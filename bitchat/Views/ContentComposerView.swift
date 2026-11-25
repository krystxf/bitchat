import SwiftUI
import PhotosUI
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

struct ContentComposerView: View {
    @EnvironmentObject private var conversationUIModel: ConversationUIModel
    @EnvironmentObject private var privateConversationModel: PrivateConversationModel
    @EnvironmentObject private var locationChannelsModel: LocationChannelsModel
    @ObservedObject private var bridgeService = BridgeService.shared
    @ThemedPalette private var palette
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var selectedPhotoItem: PhotosPickerItem?

    @Binding var messageText: String
    var isTextFieldFocused: FocusState<Bool>.Binding
    @ObservedObject var voiceRecordingVM: VoiceRecordingViewModel
    @Binding var autocompleteDebounceTimer: Timer?

    let onSendMessage: () -> Void

    /// Drag translation of the current mic hold. Local state, so finger
    /// moves re-render only the composer; the view model hears only phase
    /// changes.
    @State private var dragTranslation: CGSize = .zero
    /// Resets when the hold ends or the system cancels it, which catches
    /// a cancelled touch that never reaches `onEnded`.
    @GestureState private var micPressed = false

    #if os(iOS)
    @Binding var showImagePicker: Bool
    @Binding var imagePickerSourceType: UIImagePickerController.SourceType
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if conversationUIModel.showAutocomplete && !conversationUIModel.autocompleteSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(conversationUIModel.autocompleteSuggestions.prefix(4).enumerated()), id: \.element) { index, suggestion in
                        Button(action: {
                            _ = conversationUIModel.completeNickname(suggestion, in: &messageText)
                        }) {
                            HStack {
                                Text(suggestion)
                                    .bitchatFont(size: 11)
                                    .foregroundColor(palette.primary)
                                    .fontWeight(.medium)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                index == conversationUIModel.selectedAutocompleteIndex
                                    ? palette.secondary.opacity(0.15)
                                    : Color.clear
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .themedOverlayPanel()
                .padding(.horizontal, 12)
            }

            CommandSuggestionsView(messageText: $messageText)

            if showsRecorderHint {
                recorderHintRow
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Messages-style row: the attachment button floats in its own
            // glass circle beside the input capsule, not inside it. It
            // steps aside while recording so the bar gets the full width.
            HStack(alignment: .bottom, spacing: 8) {
                if conversationUIModel.canSendMediaInCurrentContext && !showsRecorder {
                    attachmentButton
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }

                inputCapsule
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(Self.recorderSpring, value: showsRecorder)
        .animation(Self.recorderSpring, value: recorderPhase)
        .animation(Self.recorderSpring, value: voiceRecordingVM.isDiscarding)
        .animation(.easeInOut(duration: 0.2), value: showsRecorderHint)
        .onChange(of: micPressed) { pressed in
            guard !pressed else { return }
            dragTranslation = .zero
            // A normal release reaches `onEnded` first and makes this a
            // no-op; only a touch the system cancelled gets here live.
            DispatchQueue.main.async {
                voiceRecordingVM.pressInterrupted()
            }
        }
        .onDisappear {
            autocompleteDebounceTimer?.invalidate()
        }
    }

    static let recorderSpring = Animation.spring(response: 0.32, dampingFraction: 0.8)
}

private extension ContentComposerView {
    /// Text field plus the trailing scope toggle and send/mic button, on one
    /// glass surface.
    var inputCapsule: some View {
        HStack(alignment: .center, spacing: 4) {
            ZStack(alignment: .leading) {
                // Hidden, not removed, while recording: removing the field
                // would drop focus and slide the keyboard away mid-hold.
                HStack(alignment: .center, spacing: 4) {
                    messageField

                    if showsNearbyOnlyToggle {
                        nearbyOnlyToggle
                    }
                }
                .opacity(showsRecorder ? 0 : 1)
                .allowsHitTesting(!showsRecorder)
                .accessibilityHidden(showsRecorder)

                if showsRecorder {
                    recordingBar
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
                }
            }

            sendOrMicButton
        }
        .padding(.leading, 8)
        .padding(.trailing, 2)
        .padding(.vertical, 2)
        .glassSurface(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    var messageField: some View {
        TextField(
            "",
            text: $messageText,
            prompt: Text(placeholderText)
                .foregroundColor(palette.secondary.opacity(0.6))
        )
        .textFieldStyle(.plain)
        .bitchatFont(size: 15)
        .foregroundColor(palette.primary)
        .focused(isTextFieldFocused)
        .autocorrectionDisabled(true)
        #if os(iOS)
        .textInputAutocapitalization(.sentences)
        #endif
        .submitLabel(.send)
        .modifier(AutocompleteKeyboardNavigationModifier(
            isActive: { conversationUIModel.showAutocomplete
                && !conversationUIModel.autocompleteSuggestions.isEmpty },
            onMove: { delta in
                conversationUIModel.moveAutocompleteSelection(by: delta)
            },
            onAccept: {
                conversationUIModel.completeSelectedSuggestion(in: &messageText)
            },
            onDismiss: {
                conversationUIModel.dismissAutocomplete()
            }
        ))
        // Return while the mention panel is open completes the
        // highlight instead of sending — matches command suggestions
        // (#1504) and keeps Tab/Return/Escape on one convention.
        .onSubmit {
            // The hidden field keeps focus while recording, so Return
            // sends a hands-free recording (Escape is the trash button).
            if showsRecorder {
                if recorderPhase == .locked {
                    voiceRecordingVM.sendHandsFree(completion: conversationUIModel.sendVoiceNote)
                }
                return
            }
            if conversationUIModel.showAutocomplete,
               !conversationUIModel.autocompleteSuggestions.isEmpty,
               conversationUIModel.completeSelectedSuggestion(in: &messageText) {
                return
            }
            onSendMessage()
            // Only the return-key path: it steals focus on iOS, so
            // every message would cost a tap to reopen the keyboard.
            // The send button must not reopen a deliberately
            // dismissed keyboard, so it stays out of this.
            isTextFieldFocused.wrappedValue = true
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .modifier(FocusEffectDisabledModifier())
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: messageText) { newValue in
            autocompleteDebounceTimer?.invalidate()
            autocompleteDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
                let cursorPosition = newValue.count
                Task { @MainActor in
                    conversationUIModel.updateAutocomplete(for: newValue, cursorPosition: cursorPosition)
                }
            }
        }
    }
}

private extension ContentComposerView {
    /// The nearby-only scope toggle appears only where it means something:
    /// the public mesh channel with the bridge on.
    var showsNearbyOnlyToggle: Bool {
        guard bridgeService.isEnabled,
              privateConversationModel.selectedHeaderState == nil,
              case .mesh = locationChannelsModel.selectedChannel else {
            return false
        }
        return true
    }

    /// Scope control for outgoing messages: bridged (default, crosses to
    /// other islands in this area) vs nearby-only (radio range, no internet
    /// copy exists for any gateway to carry).
    var nearbyOnlyToggle: some View {
        Button(action: { bridgeService.nearbyOnly.toggle() }) {
            Image(systemName: bridgeService.nearbyOnly ? "antenna.radiowaves.left.and.right" : "network")
                .font(.bitchatSystem(size: 16))
                .foregroundColor(bridgeService.nearbyOnly ? palette.secondary : Color.cyan.opacity(0.9))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            bridgeService.nearbyOnly
            ? String(localized: "content.accessibility.nearby_only_on", defaultValue: "Nearby only: messages stay within radio range", comment: "Accessibility label for the compose scope toggle when messages stay local")
            : String(localized: "content.accessibility.nearby_only_off", defaultValue: "Bridged: messages also reach people across the bridge", comment: "Accessibility label for the compose scope toggle when messages cross the mesh bridge")
        )
        .help(
            bridgeService.nearbyOnly
            ? String(localized: "content.composer.nearby_only_on", defaultValue: "Nearby only — this message won't cross the bridge", comment: "Tooltip for the compose scope toggle when messages stay local")
            : String(localized: "content.composer.nearby_only_off", defaultValue: "Bridged — reaches people beyond radio range in this area", comment: "Tooltip for the compose scope toggle when messages cross the mesh bridge")
        )
    }

    /// States where a message will land: the DM partner's name for private
    /// chats, the channel (and its public nature) otherwise — so a stressed
    /// user never has to guess who can read what they're typing.
    var placeholderText: String {
        if let header = privateConversationModel.selectedHeaderState {
            // A geohash-DM display name already carries its own "#geohash/@name"
            // form, so it must not get another "@" prefix; a mesh nickname does.
            let isGeoDM = privateConversationModel.selectedPeerID?.isGeoDM == true
            let target = isGeoDM ? header.displayName : "@\(header.displayName)"
            return String(
                format: String(localized: "content.input.placeholder.private", comment: "Composer placeholder inside a private chat, naming the conversation partner"),
                locale: .current,
                target
            )
        }
        switch locationChannelsModel.selectedChannel {
        case .mesh:
            return String(localized: "content.input.placeholder.mesh", comment: "Composer placeholder for the public mesh channel")
        case .location(let channel):
            return String(
                format: String(localized: "content.input.placeholder.location", comment: "Composer placeholder for a public geohash channel, naming it"),
                locale: .current,
                channel.geohash
            )
        }
    }

    // MARK: - Voice recording bar

    /// The recording bar is up: holding, hands free, or playing the
    /// discard animation.
    var showsRecorder: Bool {
        voiceRecordingVM.gesturePhase != .idle
            || voiceRecordingVM.state.isActive
            || voiceRecordingVM.isDiscarding
    }

    /// A recording that no finger holds (the composer was rebuilt while
    /// recording, say) behaves as hands free, so it always has a send and
    /// a cancel button.
    var recorderPhase: VoiceRecordGesture.Phase {
        let phase = voiceRecordingVM.gesturePhase
        if phase == .idle && voiceRecordingVM.state.isActive {
            return .locked
        }
        return phase
    }

    /// Live push-to-talk keeps its red treatment; a classic note uses the
    /// conversation accent.
    var recorderTint: Color {
        voiceRecordingVM.isLiveStreaming ? .red : composerAccentColor
    }

    var lockProgress: CGFloat {
        voiceRecordingVM.gestureThresholds.lockProgress(for: dragTranslation)
    }

    var cancelProgress: CGFloat {
        voiceRecordingVM.gestureThresholds.cancelProgress(for: dragTranslation)
    }

    var showsRecorderHint: Bool {
        if showsRecorder {
            return recorderPhase.isHolding
        }
        return voiceRecordingVM.showsHoldHint
    }

    var recorderHintText: String {
        guard showsRecorder else {
            return String(localized: "voice.recorder.hint.hold_to_record", defaultValue: "hold to record, release to send", comment: "Hint shown after a quick tap on the mic button, explaining how to record a voice message")
        }
        switch recorderPhase {
        case .lockArmed:
            return String(localized: "voice.recorder.hint.release_to_lock", defaultValue: "release to go hands free", comment: "Hint above the voice recording bar when releasing would keep recording without holding the mic")
        case .cancelArmed:
            return String(localized: "voice.recorder.hint.release_to_cancel", defaultValue: "release to cancel", comment: "Hint above the voice recording bar when releasing would discard the recording")
        case .idle, .holding, .locked:
            return String(localized: "voice.recorder.hint.swipe_to_cancel", defaultValue: "swipe left to cancel or release to send", comment: "Hint above the voice recording bar while holding the mic button")
        }
    }

    /// The hint above the bar while holding, with the lock target over the
    /// mic; or the hint after a quick tap.
    var recorderHintRow: some View {
        let isCancelArmed = showsRecorder && recorderPhase == .cancelArmed
        return ZStack(alignment: .trailing) {
            Text(recorderHintText)
                .bitchatFont(size: 12, weight: .medium)
                .foregroundColor(isCancelArmed ? .red : palette.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 44)
                .frame(maxWidth: .infinity)
                .id(recorderHintText)
                .transition(.opacity)

            if showsRecorder && recorderPhase.isHolding {
                VoiceRecorderLockPill(
                    isArmed: recorderPhase == .lockArmed,
                    progress: lockProgress,
                    tint: recorderTint
                )
                // Centers the pill over the mic at the capsule's trailing edge.
                .padding(.trailing, 2)
                .opacity(recorderPhase == .cancelArmed ? 0.4 : 1)
                .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Replaces the text field inside the capsule while recording: trash,
    /// live waveform, elapsed time.
    var recordingBar: some View {
        let isDiscarding = voiceRecordingVM.isDiscarding
        return HStack(spacing: 6) {
            recorderTrashButton

            VoiceRecordingWaveform(meter: voiceRecordingVM.levelMeter, tint: recorderTint)
                .frame(height: 24)
                .frame(maxWidth: .infinity)
                .opacity(recorderPhase == .cancelArmed ? 0.4 : 1)
                // Discarding sweeps the waveform into the trash can.
                .scaleEffect(x: isDiscarding ? 0.01 : 1, y: 1, anchor: .leading)
                .opacity(isDiscarding ? 0 : 1)
                // Time runs from the trash side in either direction.
                .flipsForRightToLeftLayoutDirection(true)

            recorderElapsedLabel
                .opacity(isDiscarding ? 0 : 1)
        }
        .frame(minHeight: 36)
    }

    var recorderTrashButton: some View {
        let isDiscarding = voiceRecordingVM.isDiscarding
        let isHighlighted = recorderPhase == .cancelArmed || isDiscarding
        let deleteLabel = String(localized: "voice.recorder.accessibility.delete", defaultValue: "delete recording", comment: "Accessibility label and tooltip for the trash button in the voice recording bar")
        return Button(action: voiceRecordingVM.discardRecording) {
            Image(systemName: isHighlighted ? "trash.fill" : "trash")
                .font(.bitchatSystem(size: 17, weight: .medium))
                .foregroundColor(isHighlighted ? .red : palette.secondary)
                .scaleEffect(isDiscarding ? 1.3 : 1 + 0.2 * cancelProgress)
                .rotationEffect(.degrees(isDiscarding ? -14 : 0), anchor: .bottom)
                .animation(.spring(response: 0.25, dampingFraction: 0.45), value: isDiscarding)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isDiscarding)
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel(deleteLabel)
        .help(deleteLabel)
    }

    /// "0:03", or a pulsing red "live 0:03" while the audio streams live.
    var recorderElapsedLabel: some View {
        let isLive = voiceRecordingVM.isLiveStreaming
        return HStack(spacing: 5) {
            if isLive {
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
                    .modifier(PulsingOpacityModifier(active: true))
            }
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let elapsed = voiceRecordingVM.formattedElapsed(for: context.date)
                if isLive {
                    Text(
                        "live \(elapsed)",
                        comment: "Recording bar label while a voice message streams live to the recipient; the placeholder is the elapsed time"
                    )
                    .monospacedDigit()
                    .bitchatFont(size: 13, weight: .bold)
                    .foregroundColor(.red)
                } else {
                    Text(verbatim: elapsed)
                        .monospacedDigit()
                        .bitchatFont(size: 13, weight: .medium)
                        .foregroundColor(palette.secondary)
                }
            }
        }
        .fixedSize()
        .padding(.trailing, 4)
    }

    /// Stops and sends a hands-free recording; takes the mic's place.
    var handsFreeSendButton: some View {
        let sendLabel = String(localized: "voice.recorder.accessibility.send", defaultValue: "send voice message", comment: "Accessibility label and tooltip for the send button of a hands-free voice recording")
        return Button {
            voiceRecordingVM.sendHandsFree(completion: conversationUIModel.sendVoiceNote)
        } label: {
            Image(systemName: "arrow.up")
                .font(.bitchatSystem(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(recorderTint))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
        .accessibilityLabel(sendLabel)
        .accessibilityAction(named: Text(String(localized: "voice.recorder.accessibility.delete", defaultValue: "delete recording", comment: "Accessibility label and tooltip for the trash button in the voice recording bar"))) {
            voiceRecordingVM.discardRecording()
        }
        .help(sendLabel)
    }

    var composerAccentColor: Color {
        privateConversationModel.selectedPeerID != nil ? Color.orange : palette.accent
    }

    var attachmentButton: some View {
        Menu {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Label(String(localized: "content.menu.photo_library", comment: "Menu option to choose an image from the photo library"), systemImage: "photo.on.rectangle")
            }
            #if os(iOS)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    imagePickerSourceType = .camera
                    showImagePicker = true
                } label: {
                    Label(String(localized: "content.menu.take_photo", comment: "Menu option to take a photo with the camera"), systemImage: "camera")
                }
            }
            #else
            Button(action: presentImageOpenPanel) {
                Label(String(localized: "content.menu.choose_file", comment: "Menu option to choose an image file"), systemImage: "folder")
            }
            #endif
        } label: {
            Image(systemName: "camera")
                .font(.bitchatSystem(size: 17, weight: .medium))
                .foregroundColor(composerAccentColor)
                .frame(width: 40, height: 40)
                .glassSurface(in: Circle())
                .contentShape(Circle())
        }
        .onChange(of: selectedPhotoItem) { item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                #if os(iOS)
                guard let image = UIImage(data: data) else { return }
                await MainActor.run { conversationUIModel.processSelectedImage(image) }
                #else
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("nova-photo-\(UUID().uuidString).jpg")
                guard (try? data.write(to: url)) != nil else { return }
                await MainActor.run { conversationUIModel.processSelectedImage(from: url) }
                #endif
                await MainActor.run { selectedPhotoItem = nil }
            }
        }
        .accessibilityLabel(String(localized: "content.accessibility.attach_photo", comment: "Accessibility label for the photo attachment button"))
        #if os(iOS)
        .accessibilityAction(named: Text("content.accessibility.take_photo", comment: "Accessibility action name for taking a photo with the camera")) {
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
            imagePickerSourceType = .camera
            showImagePicker = true
        }
        #endif
    }

    #if os(macOS)
    /// Opens the system open panel straight away, attached to the window,
    /// with no intermediate dialog.
    func presentImageOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.message = String(localized: "mac.image_picker.panel_message", comment: "Message shown in the macOS NSOpenPanel when picking an image")

        let model = conversationUIModel
        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                model.processSelectedImage(from: url)
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(panel.runModal())
        }
    }
    #endif

    @ViewBuilder
    var sendOrMicButton: some View {
        // Text typed into the hidden field while recording must not swap
        // the mic out from under the finger.
        let hasText = !messageText.trimmed.isEmpty && !showsRecorder
        if showsRecorder && recorderPhase == .locked {
            handsFreeSendButton
                .frame(width: 36, height: 36)
        } else if conversationUIModel.canSendMediaInCurrentContext {
            ZStack {
                micButtonView
                    .opacity(hasText ? 0 : 1)
                    .allowsHitTesting(!hasText)
                sendButtonView(enabled: hasText)
                    .opacity(hasText ? 1 : 0)
                    .allowsHitTesting(hasText)
            }
            .frame(width: 36, height: 36)
        } else {
            sendButtonView(enabled: hasText)
                .frame(width: 36, height: 36)
        }
    }

    /// Floor courtesy: someone else is talking live in the public channel.
    /// Only advisory — a decentralized mesh has no floor arbiter, so holding
    /// the mic still works; the tint just discourages talk-over.
    var busyTalker: String? {
        guard privateConversationModel.selectedPeerID == nil else { return nil }
        return conversationUIModel.activeLiveVoiceTalker
    }

    /// Floor-busy > default accent. Whether the hold streams live or
    /// records a classic note shows in the recording bar, not the idle
    /// button color.
    var micColor: Color {
        if busyTalker != nil { return Color.red.opacity(0.6) }
        return composerAccentColor
    }

    /// Idle: the mic glyph. Holding: a larger filled circle under the
    /// finger, like the recorder it controls.
    var micButtonView: some View {
        let isHolding = showsRecorder && recorderPhase.isHolding
        return ZStack {
            Circle()
                .fill(recorderTint)
                .frame(width: 36, height: 36)
                .scaleEffect(isHolding ? 1.12 : 0.5)
                .opacity(isHolding ? 1 : 0)
            Image(systemName: isHolding ? "mic.fill" : "mic.circle.fill")
                .font(.bitchatSystem(size: isHolding ? 17 : 24, weight: isHolding ? .semibold : .regular))
                .foregroundColor(isHolding ? .white : micColor)
        }
        .modifier(PulsingOpacityModifier(active: busyTalker != nil && !showsRecorder))
        .frame(width: 36, height: 36)
        .contentShape(Circle())
        .overlay(
            Color.clear
                .contentShape(Circle())
                .gesture(micGesture)
        )
        .accessibilityLabel(
            String(localized: "content.accessibility.record_voice_note", comment: "Accessibility label for the voice note button")
        )
        .accessibilityValue(
            showsRecorder
            ? String(localized: "content.accessibility.recording", comment: "Accessibility value announced while a voice note is recording")
            : busyTalker.map {
                String(
                    format: String(localized: "content.accessibility.someone_speaking", comment: "Accessibility value on the mic button naming who is talking live in the public channel"),
                    locale: .current,
                    $0
                )
            } ?? ""
        )
        .accessibilityHint(
            String(localized: "content.accessibility.record_voice_hint", comment: "Accessibility hint explaining double-tap toggles voice recording")
        )
        .accessibilityAddTraits(.isButton)
        // VoiceOver cannot press and drag: its activation starts a
        // hands-free recording, and the mic turns into the send button.
        .accessibilityAction {
            voiceRecordingVM.startHandsFree(canRecord: conversationUIModel.canSendMediaInCurrentContext)
        }
    }

    /// Press and hold records; release sends, drag up locks hands free,
    /// drag towards the trash cancels. Global coordinates, so the hint row
    /// appearing above the composer does not shift the measured translation.
    var micGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .updating($micPressed) { _, pressed, _ in
                pressed = true
            }
            .onChanged { value in
                // The trash can sits on the leading side: in a right-to-left
                // layout, cancelling is a drag to the right.
                let translation = layoutDirection == .rightToLeft
                    ? CGSize(width: -value.translation.width, height: value.translation.height)
                    : value.translation
                let wasHolding = voiceRecordingVM.gesturePhase.isHolding
                let crossed = voiceRecordingVM.pressChanged(
                    translation: translation,
                    canRecord: conversationUIModel.canSendMediaInCurrentContext
                )
                let phase = voiceRecordingVM.gesturePhase
                guard phase.isHolding else { return }
                dragTranslation = translation
                if !wasHolding {
                    VoiceRecorderHaptics.recordingBegan()
                } else if crossed && phase.isArmed {
                    VoiceRecorderHaptics.thresholdCrossed()
                }
            }
            .onEnded { _ in
                dragTranslation = .zero
                voiceRecordingVM.pressEnded(completion: conversationUIModel.sendVoiceNote)
            }
    }

    func sendButtonView(enabled: Bool) -> some View {
        let activeColor = composerAccentColor
        return Button(action: onSendMessage) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.bitchatSystem(size: 24))
                .foregroundColor(enabled ? activeColor : Color.gray)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(
            String(localized: "content.accessibility.send_message", comment: "Accessibility label for the send message button")
        )
        .accessibilityHint(
            enabled
            ? String(localized: "content.accessibility.send_hint_ready", comment: "Hint prompting the user to send the message")
            : String(localized: "content.accessibility.send_hint_empty", comment: "Hint prompting the user to enter a message")
        )
    }
}

/// Arrow/Tab/Return/Escape navigation for the mention suggestion list.
///
/// Deployment targets are iOS 16 / macOS 13, so `.onKeyPress` (iOS 17 /
/// macOS 14+) is gated and unavailable on the minimum OS. Separately, on
/// macOS the single-line field editor consumes `moveUp:`/`moveDown:` itself,
/// so arrow keys never reach SwiftUI while the composer has focus — the
/// same reason command suggestions (#1504) use an `NSEvent` local monitor.
/// Mentions follow that mechanism on macOS and keep `.onKeyPress` for iOS 17+.
private struct AutocompleteKeyboardNavigationModifier: ViewModifier {
    /// Live activity check, not a captured Bool. The macOS monitor closure is
    /// registered once for the view's lifetime; a plain `Bool` would freeze
    /// the value captured at install time (this is a value type), so a panel
    /// that opens after the monitor installs would never intercept a key.
    /// The provider closes over the reference-typed model and reads current
    /// state on every event.
    let isActive: () -> Bool
    let onMove: (Int) -> Void
    let onAccept: () -> Bool
    let onDismiss: () -> Void

    #if os(macOS)
    @State private var keyMonitor: Any?
    #endif

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .onAppear { installKeyMonitor() }
            .onDisappear { removeKeyMonitor() }
        #else
        if #available(iOS 17.0, *) {
            content
                .onKeyPress(.upArrow) {
                    guard isActive() else { return .ignored }
                    onMove(-1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    guard isActive() else { return .ignored }
                    onMove(1)
                    return .handled
                }
                .onKeyPress(.tab) {
                    guard isActive() else { return .ignored }
                    return onAccept() ? .handled : .ignored
                }
                .onKeyPress(.escape) {
                    guard isActive() else { return .ignored }
                    onDismiss()
                    return .handled
                }
        } else {
            content
        }
        #endif
    }

    #if os(macOS)
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event)
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    /// Standard autocomplete navigation (aligned with #1504): arrows move
    /// the highlight, return/tab insert, escape dismisses. Returning nil
    /// consumes the event so return completes instead of sending while the
    /// list is up. Inactive monitors pass everything through.
    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard isActive(),
              event.modifierFlags.isDisjoint(with: [.command, .option, .control]) else {
            return event
        }

        switch event.keyCode {
        case 126: // up arrow
            onMove(-1)
            return nil
        case 125: // down arrow
            onMove(1)
            return nil
        case 36, 48: // return, tab
            return onAccept() ? nil : event
        case 53: // escape
            onDismiss()
            return nil
        default:
            return event
        }
    }
    #endif
}
