//
//  MessageListView.swift
//  bitchat
//
//  Created by Islam on 30/03/2026.
//

import BitFoundation
import CoreBluetooth
import SwiftUI

private struct MessageDisplayItem: Identifiable {
    let id: String
    let message: BitchatMessage
    /// Whether the row opens a run of bubbles from one sender (see
    /// `MessageRunPolicy`).
    let startsRun: Bool
    /// Whether the row closes its run, which puts the sender's avatar
    /// beside it. The next row decides, so it starts true for the newest.
    var endsRun = true
    /// Whether the row opens a time group, which shows the time above it
    /// (see `MessageTimeLabel`).
    let startsTimeGroup: Bool
}

/// What the list's change detection keys on. The count alone stops moving
/// once the store's cap evicts the oldest message on every append, so the IDs
/// at both ends ride along, and the context key makes a switch to another
/// timeline one change even between two empty ones. The DM peer rides along
/// because the deprecated `onChange(of:perform:)` runs the closure from the
/// previous render, whose `privatePeer` is still the old one right after a
/// DM switch.
private struct TimelineSignature: Equatable {
    let privatePeer: PeerID?
    let contextKey: String
    // periphery:ignore - read only via the synthesized Equatable
    // conformance (onChange's comparison), which the indexer cannot
    // attribute.
    let count: Int
    // periphery:ignore - see `count`.
    let firstMessageID: String?
    // periphery:ignore - see `count`.
    let lastMessageID: String?

    init(privatePeer: PeerID?, contextKey: String, messages: [BitchatMessage]) {
        self.privatePeer = privatePeer
        self.contextKey = contextKey
        count = messages.count
        firstMessageID = messages.first?.id
        lastMessageID = messages.last?.id
    }
}

/// The message the full emoji picker is open for.
struct ReactionPickerTarget: Identifiable {
    let message: BitchatMessage
    var id: String { message.id }
}

struct MessageListView: View {
    @EnvironmentObject private var publicChatModel: PublicChatModel
    @EnvironmentObject private var privateInboxModel: PrivateInboxModel
    @EnvironmentObject private var privateConversationModel: PrivateConversationModel
    @EnvironmentObject private var conversationUIModel: ConversationUIModel
    @EnvironmentObject private var locationChannelsModel: LocationChannelsModel
    @EnvironmentObject private var appChromeModel: AppChromeModel
    @ObservedObject private var nearbyNotes = NearbyNotesCounter.shared

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.resolvedMessageBubbleColor) private var messageBubbleColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let privatePeer: PeerID?
    @Binding var isAtBottom: Bool
    @Binding var messageText: String
    @Binding var selectedMessageSender: String?
    @Binding var selectedMessageSenderID: PeerID?
    @Binding var imagePreviewURL: URL?
    @Binding var windowCountPublic: Int
    @Binding var windowCountPrivate: [PeerID: Int]

    var isTextFieldFocused: FocusState<Bool>.Binding

    @State private var showMessageActions = false
    @State private var showCreateGroupPrompt = false
    @State private var newGroupName = ""
    @State private var createGroupPeerID: PeerID?
    @State private var createGroupPeerName = ""
    @State private var showClearConfirmation = false
    /// macOS: the message under the pointer, and the one whose quick
    /// reaction bar shows (after a short delay, never while scrolling).
    @State private var hoveredReactionMessageID: String?
    @State private var reactionBarMessageID: String?
    @State private var reactionBarTask: Task<Void, Never>?
    /// The quick bar's own popover is open, so the bar stays.
    @State private var isReactionBarPinned = false
    @State private var isListScrolling = false
    /// The message the full emoji picker reacts to: a sheet on iOS, a
    /// popover anchored to the message on macOS (from its context menu).
    @State private var reactionPickerTarget: ReactionPickerTarget?
    /// The message whose long-press overlay is open (iOS 16.4+).
    @State private var actionsOverlayItem: MessageActionsOverlayItem?
    @State private var lastScrollTime: Date = .distantPast
    @State private var scrollThrottleTimer: Timer?
    @State private var unseenCount = 0
    /// The timeline as of the last change this list observed: its newest
    /// message (the next change counts what landed after it) and the
    /// window's first row (kept in place while the reader is scrolled up).
    /// Marks are per context: channel switches swap the timeline wholesale,
    /// so a difference only means "new messages" within one context. Its
    /// context is the one the list has landed in; row callbacks from any
    /// other timeline are ignored.
    @State private var timelineMark: MessageListScrollPolicy.TimelineMark?
    /// Row whose appearance last put the list at the bottom, cleared when it
    /// leaves the screen. Its leaving means the reader scrolled up, even while
    /// a newer row that landed below it has not appeared yet.
    @State private var bottomRowID: String?
    /// Set while an expansion's position-restoring scroll is still queued.
    @State private var isRestoringExpansion = false
    /// Context whose newest row has appeared since the list appeared or
    /// landed in it, i.e. whose scroll to the bottom has landed. Window
    /// expansion waits for it.
    @State private var bottomSettledContextKey: String?
    /// Whether this instance holds the nearby-notes counter active (mesh
    /// public timeline only); balanced against activate/deactivate.
    @State private var holdsNotesCounter = false

    @ThemedPalette private var palette

    var body: some View {
        let currentWindowCount = windowCount(for: privatePeer)

        let messages = conversationMessages(for: privatePeer)
        let reactionProjection = MessageReactionProjection(
            messages: messages,
            isMine: conversationUIModel.isSentByCurrentUser,
            displayName: conversationUIModel.displayName
        )
        let contextKey = timelineContextKey(for: privatePeer)
        // While the reader is scrolled up, messages landing below the
        // window's first row widen the window in this same render instead of
        // pushing that row out of the top, which would shift what they are
        // reading (onTimelineChange then records the wider window).
        let renderedWindowCount = isAtBottom
            ? currentWindowCount
            : MessageListScrollPolicy.windowCountKeepingFirstRow(
                current: currentWindowCount,
                mark: contextMark(for: contextKey),
                appendedCount: 0,
                in: messages
            )
        let windowedMessages = Array(messages.suffix(renderedWindowCount))

        let messageItems = displayItems(for: windowedMessages, of: messages, contextKey: contextKey)
        // Top edge of the rendered window (whitespace-only messages get no
        // row, so they could never report reaching it).
        let firstRowID = messageItems.first?.id

        VStack(spacing: 0) {
        // Notes pinned to this place stay visible while chatting — a
        // conversation starting must not hide what's left here.
        if privatePeer == nil,
           case .mesh = locationChannelsModel.selectedChannel,
           nearbyNotes.noteCount > 0 {
            notesHereStrip
        }
        GeometryReader { geometry in
        // Rows are inset 12pt on each side.
        let maxBubbleWidth = MessageBubbleStyle.maxBubbleWidth(rowWidth: geometry.size.width - 24)
        ScrollViewReader { proxy in
            ScrollView {
                if messageItems.isEmpty && privatePeer == nil {
                    publicEmptyState(fillHeight: geometry.size.height)
                }
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(messageItems) { item in
                        let message = item.message
                        let isSelf = conversationUIModel.isSentByCurrentUser(message)
                        let showsSender = isMultiPersonConversation && !isSelf && message.sender != "system"
                        messageRow(
                            for: message,
                            isSelf: isSelf,
                            showsSenderName: item.startsRun && showsSender,
                            avatar: showsSender ? (item.endsRun ? .shown : .space) : .absent,
                            maxBubbleWidth: maxBubbleWidth,
                            endsRun: item.endsRun,
                            reactions: reactionProjection.summaries(for: message.id)
                        )
                            .onAppear {
                                // Callbacks lag a timeline switch: the new
                                // rows appear before the old ones disappear,
                                // each with its own render's view of which row
                                // was last. Only rows of the timeline the list
                                // has landed in may move its state, checked
                                // against live state rather than the render's.
                                guard isLandedRow(item.id) else { return }
                                if item.id == newestRowID(for: privatePeer) {
                                    isAtBottom = true
                                    unseenCount = 0
                                    if bottomRowID != item.id {
                                        bottomRowID = item.id
                                    }
                                    if bottomSettledContextKey != contextKey {
                                        bottomSettledContextKey = contextKey
                                    }
                                    returnWindowToInitialSize(for: privatePeer, contextKey: contextKey, messages: messages)
                                }
                                if item.id == firstRowID,
                                   messages.count > windowedMessages.count {
                                    expandWindow(
                                        ifNeededFor: message,
                                        allMessages: messages,
                                        privatePeer: privatePeer,
                                        proxy: proxy
                                    )
                                }
                            }
                            .onDisappear {
                                // A row of the landed timeline shares this
                                // closure's peer, so newestRowID is live here.
                                guard isLandedRow(item.id) else { return }
                                if item.id == newestRowID(for: privatePeer) || item.id == bottomRowID {
                                    isAtBottom = false
                                    bottomRowID = nil
                                    // Leaving the bottom drops a follow-scroll
                                    // still waiting on the throttle: it would
                                    // yank the reader back down.
                                    cancelFollowScroll()
                                }
                            }
                            .messageExactTimeHelp(message.timestamp)
                            // The menu belongs to the bubble, not the empty
                            // side of the row.
                            .contentShape(Rectangle())
                            // iOS 16.4+: a long press opens the Liquid Glass
                            // overlay; elsewhere the native context menu.
                            .modifier(MessageMenuModifier(onLongPress: { frame in
                                presentActionsOverlay(
                                    for: message,
                                    isSelf: isSelf,
                                    frame: frame,
                                    reactions: reactionProjection.summaries(for: message.id),
                                    content: AnyView(messageRow(
                                        for: message,
                                        isSelf: isSelf,
                                        showsSenderName: item.startsRun && showsSender,
                                        avatar: showsSender ? (item.endsRun ? .shown : .space) : .absent,
                                        maxBubbleWidth: maxBubbleWidth,
                                        endsRun: item.endsRun,
                                        reactions: reactionProjection.summaries(for: message.id)
                                    ))
                                )
                            }) {
                                if canReact(to: message) {
                                    Section {
                                        ReactionMenuRow(
                                            selected: ownReactionEmojis(in: reactionProjection.summaries(for: message.id)),
                                            tint: messageBubbleColor,
                                            onSelect: { emoji in toggleReaction(emoji, on: message) },
                                            onOpenPicker: { openReactionPicker(for: message) }
                                        )
                                    }
                                }
                                // The exact time, which no longer sits beside
                                // each bubble.
                                Section {
                                    Text(verbatim: MessageTimeLabel.exactLabel(for: message.timestamp))
                                }
                                MessageActionMenuItems(actions: messageActions(for: message, isSelf: isSelf))
                            })
                            // VoiceOver reaches every action and the quick
                            // reactions without the overlay or the menu.
                            .accessibilityActions {
                                if canReact(to: message) {
                                    ForEach(MessageReaction.emojis, id: \.self) { emoji in
                                        Button(emoji) { toggleReaction(emoji, on: message) }
                                    }
                                    Button(String(localized: "content.reaction.add", comment: "Menu item or title for adding a reaction to a message")) {
                                        openReactionPicker(for: message)
                                    }
                                }
                                ForEach(messageActions(for: message, isSelf: isSelf)) { action in
                                    Button(action.title, action: action.perform)
                                }
                            }
#if os(macOS)
                            // The context menu's "+" opens the full picker
                            // anchored to the message.
                            .popover(isPresented: reactionPickerBinding(for: message), arrowEdge: .bottom) {
                                if let target = reactionPickerTarget {
                                    reactionPicker(for: target)
                                }
                            }
                            // The bar sits in the free space beside the
                            // bubble, so hovering anywhere on the row (bar
                            // included) keeps it.
                            .reactionQuickBar(
                                alignment: rowAlignment(for: message, isSelf: isSelf).horizontal,
                                isShown: reactionBarMessageID == message.id && message.sender != "system" && !message.isUnsentLocationMessage
                            ) {
                                ReactionQuickBar(
                                    selected: ownReactionEmojis(in: reactionProjection.summaries(for: message.id)),
                                    tint: messageBubbleColor,
                                    isPresentingChoices: $isReactionBarPinned
                                ) { emoji in
                                    toggleReaction(emoji, on: message)
                                }
                            }
                            .onHover { hovering in
                                updateReactionHover(hovering, on: message)
                            }
#endif
                            .frame(maxWidth: .infinity, alignment: rowAlignment(for: message, isSelf: isSelf))
                            .padding(.horizontal, 12)
                            // A run of bubbles from one sender reads as a
                            // group: tight within, a wider gap above it.
                            .padding(.top, item.startsRun ? 8 : 2)
                            .padding(.bottom, item.endsRun ? 6 : 1)
                            // No row background: bubbles sit straight on the
                            // backdrop. Archived echoes are told apart by
                            // their dimming (messageRow) alone.
                            .messageTimeHeader(item.startsTimeGroup ? message.timestamp : nil)
                    }
                }
                .padding(.vertical, 6)
                // A loaded GIF opens in the same preview as an image.
                .environment(\.openMediaPreview) { url in
                    imagePreviewURL = url
                }

                // Only carried history on screen: the ambient layer (radar,
                // sightings, live hints) stays visible below it instead of
                // vanishing the moment echoes exist.
                if privatePeer == nil, showsAmbientFooter(messageItems: messageItems) {
                    MeshEmptyStateView(compact: true, bluetoothAvailable: bluetoothCanScan)
                        .padding(.horizontal, 12)
                        .padding(.top, 20)
                        .padding(.bottom, 8)
                }
            }
#if os(macOS)
            .onScrollPhaseChange { _, phase in
                updateReactionBarForScrolling(phase.isScrolling)
            }
#endif
#if os(iOS)
            // A drag through the conversation puts the keyboard away, as in
            // Messages; the draft stays in the composer. The list's own
            // scrolls (new messages, the jump to the latest) are no drag
            // and leave the keyboard up. The composer sits outside this
            // scroll view, so its own scrolling keeps the keyboard too.
            .scrollDismissesKeyboard(.immediately)
#endif
            .overlay(alignment: .bottomTrailing) {
                if !isAtBottom && !messageItems.isEmpty {
                    jumpToLatestPill(proxy: proxy)
                }
            }
            .onOpenURL(perform: handleOpenURL)
#if os(iOS)
            .sheet(item: $reactionPickerTarget) { target in
                reactionPicker(for: target)
                    .presentationDetents([.medium, .large])
            }
            .fullScreenCover(item: $actionsOverlayItem) { item in
                actionsOverlay(for: item)
            }
#endif
            .onTapGesture(count: 3) {
                showClearConfirmation = true
            }
            .confirmationDialog(
                "content.clear.confirm_title",
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("content.clear.confirm_action", role: .destructive) {
                    conversationUIModel.clearCurrentConversation()
                }
                Button("common.cancel", role: .cancel) {}
            }
            .onAppear {
                // Runs before the rows' onAppear: lands the list (and sets the
                // mark the row callbacks are checked against) before any row
                // reports in. Expansion waits until the scroll below has
                // brought the newest row on screen.
                bottomSettledContextKey = nil
                scrollToBottom(on: proxy, privatePeer: privatePeer)
            }
            // The one change handler: a channel or DM switch changes the
            // signature too, so landing in the new timeline happens here,
            // ahead of that update's row callbacks.
            .onChange(of: TimelineSignature(privatePeer: privatePeer, contextKey: contextKey, messages: messages)) { signature in
                onTimelineChange(signature, proxy: proxy)
            }
            .confirmationDialog(
                selectedMessageSender.map { "@\($0)" } ?? String(localized: "content.actions.title", comment: "Fallback title for the message action sheet"),
                isPresented: $showMessageActions,
                titleVisibility: .visible
            ) {
                Button("content.actions.mention") {
                    if let sender = selectedMessageSender {
                        insertMention(sender)
                    }
                }

                Button("content.actions.direct_message") {
                    if let peerID = selectedMessageSenderID {
                        privateConversationModel.openConversation(for: peerID)
                    }
                }

                if let peerID = selectedMessageSenderID, conversationUIModel.canCreateGroup(with: peerID) {
                    Button {
                        createGroupPeerID = peerID
                        createGroupPeerName = selectedMessageSender ?? ""
                        newGroupName = GroupManagementPolicy.defaultName(with: createGroupPeerName)
                        showCreateGroupPrompt = true
                    } label: {
                        Text(verbatim: String(format: String(localized: "group.action.create_with_peer"), selectedMessageSender ?? ""))
                    }
                    .accessibilityLabel(Text(verbatim: String(format: String(localized: "group.action.create_with_peer"), selectedMessageSender ?? "")))
                }

                Button("content.actions.block", role: .destructive) {
                    conversationUIModel.block(peerID: selectedMessageSenderID, displayName: selectedMessageSender)
                }

                Button("common.cancel", role: .cancel) {}
            }
            .alert("group.create.title", isPresented: $showCreateGroupPrompt) {
                TextField("group.create.name", text: $newGroupName)
                Button("common.cancel", role: .cancel) { createGroupPeerID = nil }
                Button("group.create.action") {
                    guard let peerID = createGroupPeerID else { return }
                    _ = conversationUIModel.createGroup(named: newGroupName, inviting: peerID)
                    createGroupPeerID = nil
                }
            } message: {
                Text("group.create.prompt")
            }
            .onAppear {
                // Also check when view appears
                if let peerID = privatePeer {
                    // Try multiple times to ensure read receipts are sent
                    privateConversationModel.markMessagesAsRead(from: peerID)

                    DispatchQueue.main.asyncAfter(deadline: .now() + TransportConfig.uiReadReceiptRetryShortSeconds) {
                        privateConversationModel.markMessagesAsRead(from: peerID)
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + TransportConfig.uiReadReceiptRetryLongSeconds) {
                        privateConversationModel.markMessagesAsRead(from: peerID)
                    }
                }
            }
            .onDisappear {
                cancelFollowScroll()
            }
        }
        }
        }
        .onAppear { updateNotesCounterHold() }
        .onDisappear { releaseNotesCounterHold() }
#if os(macOS)
        // Where the Character Viewer types a reaction picked from it.
        .background { CharacterViewerHost() }
#endif
        .onChange(of: locationChannelsModel.selectedChannel) { _ in updateNotesCounterHold() }
        .onChange(of: privatePeer) { _ in updateNotesCounterHold() }
        .environment(\.openURL, OpenURLAction { url in
            // Intercept custom cashu: links created in attributed text
            if let scheme = url.scheme?.lowercased(), scheme == "cashu" || scheme == "lightning" {
                #if os(iOS)
                UIApplication.shared.open(url)
                return .handled
                #else
                // On non-iOS platforms, let the system handle or ignore
                return .systemAction
                #endif
            }
            return .systemAction
        })
    }
}

private extension MessageListView {
    /// Whether the radio could be scanning at all — the empty-state radar
    /// must not sweep over a switched-off or denied radio.
    var bluetoothCanScan: Bool {
        switch appChromeModel.bluetoothState {
        case .poweredOff, .unauthorized, .unsupported: return false
        default: return true
        }
    }

    /// Context key of the timeline shown for `privatePeer` (the DM, or the
    /// public channel); also the prefix of its row IDs. The public key comes
    /// from the channel PublicChatModel publishes together with its messages:
    /// the selected channel switches one render or more before the timeline
    /// does, and keying the old messages with the new channel re-keys (and
    /// re-appears) every row.
    func timelineContextKey(for privatePeer: PeerID?) -> String {
        if let peer = privatePeer {
            return "dm:\(peer)"
        }
        return publicChatModel.activeChannel.contextKey
    }

    func windowCount(for privatePeer: PeerID?) -> Int {
        if let peer = privatePeer {
            return windowCountPrivate[peer] ?? TransportConfig.uiWindowInitialCountPrivate
        }
        return windowCountPublic
    }

    func setWindowCount(_ count: Int, for privatePeer: PeerID?) {
        if let peer = privatePeer {
            windowCountPrivate[peer] = count
        } else {
            windowCountPublic = count
        }
    }

    /// Returns the window to its initial size once the reader is back at the
    /// bottom (the newest row has appeared): whatever it grew by while they
    /// were scrolled up, or expanded into history, need not stay rendered,
    /// and dropping rows above the bottom moves nothing on screen. Never in
    /// the same update as a scroll: rows changing above the viewport make
    /// SwiftUI hold its position, and a pending scrollTo never lands.
    func returnWindowToInitialSize(for privatePeer: PeerID?, contextKey: String, messages: [BitchatMessage]) {
        let initialCount = privatePeer == nil
            ? TransportConfig.uiWindowInitialCountPublic
            : TransportConfig.uiWindowInitialCountPrivate
        guard windowCount(for: privatePeer) > initialCount else { return }
        setWindowCount(initialCount, for: privatePeer)
        timelineMark = contextMark(for: contextKey)?.withWindowCount(initialCount, in: messages)
    }

    /// The timeline mark, if it was taken in `contextKey`.
    func contextMark(for contextKey: String) -> MessageListScrollPolicy.TimelineMark? {
        guard let timelineMark, timelineMark.contextKey == contextKey else { return nil }
        return timelineMark
    }

    /// Whether a row belongs to the timeline the list has landed in (the
    /// mark's context: the change handler lands a switch before the rows of
    /// that update report in).
    func isLandedRow(_ rowID: String) -> Bool {
        guard let landedContextKey = timelineMark?.contextKey else { return false }
        return MessageListScrollPolicy.isRow(rowID, inContext: landedContextKey)
    }

    /// Tappable strip above the mesh timeline while notes are pinned at this
    /// place: opens the notices sheet on the geo tab.
    var notesHereStrip: some View {
        let text: String = nearbyNotes.noteCount == 1
            ? String(localized: "content.empty.notes_one", comment: "Hint when exactly one note was left at this place")
            : String(
                format: String(localized: "content.empty.notes_many", comment: "Hint counting notes left at this place"),
                locale: .current,
                nearbyNotes.noteCount
            )

        return Button {
            appChromeModel.presentNotices(geoTab: true)
        } label: {
            ChatBanner(systemImage: "mappin.and.ellipse", symbolColor: palette.accent, showsChevron: true) {
                Text(verbatim: text)
                    .font(.footnote)
                    .foregroundStyle(palette.primary)
            }
        }
        .buttonStyle(.plain)
    }

    /// The nearby-notes counter is held whenever the mesh public timeline is
    /// showing — the strip needs a live count before it can decide to exist.
    /// Holding is not subscribing: nothing hits the relays until an explicit
    /// act reveals the counter (tap-to-reveal).
    func updateNotesCounterHold() {
        let shouldHold = privatePeer == nil && locationChannelsModel.selectedChannel.isMesh
        guard shouldHold != holdsNotesCounter else { return }
        holdsNotesCounter = shouldHold
        if shouldHold {
            NearbyNotesCounter.shared.activate()
        } else {
            NearbyNotesCounter.shared.deactivate()
        }
    }

    func releaseNotesCounterHold() {
        guard holdsNotesCounter else { return }
        holdsNotesCounter = false
        NearbyNotesCounter.shared.deactivate()
    }

    /// True when the mesh timeline holds nothing but archived echoes and
    /// system lines — no live conversation yet, so the ambient layer still
    /// applies.
    private func showsAmbientFooter(messageItems: [MessageDisplayItem]) -> Bool {
        guard case .mesh = locationChannelsModel.selectedChannel,
              !messageItems.isEmpty else { return false }
        return messageItems.allSatisfy { $0.message.isArchivedEcho || $0.message.sender == "system" }
    }

    /// The empty public timeline, centered as the system's empty states
    /// are: which channel this is and who it reaches. Rendered inside the
    /// ScrollView; it goes away with the first row. It fills the visible
    /// chat height, so it sits in the middle of the screen.
    @ViewBuilder
    func publicEmptyState(fillHeight: CGFloat) -> some View {
        switch locationChannelsModel.selectedChannel {
        case .mesh:
            MeshEmptyStateView(
                fillHeight: max(0, fillHeight - 24),
                bluetoothAvailable: bluetoothCanScan
            )
            .padding(.horizontal, 12)
        case .location(let channel):
            VStack {
                Spacer(minLength: 24)
                ChatEmptyStateHeader(
                    title: "#\(channel.geohash)",
                    message: String(
                        format: String(localized: "content.empty.location_intro", comment: "First line of an empty geohash timeline naming the channel"),
                        locale: .current,
                        channel.geohash
                    )
                ) {
                    ChatEmptyStateSymbol(systemImage: "mappin.and.ellipse")
                }
                Spacer(minLength: 24)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: max(0, fillHeight - 24))
        }
    }

    /// A failed private text message of our own can be resent through the
    /// normal send path (the context menu removes the failed original and
    /// re-submits its content). So can a location message of ours that never
    /// went out: it shows only in its own channel's timeline, so the normal
    /// send path sends it to that channel.
    func isResendableFailedMessage(_ message: BitchatMessage) -> Bool {
        guard message.isPrivate || (privatePeer == nil && message.isUnsentLocationMessage),
              conversationUIModel.isSentByCurrentUser(message),
              conversationUIModel.mediaAttachment(for: message) == nil,
              case .failed = message.deliveryStatus
        else { return false }
        return true
    }

    /// Appends an @mention to the composer draft (never overwrites what the
    /// user has already typed) and focuses the input field.
    func insertMention(_ sender: String) {
        let mention = "@\(sender) "
        if messageText.isEmpty {
            messageText = mention
        } else if messageText.hasSuffix(" ") {
            messageText += mention
        } else {
            messageText += " " + mention
        }
        isTextFieldFocused.wrappedValue = true
    }

    /// Floating pill shown while scrolled up: re-presents the isAtBottom /
    /// unseenCount state the view already tracks, and jumps to the newest
    /// message via the existing scrollToBottom helper.
    func jumpToLatestPill(proxy: ScrollViewProxy) -> some View {
        Button {
            scrollToBottom(on: proxy, privatePeer: privatePeer)
        } label: {
            // Same size as the composer's image button: a 40pt glass circle,
            // stretching into a capsule when it also shows the new count.
            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                    .font(.callout.weight(.semibold))
                if unseenCount > 0 {
                    Text(
                        String(
                            format: String(localized: "content.jump.new_count", comment: "Count of messages that arrived while scrolled up, shown in the jump-to-latest pill"),
                            locale: .current,
                            unseenCount
                        )
                    )
                    .font(.subheadline.weight(.medium))
                }
            }
            .foregroundColor(palette.primary)
            .padding(.horizontal, unseenCount > 0 ? 14 : 0)
            .frame(minWidth: 40, minHeight: 40)
            .glassSurface(in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 12)
        .padding(.bottom, 10)
        .accessibilityLabel(jumpToLatestAccessibilityLabel)
    }

    var jumpToLatestAccessibilityLabel: String {
        let base = String(localized: "content.accessibility.jump_to_latest", comment: "Accessibility label for the jump to latest messages button")
        guard unseenCount > 0 else { return base }
        let count = String(
            format: String(localized: "content.jump.new_count", comment: "Count of messages that arrived while scrolled up, shown in the jump-to-latest pill"),
            locale: .current,
            unseenCount
        )
        return "\(base), \(count)"
    }

    /// Whether several people talk here: a public channel or a group
    /// chat, not a 1:1 private chat. Other people's bubbles then show who
    /// sent them: the name above a run, the avatar beside it.
    var isMultiPersonConversation: Bool {
        privatePeer.map(\.isGroup) ?? true
    }

    /// System lines sit centered; bubbles sit on their sender's side, mine
    /// on the right.
    func rowAlignment(for message: BitchatMessage, isSelf: Bool) -> Alignment {
        if message.sender == "system" { return .center }
        return isSelf ? .trailing : .leading
    }

    /// The rows of the rendered window, each marked with whether it opens a
    /// run and a time group, and whether it closes its run. The message just
    /// above the window decides both openings for its first row, so a window
    /// that grows or shrinks never regroups a row. The window always ends at
    /// the newest message, so its last row closes its run.
    func displayItems(
        for windowedMessages: [BitchatMessage],
        of messages: [BitchatMessage],
        contextKey: String
    ) -> [MessageDisplayItem] {
        let firstIndex = messages.count - windowedMessages.count
        var previous = firstIndex > 0 ? messages[firstIndex - 1] : nil
        var items: [MessageDisplayItem] = []
        items.reserveCapacity(windowedMessages.count)
        // Whitespace-only messages get no row, and neither do reaction
        // lines: they show as pills under their target, or not at all
        // while the target is missing.
        for message in windowedMessages where Self.rendersRow(message) {
            let startsRun = MessageRunPolicy.startsRun(message, after: previous)
            if !items.isEmpty {
                items[items.count - 1].endsRun = startsRun
            }
            items.append(MessageDisplayItem(
                id: "\(contextKey)|\(message.id)",
                message: message,
                startsRun: startsRun,
                startsTimeGroup: MessageTimeLabel.startsTimeGroup(message, after: previous)
            ))
            previous = message
        }
        return items
    }

    /// Whether a message gets a row: not whitespace-only, not a reaction
    /// line.
    static func rendersRow(_ message: BitchatMessage) -> Bool {
        !message.content.trimmed.isEmpty && !message.isReactionLine
    }

    /// What sits left of a row's bubble.
    enum AvatarSlot {
        /// No column: my bubbles, system lines, and 1:1 chats.
        case absent
        /// The sender's avatar, on the last row of their run.
        case shown
        /// An empty column as wide as the avatar, which keeps the other
        /// rows of the run lined up with the last.
        case space
    }

    @ViewBuilder
    func messageRow(
        for message: BitchatMessage,
        isSelf: Bool,
        showsSenderName: Bool,
        avatar: AvatarSlot,
        maxBubbleWidth: CGFloat,
        endsRun: Bool,
        reactions: [MessageReactionSummary] = []
    ) -> some View {
        Group {
            if avatar == .absent {
                messageContent(for: message, isSelf: isSelf, showsSenderName: showsSenderName, maxBubbleWidth: maxBubbleWidth, endsRun: endsRun, reactions: reactions)
            } else {
                // The avatar lines up with the bottom of the bubble, as in
                // Messages, not with anything below it (payment chips).
                HStack(alignment: .messageBubbleBottom, spacing: MessageBubbleStyle.avatarSpacing) {
                    senderAvatar(for: message, isShown: avatar == .shown)
                    messageContent(for: message, isSelf: isSelf, showsSenderName: showsSenderName, maxBubbleWidth: maxBubbleWidth, endsRun: endsRun, reactions: reactions)
                }
            }
        }
        // Archived echoes ("heard here earlier") render dimmed: real history,
        // visually distinct from the live conversation. They start a run of
        // their own (MessageRunPolicy), so the sender's name shows again
        // where the live conversation picks up.
        .opacity(message.isArchivedEcho ? 0.55 : 1)
    }

    /// The message and, under its bubble, its reaction pills. The pills
    /// line up with the bubble's edge and wrap within the bubble's width.
    @ViewBuilder
    func messageContent(
        for message: BitchatMessage,
        isSelf: Bool,
        showsSenderName: Bool,
        maxBubbleWidth: CGFloat,
        endsRun: Bool,
        reactions: [MessageReactionSummary] = []
    ) -> some View {
        if message.sender == "system" {
            systemMessageRow(message)
        } else {
            VStack(alignment: isSelf ? .trailing : .leading, spacing: MessageReactionStyle.bubbleGap) {
                messageBody(for: message, isSelf: isSelf, showsSenderName: showsSenderName, maxBubbleWidth: maxBubbleWidth, endsRun: endsRun)
                if !reactions.isEmpty {
                    MessageReactionsView(
                        summaries: reactions,
                        isSelf: isSelf,
                        maxWidth: maxBubbleWidth,
                        tint: messageBubbleColor,
                        onToggle: { emoji in toggleReaction(emoji, on: message) },
                        onOpenPicker: { openReactionPicker(for: message) }
                    )
                    .transition(MessageReactionStyle.transition(reduceMotion: reduceMotion))
                }
            }
            // The first reaction grows the row smoothly instead of making
            // it jump.
            .animation(MessageReactionStyle.animation(reduceMotion: reduceMotion), value: reactions.isEmpty)
        }
    }

    @ViewBuilder
    func messageBody(
        for message: BitchatMessage,
        isSelf: Bool,
        showsSenderName: Bool,
        maxBubbleWidth: CGFloat,
        endsRun: Bool
    ) -> some View {
        if let media = conversationUIModel.mediaAttachment(for: message) {
            MediaMessageView(
                message: message,
                media: media,
                imagePreviewURL: $imagePreviewURL,
                isSelf: isSelf,
                showsSenderName: showsSenderName,
                maxBubbleWidth: maxBubbleWidth
            )
        } else {
            TextMessageView(
                message: message,
                isSelf: isSelf,
                showsSenderName: showsSenderName,
                maxBubbleWidth: maxBubbleWidth,
                hasTail: endsRun
            )
        }
    }

    func ownReactionEmojis(in reactions: [MessageReactionSummary]) -> Set<String> {
        Set(reactions.filter(\.includesMe).map(\.emoji))
    }

#if os(macOS)
    /// Shows the quick bar for the message under the pointer after a short
    /// delay, or at once when it moves over from another message, and hides
    /// it a moment after the pointer leaves (so it can cross a gap).
    func updateReactionHover(_ hovering: Bool, on message: BitchatMessage) {
        // A location message that never went out has no event anyone could
        // react to.
        guard message.sender != "system", !message.isUnsentLocationMessage else { return }
        if hovering {
            hoveredReactionMessageID = message.id
            reactionBarTask?.cancel()
            guard !isListScrolling, !isReactionBarPinned else { return }
            if reactionBarMessageID != nil {
                reactionBarMessageID = message.id
            } else {
                showReactionBar(for: message.id, after: 0.35)
            }
        } else if hoveredReactionMessageID == message.id {
            hoveredReactionMessageID = nil
            reactionBarTask?.cancel()
            reactionBarTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled, hoveredReactionMessageID == nil, !isReactionBarPinned else { return }
                reactionBarMessageID = nil
            }
        }
    }

    func showReactionBar(for messageID: String, after delay: TimeInterval) {
        reactionBarTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, hoveredReactionMessageID == messageID, !isListScrolling else { return }
            reactionBarMessageID = messageID
        }
    }

    /// Scrolling hides the bar; when it stops, the message under the pointer
    /// gets the bar again after the usual delay.
    func updateReactionBarForScrolling(_ isScrolling: Bool) {
        guard isScrolling != isListScrolling else { return }
        isListScrolling = isScrolling
        reactionBarTask?.cancel()
        if isScrolling {
            guard !isReactionBarPinned else { return }
            reactionBarMessageID = nil
        } else if let hovered = hoveredReactionMessageID {
            showReactionBar(for: hovered, after: 0.35)
        }
    }
#endif

    func toggleReaction(_ emoji: String, on message: BitchatMessage) {
        let ownEvents = MessageReaction.resolvedEvents(in: conversationMessages(for: privatePeer))
            .filter { $0.event.targetID == message.id && conversationUIModel.isSentByCurrentUser($0.message) }
        let active = ownEvents.last(where: { $0.event.emoji == emoji })?.event.removes == false
        if !active {
            ReactionEmojiPreferences.shared.recordUse(emoji)
        }
        conversationUIModel.sendMessage(MessageReaction.format(emoji: emoji, target: message, removes: active))
    }

    /// Whether a message takes reactions: not a system line, and not a
    /// location message that never went out (it has no event to react to).
    func canReact(to message: BitchatMessage) -> Bool {
        message.sender != "system" && !message.isUnsentLocationMessage
    }

    /// What I can do with a message, in menu order.
    func messageActions(for message: BitchatMessage, isSelf: Bool) -> [MessageAction] {
        var actions: [MessageAction] = []
        if isResendableFailedMessage(message) {
            actions.append(MessageAction(kind: .resend) {
                if message.isPrivate {
                    conversationUIModel.resendFailedPrivateMessage(message)
                } else {
                    conversationUIModel.resendFailedLocationMessage(message)
                }
            })
        }
        let showsUserActions = message.sender != "system" && !isSelf
        // Mention and DM are redundant inside a 1:1 conversation:
        // mentioning the only other participant is noise, and "DM" would
        // just reopen the conversation that is already open.
        if showsUserActions && privatePeer == nil {
            actions.append(MessageAction(kind: .mention) { insertMention(message.sender) })
            if let peerID = message.senderPeerID {
                actions.append(MessageAction(kind: .directMessage) {
                    privateConversationModel.openConversation(for: peerID)
                })
            }
        }
        actions.append(MessageAction(kind: .copy) {
            #if os(iOS)
            UIPasteboard.general.string = message.content
            #else
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(message.content, forType: .string)
            #endif
        })
        if showsUserActions {
            actions.append(MessageAction(kind: .block) {
                conversationUIModel.block(peerID: message.senderPeerID, displayName: message.sender)
            })
        }
        return actions
    }

    /// Opens the long-press overlay (iOS 16.4+) with a light tap.
    func presentActionsOverlay(
        for message: BitchatMessage,
        isSelf: Bool,
        frame: CGRect,
        reactions: [MessageReactionSummary],
        content: AnyView
    ) {
        #if os(iOS)
        guard frame.width > 0 else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let item = MessageActionsOverlayItem(
            message: message,
            messageFrame: frame,
            isSelf: isSelf,
            canReact: canReact(to: message),
            selectedReactions: ownReactionEmojis(in: reactions),
            actions: messageActions(for: message, isSelf: isSelf),
            content: content
        )
        // The overlay animates itself; the cover appears and goes at once.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { actionsOverlayItem = item }
        #endif
    }

    func openReactionPicker(for message: BitchatMessage) {
        reactionPickerTarget = ReactionPickerTarget(message: message)
    }

#if os(iOS)
    @ViewBuilder
    func actionsOverlay(for item: MessageActionsOverlayItem) -> some View {
        if #available(iOS 16.4, *) {
            MessageActionsOverlay(
                item: item,
                tint: messageBubbleColor,
                onReact: { emoji in toggleReaction(emoji, on: item.message) },
                onOpenPicker: {
                    // After the cover is gone, so the sheet can present.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        openReactionPicker(for: item.message)
                    }
                },
                onDismiss: {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { actionsOverlayItem = nil }
                }
            )
            .environmentObject(conversationUIModel)
            .environment(\.resolvedMessageBubbleColor, messageBubbleColor)
            .presentationBackground(.clear)
        }
    }
#endif

    /// Whether the picker popover shows on `message`'s row (macOS).
    func reactionPickerBinding(for message: BitchatMessage) -> Binding<Bool> {
        Binding(
            get: { reactionPickerTarget?.message.id == message.id },
            set: { isPresented in
                if !isPresented, reactionPickerTarget?.message.id == message.id {
                    reactionPickerTarget = nil
                }
            }
        )
    }

    /// My current reactions on a message, for marking them in a picker.
    func ownReactionEmojis(on message: BitchatMessage) -> Set<String> {
        let projection = MessageReactionProjection(
            messages: conversationMessages(for: privatePeer),
            isMine: conversationUIModel.isSentByCurrentUser,
            displayName: conversationUIModel.displayName
        )
        return ownReactionEmojis(in: projection.summaries(for: message.id))
    }

    /// The full emoji picker for `target`. Choosing an emoji closes it.
    func reactionPicker(for target: ReactionPickerTarget) -> some View {
        EmojiPickerView(
            selected: ownReactionEmojis(on: target.message),
            tint: messageBubbleColor,
            onSelect: { emoji in
                reactionPickerTarget = nil
                toggleReaction(emoji, on: target.message)
            },
            onClose: { reactionPickerTarget = nil }
        )
    }

    /// The avatar column of a row. A tap on the avatar opens the sender's
    /// actions, as a tap on their name does. VoiceOver skips it: the name
    /// above the run already says who wrote it.
    func senderAvatar(for message: BitchatMessage, isShown: Bool) -> some View {
        ZStack {
            if isShown {
                if let peerID = message.senderPeerID {
                    Button {
                        presentSenderActions(for: peerID)
                    } label: {
                        InitialsAvatar(name: conversationUIModel.displayName(for: message), peerID: peerID, size: MessageBubbleStyle.avatarSize)
                    }
                    .buttonStyle(.plain)
                } else {
                    InitialsAvatar(name: conversationUIModel.displayName(for: message), peerID: nil, size: MessageBubbleStyle.avatarSize)
                }
            }
        }
        .frame(width: MessageBubbleStyle.avatarSize)
        .accessibilityHidden(true)
    }

    /// Status lines ("You're on #mesh") stay plain, without a bubble:
    /// centered secondary text, as Messages shows its own notices.
    func systemMessageRow(_ message: BitchatMessage) -> some View {
        Text(verbatim: message.content)
            .font(.footnote)
            .foregroundColor(palette.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)
            .padding(.vertical, 4)
    }

    func expandWindow(ifNeededFor message: BitchatMessage,
                      allMessages: [BitchatMessage],
                      privatePeer: PeerID?,
                      proxy: ScrollViewProxy) {
        let contextKey = timelineContextKey(for: privatePeer)
        guard MessageListScrollPolicy.canExpandWindow(
            isRestoringExpansion: isRestoringExpansion,
            bottomSettledContextKey: bottomSettledContextKey,
            contextKey: contextKey
        ) else { return }

        let current = windowCount(for: privatePeer)
        let newCount = min(allMessages.count, current + TransportConfig.uiWindowStepCount)
        guard newCount != current else { return }
        setWindowCount(newCount, for: privatePeer)
        // The window's first row moved up with it: re-take the mark's window
        // so a scrolled-up reader keeps holding the new first row.
        timelineMark = contextMark(for: contextKey)?.withWindowCount(newCount, in: allMessages)

        // Until the restore below lands, the rows just inserted above leave a
        // new first row on screen; it must not expand the window again.
        let preserveID = "\(contextKey)|\(message.id)"
        isRestoringExpansion = true
        DispatchQueue.main.async {
            proxy.scrollTo(preserveID, anchor: .top)
            isRestoringExpansion = false
        }
    }

    func handleOpenURL(_ url: URL) {
        guard url.scheme == "bitchat" else { return }
        switch url.host {
        case "user":
            let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            presentSenderActions(for: PeerID(str: id.removingPercentEncoding ?? id))

        case "geohash":
            let gh = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
            let allowed = Set("0123456789bcdefghjkmnpqrstuvwxyz")
            guard (2...12).contains(gh.count), gh.allSatisfy({ allowed.contains($0) }) else { return }
            locationChannelsModel.openLocationChannel(for: gh)

        default:
            return
        }
    }

    /// Opens the action sheet (mention, DM, new group, block) for the
    /// sender behind `peerID`, unless that is me. A tap on a sender's name
    /// or avatar lands here.
    func presentSenderActions(for peerID: PeerID) {
        selectedMessageSenderID = peerID
        selectedMessageSender = conversationUIModel.senderDisplayName(
            for: peerID,
            fallbackMessages: conversationMessages(for: privatePeer)
        )

        if conversationUIModel.isSelfSender(peerID: peerID, displayName: selectedMessageSender) {
            selectedMessageSender = nil
            selectedMessageSenderID = nil
        } else {
            showMessageActions = true
        }
    }

    func scrollToBottom(on proxy: ScrollViewProxy, privatePeer: PeerID?) {
        // A follow-scroll still pending (possibly for a timeline being left)
        // has nothing left to do.
        cancelFollowScroll()
        isAtBottom = true
        unseenCount = 0
        timelineMark = MessageListScrollPolicy.TimelineMark(
            contextKey: timelineContextKey(for: privatePeer),
            messages: conversationMessages(for: privatePeer),
            windowCount: windowCount(for: privatePeer)
        )
        if let target = newestRowID(for: privatePeer) {
            proxy.scrollTo(target, anchor: .bottom)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Retry only a scroll that has not landed. Once the newest row is
            // on screen the retry would be a no-op, and a no-op scrollTo stays
            // queued until the next layout pass: the reader's next drag.
            if let secondTarget = self.newestRowID(for: privatePeer),
               MessageListScrollPolicy.needsScroll(toNewestRowID: secondTarget, bottomRowID: bottomRowID) {
                proxy.scrollTo(secondTarget, anchor: .bottom)
            }
        }
    }

    /// Lands the list at the newest message of a timeline it was not showing
    /// (a channel or DM switch): nothing about the old timeline's bottom
    /// carries over.
    func land(on proxy: ScrollViewProxy, privatePeer: PeerID?) {
        bottomRowID = nil
        bottomSettledContextKey = nil
        scrollToBottom(on: proxy, privatePeer: privatePeer)
    }

    /// Row ID of the newest message that has a row (whitespace-only
    /// messages and reaction lines render none).
    func newestRowID(for privatePeer: PeerID?) -> String? {
        guard let newest = conversationMessages(for: privatePeer).last(where: Self.rendersRow) else {
            return nil
        }
        return "\(timelineContextKey(for: privatePeer))|\(newest.id)"
    }

    /// Handles any change to the shown timeline: an append, a late message
    /// inserted mid-timeline, an eviction at the cap, a removal, or a
    /// different timeline altogether (a channel or DM switch).
    func onTimelineChange(_ signature: TimelineSignature, proxy: ScrollViewProxy) {
        // The deprecated onChange runs the previous render's closure, so the
        // timeline comes from the new value rather than `self.privatePeer`.
        let privatePeer = signature.privatePeer
        let contextKey = signature.contextKey
        let messages = conversationMessages(for: privatePeer)

        // No mark in this context means the timeline was swapped wholesale:
        // nothing is booked as "new", the list lands instead.
        let mark = contextMark(for: contextKey)
        let appended = mark.map { MessageListScrollPolicy.appended(since: $0, in: messages) }
            ?? MessageListScrollPolicy.Appended()
        let currentWindowCount = windowCount(for: privatePeer)
        let reaction = MessageListScrollPolicy.reaction(
            mark: mark,
            messages: messages,
            // My reaction to an older message is no new message of mine:
            // it must not pull a scrolled-up reader to the bottom.
            newestIsOwn: messages.last.map { !$0.isReactionLine && conversationUIModel.isSentByCurrentUser($0) } ?? false,
            appendedCount: appended.total,
            windowCount: currentWindowCount,
            isAtBottom: isAtBottom
        )

        if reaction == .land {
            land(on: proxy, privatePeer: privatePeer)
            return
        }

        // Record the window this render kept: for a scrolled-up reader,
        // widened over what landed below its first row instead of dropping
        // that row (grown by the appended count if the mark lost track of
        // it). A follow keeps it too: rows changing above the viewport in the
        // same update as the scroll make SwiftUI hold its position instead.
        let keptWindowCount = isAtBottom
            ? currentWindowCount
            : MessageListScrollPolicy.windowCountKeepingFirstRow(
                current: currentWindowCount,
                mark: mark,
                appendedCount: appended.total,
                in: messages
            )
        if keptWindowCount != currentWindowCount {
            setWindowCount(keptWindowCount, for: privatePeer)
        }
        timelineMark = MessageListScrollPolicy.TimelineMark(contextKey: contextKey, messages: messages, windowCount: keptWindowCount)

        switch reaction {
        case .keepPosition:
            unseenCount += appended.unseen
        case .follow:
            // Ensure we consider ourselves at bottom for subsequent messages
            isAtBottom = true
            unseenCount = 0
            followToBottom(privatePeer: privatePeer, proxy: proxy)
        case .hold:
            if messages.isEmpty {
                // Timeline emptied (e.g. /clear): nothing below to jump to.
                unseenCount = 0
            }
        case .land:
            break
        }
    }

    /// Scrolls to the newest row, at most once per throttle interval. A
    /// throttled scroll decides when its timer fires: the timer is held back
    /// while a drag is tracking, so by then the reader may have scrolled
    /// away or switched timelines, and newer rows may have landed.
    func followToBottom(privatePeer: PeerID?, proxy: ScrollViewProxy) {
        let now = Date()
        if now.timeIntervalSince(lastScrollTime) > TransportConfig.uiScrollThrottleSeconds {
            // Immediate scroll if enough time has passed
            scrollToNewestRow(privatePeer: privatePeer, proxy: proxy, at: now)
            return
        }
        // Schedule a delayed scroll
        let scheduledContextKey = timelineContextKey(for: privatePeer)
        scrollThrottleTimer?.invalidate()
        scrollThrottleTimer = Timer.scheduledTimer(withTimeInterval: TransportConfig.uiScrollThrottleSeconds, repeats: false) { _ in
            Task { @MainActor in
                guard MessageListScrollPolicy.shouldRunDeferredFollowScroll(
                    isAtBottom: isAtBottom,
                    scheduledContextKey: scheduledContextKey,
                    currentContextKey: timelineContextKey(for: privatePeer)
                ) else { return }
                scrollToNewestRow(privatePeer: privatePeer, proxy: proxy, at: Date())
            }
        }
    }

    func scrollToNewestRow(privatePeer: PeerID?, proxy: ScrollViewProxy, at date: Date) {
        lastScrollTime = date
        if let target = newestRowID(for: privatePeer) {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }

    /// Drops a follow-scroll still waiting on the throttle.
    func cancelFollowScroll() {
        guard let timer = scrollThrottleTimer else { return }
        timer.invalidate()
        scrollThrottleTimer = nil
    }

    func conversationMessages(for privatePeer: PeerID?) -> [BitchatMessage] {
        if let privatePeer {
            return privateInboxModel.messages(for: privatePeer)
        }
        return publicChatModel.messages
    }
}

private extension ChannelID {
    var contextKey: String {
        switch self {
        case .mesh:             "mesh"
        case .location(let ch): "geo:\(ch.geohash)"
        }
    }
}

// #Preview {
//    MessageListView()
// }
