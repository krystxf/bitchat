import BitFoundation
import BitLogger
import Foundation

/// The narrow surface `ChatOutgoingCoordinator` needs from its owner.
///
/// Follows the `ChatDeliveryContext` exemplar: the coordinator depends on the
/// minimal context it actually uses instead of holding an `unowned` back-ref
/// to the whole `ChatViewModel`. This keeps the coordinator independently
/// testable (see `ChatOutgoingCoordinatorContextTests`) and makes its true
/// dependencies explicit.
@MainActor
protocol ChatOutgoingContext: AnyObject {
    // MARK: Identity & channel state
    var nickname: String { get }
    var myPeerID: PeerID { get }
    var activeChannel: ChannelID { get }
    var selectedPrivateChatPeer: PeerID? { get }
    var isTeleported: Bool { get }

    // MARK: Commands & private messages
    func handleCommand(_ command: String)
    func updatePrivateChatPeerIfNeeded()
    func sendPrivateMessage(_ content: String, to peerID: PeerID)

    // MARK: Public timeline (local echo)
    func parseMentions(from content: String) -> [String]
    /// Appends a public message via the single-writer store intent
    /// (immediate: the local echo must render without batching).
    @discardableResult
    func appendPublicMessage(_ message: BitchatMessage, to conversationID: ConversationID) -> Bool
    /// Swaps a pending bubble for the sent message it stood for, in place.
    /// Returns `false` when the bubble is gone (cleared, wiped).
    @discardableResult
    func replacePublicMessage(withID messageID: String, by message: BitchatMessage, in conversationID: ConversationID) -> Bool
    /// Marks a pending bubble's outcome (`.failed` when it never went out).
    func setPublicMessageDeliveryStatus(_ status: DeliveryStatus, forMessageID messageID: String, in conversationID: ConversationID)
    func addSystemMessage(_ content: String)

    // MARK: Content dedup
    func normalizedContentKey(_ content: String) -> String
    func recordContentKey(_ key: String, timestamp: Date)

    // MARK: Outbound routing
    /// Stamps "now" as the channel's last public activity (background nudges).
    /// (Single mutation path for the owner's `lastPublicActivityAt`; this
    /// coordinator never reads it.)
    func recordPublicActivity(forChannelKey key: String)
    func sendMeshMessage(_ content: String, mentions: [String], messageID: String, timestamp: Date)
    func sendGeohash(context: ChatViewModel.GeoOutgoingContext)
    /// Ships the bridged (rendezvous) copy of a just-sent public mesh
    /// message; no-op when the bridge is off or the send is nearby-only.
    /// Takes the origin coordinates (sender + wire timestamp) — the bridge
    /// derives the cross-device-stable mesh message ID from them, not from
    /// our local timeline UUID (which no other device can recompute).
    func bridgeOutgoingPublicMessage(_ content: String, senderPeerID: PeerID, timestamp: Date)

    // MARK: Geohash identity (shared with the other contexts)
    func deriveNostrIdentity(forGeohash geohash: String) throws -> NostrIdentity
}

extension ChatViewModel: ChatOutgoingContext {
    // `nickname`, `myPeerID`, `activeChannel`, `selectedPrivateChatPeer`,
    // `isTeleported`, `handleCommand(_:)`, `updatePrivateChatPeerIfNeeded()`,
    // `sendPrivateMessage(_:to:)`, `parseMentions(from:)`,
    // `appendPublicMessage(_:to:)`, `addSystemMessage(_:)`,
    // `normalizedContentKey(_:)`, `recordContentKey(_:timestamp:)`,
    // `sendMeshMessage(_:mentions:messageID:timestamp:)`,
    // `sendGeohash(context:)`, and `deriveNostrIdentity(forGeohash:)` are
    // shared requirements with the other contexts or satisfied by existing
    // `ChatViewModel` members. The single-writer intent op below lives next to
    // its backing state's owner.

    func recordPublicActivity(forChannelKey key: String) {
        lastPublicActivityAt[key] = Date()
    }

    @discardableResult
    func replacePublicMessage(withID messageID: String, by message: BitchatMessage, in conversationID: ConversationID) -> Bool {
        conversations.replaceMessage(withID: messageID, by: message, in: conversationID)
    }

    func setPublicMessageDeliveryStatus(_ status: DeliveryStatus, forMessageID messageID: String, in conversationID: ConversationID) {
        conversations.setDeliveryStatus(status, forMessageID: messageID, in: conversationID)
    }

    func bridgeOutgoingPublicMessage(_ content: String, senderPeerID: PeerID, timestamp: Date) {
        BridgeService.shared.bridgeOutgoing(content: content, senderPeerID: senderPeerID, timestamp: timestamp)
    }
}

@MainActor
final class ChatOutgoingCoordinator {
    private unowned let context: any ChatOutgoingContext

    /// In-flight NIP-13 mining for the most recent geohash send. A newer send
    /// cancels it, which only expedites the mining — the message still goes
    /// out at the difficulty already reached. Leaving the channel drops it
    /// instead (`abandonPendingGeohashSends()`).
    /// (Read access is internal so tests can await the send's completion.)
    private(set) var geohashMiningTask: Task<Void, Never>?

    /// Pending bubbles of geohash sends still mining, by message ID, with
    /// whether leaving the channel dropped them.
    private var pendingGeohashSends: [String: Bool] = [:]

    /// Prefix of a pending bubble's temporary message ID, used until the
    /// signed event (whose ID the sent message takes) exists.
    static let pendingMessageIDPrefix = "pow-pending-"

    /// Why a pending bubble ended failed.
    static var sendErrorReason: String {
        String(localized: "content.delivery.reason.send_error", comment: "Failure reason shown when a send failed with an error")
    }

    static var leftChannelReason: String {
        String(localized: "content.delivery.reason.left_channel", defaultValue: "You left the channel before it was sent", comment: "Failure reason under a location message that was still doing its proof of work when the person left the channel, so it was not sent")
    }

    /// The NIP-13 target for the next geohash send, read when the message is
    /// sent (0 = proof of work off: no mining, no nonce tag). Injected so
    /// tests do not depend on the shared preferences.
    private let powTargetBits: () -> Int

    /// What pending bubbles show while their geohash sends mine.
    private let miningStatus: LocationPoWMiningStatus

    /// How long a bubble that showed its progress keeps it after the event
    /// went out. Injected so tests need not wait for animations.
    private let finishAnimationDuration: TimeInterval

    init(
        context: any ChatOutgoingContext,
        powTargetBits: @escaping () -> Int = { LocationProofOfWorkSettings.sendTargetBits() },
        miningStatus: LocationPoWMiningStatus? = nil,
        finishAnimationDuration: TimeInterval = PoWSendProgress.finishDuration
    ) {
        self.context = context
        self.powTargetBits = powTargetBits
        self.miningStatus = miningStatus ?? .shared
        self.finishAnimationDuration = finishAnimationDuration
    }

    /// Finish any in-flight geohash PoW mining early (the pending message
    /// still sends, at whatever committed difficulty it reached).
    func expeditePendingGeohashMining() {
        geohashMiningTask?.cancel()
    }

    /// Leaving the channel: messages still mining are not sent. Mining is
    /// cut short and their bubbles end failed, saying why, so a message
    /// never lands in a channel the person already left.
    func abandonPendingGeohashSends() {
        guard !pendingGeohashSends.isEmpty else { return }
        for messageID in pendingGeohashSends.keys {
            pendingGeohashSends[messageID] = true
        }
        geohashMiningTask?.cancel()
    }

    func sendMessage(_ content: String) {
        guard let trimmed = content.trimmedOrNilIfEmpty else { return }

        if content.hasPrefix("/") {
            Task { @MainActor [weak context = self.context] in
                context?.handleCommand(content)
            }
            return
        }

        if context.selectedPrivateChatPeer != nil {
            context.updatePrivateChatPeerIfNeeded()

            if let selectedPeer = context.selectedPrivateChatPeer {
                context.sendPrivateMessage(content, to: selectedPeer)
            }
            return
        }

        let mentions = context.parseMentions(from: content)

        switch context.activeChannel {
        case .mesh:
            sendMeshPublicMessage(originalContent: content, trimmed: trimmed, mentions: mentions)
        case .location(let channel):
            sendGeohashPublicMessage(trimmed, mentions: mentions, channel: channel)
        }
    }

    /// Broadcasts a wave on the mesh channel regardless of the active channel —
    /// used by the "bitchatters nearby" notification quick action, which always
    /// refers to mesh peers.
    func sendMeshWave() {
        sendMeshPublicMessage(originalContent: "👋", trimmed: "👋", mentions: [])
    }
}

private extension ChatOutgoingCoordinator {
    func sendMeshPublicMessage(originalContent: String, trimmed: String, mentions: [String]) {
        let message = BitchatMessage(
            sender: context.nickname,
            content: trimmed,
            timestamp: Date(),
            isRelay: false,
            senderPeerID: context.myPeerID,
            mentions: mentions.isEmpty ? nil : mentions
        )

        appendLocalEcho(message, to: .mesh)
        context.recordPublicActivity(forChannelKey: "mesh")
        context.sendMeshMessage(
            originalContent,
            mentions: mentions,
            messageID: message.id,
            timestamp: message.timestamp
        )
        context.bridgeOutgoingPublicMessage(trimmed, senderPeerID: context.myPeerID, timestamp: message.timestamp)
    }

    /// Geohash sends mine a NIP-13 nonce tag first (off the main actor, see
    /// `NostrPoW`), so the whole echo-and-send runs in a task once the signed
    /// event — whose ID is also the local message ID — exists. The target
    /// comes from settings: mining at the default is well under 100 ms,
    /// higher targets are hard-capped at
    /// `NostrPoW.miningTimeCap(forTargetBits:)`, and with proof of work off
    /// nothing is mined at all.
    func sendGeohashPublicMessage(_ trimmed: String, mentions: [String], channel: GeohashChannel) {
        let identity: NostrIdentity
        do {
            identity = try context.deriveNostrIdentity(forGeohash: channel.geohash)
        } catch {
            SecureLogger.error("❌ Failed to prepare geohash message: \(error)", category: .session)
            context.addSystemMessage(
                String(localized: "system.location.send_failed", comment: "System message when a location channel send fails")
            )
            return
        }

        let displaySender = context.nickname + "#" + String(identity.publicKeyHex.suffix(4))
        let senderPeerID = PeerID(nostr: identity.publicKeyHex)
        let teleported = context.isTeleported
        let nickname = context.nickname
        let powTargetBits = self.powTargetBits()
        let conversationID = ConversationID(channelID: .location(channel))
        let miningStatus = self.miningStatus

        // A message that mines gets its bubble right away, under a temporary
        // ID, and keeps its place: the signed event reuses the bubble's
        // timestamp (whole seconds, as created_at carries), and the sent
        // message replaces the bubble in place. With proof of work off,
        // signing is instant and the sent message is appended as before.
        let createdAt = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        var pendingID: String?
        if powTargetBits > 0 {
            let id = Self.pendingMessageIDPrefix + UUID().uuidString
            context.appendPublicMessage(
                BitchatMessage(
                    id: id,
                    sender: displaySender,
                    content: trimmed,
                    timestamp: createdAt,
                    isRelay: false,
                    senderPeerID: senderPeerID,
                    mentions: mentions.isEmpty ? nil : mentions,
                    deliveryStatus: .sending
                ),
                to: conversationID
            )
            miningStatus.begin(messageID: id, targetBits: powTargetBits)
            pendingGeohashSends[id] = false
            pendingID = id
        }

        // Serialize geohash sends: each send awaits the previous send's task
        // before it appends + relays, so user-visible order always matches
        // send order even when an earlier message mines longer than a later
        // one. Cancelling the previous task only *expedites* its mining (the
        // NIP-13 target is polled, not aborted), so it still finishes and
        // sends — and it finishes fast, so awaiting it never stacks mining
        // delays or blocks a send beyond its own mining time cap.
        let previousSend = geohashMiningTask
        previousSend?.cancel()
        geohashMiningTask = Task { @MainActor [weak self, weak context = self.context] in
            await previousSend?.value

            let event: NostrEvent
            do {
                event = try await NostrProtocol.createMinedEphemeralGeohashEvent(
                    content: trimmed,
                    geohash: channel.geohash,
                    senderIdentity: identity,
                    nickname: nickname,
                    teleported: teleported,
                    createdAt: createdAt,
                    powTargetBits: powTargetBits
                )
            } catch {
                SecureLogger.error("❌ Failed to prepare geohash message: \(error)", category: .session)
                if let pendingID {
                    self?.failPendingGeohashSend(pendingID, in: conversationID, reason: Self.sendErrorReason)
                } else {
                    context?.addSystemMessage(
                        String(localized: "system.location.send_failed", comment: "System message when a location channel send fails")
                    )
                }
                return
            }
            guard let context else { return }
            if let pendingID, self?.pendingGeohashSends[pendingID] == true {
                self?.failPendingGeohashSend(pendingID, in: conversationID, reason: Self.leftChannelReason)
                return
            }

            let message = BitchatMessage(
                id: event.id,
                sender: displaySender,
                content: trimmed,
                timestamp: Date(timeIntervalSince1970: TimeInterval(event.created_at)),
                isRelay: false,
                senderPeerID: senderPeerID,
                mentions: mentions.isEmpty ? nil : mentions
            )

            if let pendingID {
                self?.pendingGeohashSends.removeValue(forKey: pendingID)
                self?.completePendingGeohashSend(pendingID, with: message, in: conversationID)
            } else {
                context.appendPublicMessage(message, to: conversationID)
            }
            let contentKey = context.normalizedContentKey(message.content)
            context.recordContentKey(contentKey, timestamp: message.timestamp)

            context.recordPublicActivity(forChannelKey: "geo:\(channel.geohash)")
            context.sendGeohash(context: (
                channel: channel,
                event: event,
                identity: identity,
                teleported: teleported
            ))
        }
    }

    /// The event went out: the pending bubble becomes the sent message. A
    /// bubble that showed its progress first lets it fill and fade
    /// (`PoWSendProgress.finishDuration`); one that never showed any, as at
    /// the default 8 bits, is swapped at once. The swap runs on its own, so
    /// the next send never waits for it.
    func completePendingGeohashSend(_ pendingID: String, with message: BitchatMessage, in conversationID: ConversationID) {
        let miningStatus = self.miningStatus
        miningStatus.finish(messageID: pendingID)
        guard miningStatus.showedProgress(for: pendingID), finishAnimationDuration > 0 else {
            context.replacePublicMessage(withID: pendingID, by: message, in: conversationID)
            miningStatus.end(messageID: pendingID)
            return
        }
        let delay = UInt64(finishAnimationDuration * 1_000_000_000)
        Task { @MainActor [weak context = self.context] in
            try? await Task.sleep(nanoseconds: delay)
            context?.replacePublicMessage(withID: pendingID, by: message, in: conversationID)
            miningStatus.end(messageID: pendingID)
        }
    }

    /// The message never went out: its bubble stays, failed, with the
    /// reason under it, as a failed private message shows.
    func failPendingGeohashSend(_ pendingID: String, in conversationID: ConversationID, reason: String) {
        pendingGeohashSends.removeValue(forKey: pendingID)
        miningStatus.end(messageID: pendingID)
        context.setPublicMessageDeliveryStatus(.failed(reason: reason), forMessageID: pendingID, in: conversationID)
    }

    func appendLocalEcho(_ message: BitchatMessage, to conversationID: ConversationID) {
        context.appendPublicMessage(message, to: conversationID)

        let contentKey = context.normalizedContentKey(message.content)
        context.recordContentKey(contentKey, timestamp: message.timestamp)
    }
}
