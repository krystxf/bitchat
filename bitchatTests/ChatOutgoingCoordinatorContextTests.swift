//
// ChatOutgoingCoordinatorContextTests.swift
// bitchatTests
//
// Exercises `ChatOutgoingCoordinator` against a mock `ChatOutgoingContext` —
// proving the coordinator works without a `ChatViewModel`, following the
// `ChatDeliveryCoordinatorContextTests` exemplar.
//
// Scope note: the geohash path builds and signs a real Nostr event via
// `NostrProtocol.createEphemeralGeohashEvent` (pure crypto, no shared state);
// everything else flows through the mock context.
//

import Testing
import Foundation
import BitFoundation
@testable import bitchat

// MARK: - Mock Context

/// Lightweight stand-in for `ChatOutgoingContext` proving that
/// `ChatOutgoingCoordinator` is testable without a `ChatViewModel`.
@MainActor
private final class MockChatOutgoingContext: ChatOutgoingContext {
    // Identity & channel state
    var nickname = "me"
    var myPeerID = PeerID(str: "0011223344556677")
    var activeChannel: ChannelID = .mesh
    var selectedPrivateChatPeer: PeerID?
    var isTeleported = false

    // Commands & private messages
    var selectedPeerAfterUpdate: PeerID??
    private(set) var handledCommands: [String] = []
    private(set) var updatePrivateChatPeerIfNeededCount = 0
    private(set) var sentPrivateMessages: [(content: String, peerID: PeerID)] = []

    func handleCommand(_ command: String) { handledCommands.append(command) }

    func updatePrivateChatPeerIfNeeded() {
        updatePrivateChatPeerIfNeededCount += 1
        if let selectedPeerAfterUpdate {
            selectedPrivateChatPeer = selectedPeerAfterUpdate
        }
    }

    func sendPrivateMessage(_ content: String, to peerID: PeerID) {
        sentPrivateMessages.append((content, peerID))
    }

    // Public timeline (local echo)
    private(set) var appendedPublicMessages: [(message: BitchatMessage, conversationID: ConversationID)] = []
    private(set) var systemMessages: [String] = []

    func parseMentions(from content: String) -> [String] {
        content.contains("@bob") ? ["bob"] : []
    }

    @discardableResult
    func appendPublicMessage(_ message: BitchatMessage, to conversationID: ConversationID) -> Bool {
        appendedPublicMessages.append((message, conversationID))
        return true
    }

    private(set) var replacedMessageIDs: [String] = []

    @discardableResult
    func replacePublicMessage(withID messageID: String, by message: BitchatMessage, in conversationID: ConversationID) -> Bool {
        guard let index = appendedPublicMessages.firstIndex(where: {
            $0.message.id == messageID && $0.conversationID == conversationID
        }) else { return false }
        appendedPublicMessages[index] = (message, conversationID)
        replacedMessageIDs.append(messageID)
        return true
    }

    func setPublicMessageDeliveryStatus(_ status: DeliveryStatus, forMessageID messageID: String, in conversationID: ConversationID) {
        if let entry = appendedPublicMessages.first(where: {
            $0.message.id == messageID && $0.conversationID == conversationID
        }) {
            entry.message.deliveryStatus = status
        }
    }

    func addSystemMessage(_ content: String) { systemMessages.append(content) }

    // Content dedup
    private(set) var recordedContentKeys: [(key: String, timestamp: Date)] = []

    func normalizedContentKey(_ content: String) -> String { "key:\(content)" }
    func recordContentKey(_ key: String, timestamp: Date) {
        recordedContentKeys.append((key, timestamp))
    }

    // Outbound routing
    private(set) var recordedActivityKeys: [String] = []
    private(set) var sentMeshMessages: [(content: String, mentions: [String], messageID: String, timestamp: Date)] = []
    private(set) var sentGeohashContexts: [ChatViewModel.GeoOutgoingContext] = []

    func recordPublicActivity(forChannelKey key: String) { recordedActivityKeys.append(key) }

    func sendMeshMessage(_ content: String, mentions: [String], messageID: String, timestamp: Date) {
        sentMeshMessages.append((content, mentions, messageID, timestamp))
    }

    func sendGeohash(context: ChatViewModel.GeoOutgoingContext) {
        sentGeohashContexts.append(context)
    }

    private(set) var bridgedMessages: [(content: String, senderPeerID: PeerID, timestamp: Date)] = []
    func bridgeOutgoingPublicMessage(_ content: String, senderPeerID: PeerID, timestamp: Date) {
        bridgedMessages.append((content, senderPeerID, timestamp))
    }

    // Geohash identity
    struct IdentityUnavailable: Error {}
    var deriveNostrIdentityError: Error?
    static let dummyIdentity = NostrIdentity(
        privateKey: Data(repeating: 0x11, count: 32),
        publicKey: Data(repeating: 0x22, count: 32),
        npub: "npub1mock",
        createdAt: Date(timeIntervalSince1970: 0)
    )

    /// A key no event can be signed with, for the signing-failure path.
    static let unsignableIdentity = NostrIdentity(
        privateKey: Data(count: 32),
        publicKey: Data(repeating: 0x33, count: 32),
        npub: "npub1unsignable",
        createdAt: Date(timeIntervalSince1970: 0)
    )
    var identity = MockChatOutgoingContext.dummyIdentity

    func deriveNostrIdentity(forGeohash geohash: String) throws -> NostrIdentity {
        if let deriveNostrIdentityError { throw deriveNostrIdentityError }
        return identity
    }
}

// MARK: - Helpers

/// Lets the coordinator's internal `Task { @MainActor … }` hops run.
@MainActor
private func drainMainActorTasks() async {
    for _ in 0..<10 { await Task.yield() }
}

// MARK: - Coordinator Tests Against Mock Context

/// Exercises `ChatOutgoingCoordinator` against `MockChatOutgoingContext` with
/// no `ChatViewModel`.
struct ChatOutgoingCoordinatorContextTests {

    @Test @MainActor
    func sendMessage_routesSlashCommandsAndDropsEmptyContent() async {
        let context = MockChatOutgoingContext()
        let coordinator = ChatOutgoingCoordinator(context: context)

        coordinator.sendMessage("   ")
        coordinator.sendMessage("/who all")
        await drainMainActorTasks()

        #expect(context.handledCommands == ["/who all"])
        #expect(context.appendedPublicMessages.isEmpty)
        #expect(context.sentMeshMessages.isEmpty)
    }

    @Test @MainActor
    func sendMessage_inPrivateChat_reResolvesPeerBeforeSending() async {
        let context = MockChatOutgoingContext()
        let coordinator = ChatOutgoingCoordinator(context: context)
        let shortPeer = PeerID(str: "1111111111111111")
        let stablePeer = PeerID(str: String(repeating: "ab", count: 32))

        // The selected peer is refreshed (short → stable) before sending.
        context.selectedPrivateChatPeer = shortPeer
        context.selectedPeerAfterUpdate = stablePeer
        coordinator.sendMessage("hi there")
        #expect(context.updatePrivateChatPeerIfNeededCount == 1)
        #expect(context.sentPrivateMessages.map(\.peerID) == [stablePeer])
        #expect(context.sentPrivateMessages.map(\.content) == ["hi there"])

        // If the refresh clears the selection, nothing is sent.
        context.selectedPeerAfterUpdate = PeerID??.some(nil)
        coordinator.sendMessage("dropped")
        await drainMainActorTasks()
        #expect(context.sentPrivateMessages.count == 1)
        #expect(context.appendedPublicMessages.isEmpty)
    }

    @Test @MainActor
    func sendMessage_onMesh_appendsLocalEchoRecordsActivityAndSends() async {
        let context = MockChatOutgoingContext()
        let coordinator = ChatOutgoingCoordinator(context: context)

        coordinator.sendMessage("  hello @bob  ")
        await drainMainActorTasks()

        // Local echo uses the trimmed content, own nickname/peer ID, mentions.
        #expect(context.appendedPublicMessages.count == 1)
        let echo = context.appendedPublicMessages[0]
        #expect(echo.message.content == "hello @bob")
        #expect(echo.message.sender == "me")
        #expect(echo.message.senderPeerID == context.myPeerID)
        #expect(echo.message.mentions == ["bob"])
        #expect(echo.conversationID == .mesh)
        #expect(context.recordedContentKeys.map(\.key) == ["key:hello @bob"])

        // The mesh send carries the original (untrimmed) content and reuses
        // the echo's message ID and timestamp; activity is stamped for "mesh".
        #expect(context.recordedActivityKeys == ["mesh"])
        #expect(context.sentMeshMessages.count == 1)
        let sent = context.sentMeshMessages[0]
        #expect(sent.content == "  hello @bob  ")
        #expect(sent.mentions == ["bob"])
        #expect(sent.messageID == echo.message.id)
        #expect(sent.timestamp == echo.message.timestamp)
    }

    @Test @MainActor
    func sendMessage_onLocationChannel_sendsGeohashEventOrFailsWithSystemMessage() async {
        let context = MockChatOutgoingContext()
        let coordinator = ChatOutgoingCoordinator(context: context, miningStatus: LocationPoWMiningStatus(), finishAnimationDuration: 0)
        let channel = GeohashChannel(level: .city, geohash: "u4pruydq")
        context.activeChannel = .location(channel)
        context.isTeleported = true

        coordinator.sendMessage("hello geo")
        // Geohash sends mine a NIP-13 nonce tag off-main before echoing and
        // sending; await the send task, then drain the main queue.
        await coordinator.geohashMiningTask?.value
        await drainMainActorTasks()

        // Local echo carries the geohash sender suffix (#last-4-of-pubkey) and
        // the signed event's ID; the send context targets the same channel.
        #expect(context.appendedPublicMessages.count == 1)
        let echo = context.appendedPublicMessages[0].message
        #expect(context.appendedPublicMessages[0].conversationID == .geohash("u4pruydq"))
        #expect(echo.sender == "me#2222")
        // The echo is told apart as mine by this ID, not by its name.
        #expect(echo.senderPeerID == PeerID(nostr: MockChatOutgoingContext.dummyIdentity.publicKeyHex))
        #expect(context.recordedActivityKeys == ["geo:u4pruydq"])
        #expect(context.sentGeohashContexts.count == 1)
        let geoContext = context.sentGeohashContexts[0]
        #expect(geoContext.channel == channel)
        #expect(geoContext.teleported)
        #expect(geoContext.event.id == echo.id)

        // Identity derivation failure: system message, no echo, no send.
        context.deriveNostrIdentityError = MockChatOutgoingContext.IdentityUnavailable()
        coordinator.sendMessage("doomed")
        await drainMainActorTasks()
        #expect(context.systemMessages.count == 1)
        #expect(context.appendedPublicMessages.count == 1)
        #expect(context.sentGeohashContexts.count == 1)
    }

    @Test @MainActor
    func sendMessage_onLocationChannel_minesTheTargetFromSettingsAtSendTime() async throws {
        let context = MockChatOutgoingContext()
        var target = 12
        let coordinator = ChatOutgoingCoordinator(context: context, powTargetBits: { target }, miningStatus: LocationPoWMiningStatus(), finishAnimationDuration: 0)
        context.activeChannel = .location(GeohashChannel(level: .city, geohash: "u4pruydq"))

        coordinator.sendMessage("mined")
        await coordinator.geohashMiningTask?.value
        // Proof of work switched off between sends: the next send mines
        // nothing, so the setting is read per send, not once.
        target = 0
        coordinator.sendMessage("not mined")
        await coordinator.geohashMiningTask?.value
        await drainMainActorTasks()

        #expect(context.sentGeohashContexts.count == 2)
        let mined = context.sentGeohashContexts[0].event
        let nonceTag = try #require(mined.tags.first { $0.first == "nonce" })
        let committed = try #require(Int(nonceTag[2]))
        // 12 bits is ~4,096 hashes, far inside the 2 s cap; a step-down would
        // still be an honest, lower commitment.
        #expect(committed == 12 || committed == 6)
        #expect(NostrPoW.validatedDifficulty(idHex: mined.id, tags: mined.tags) == committed)

        let unmined = context.sentGeohashContexts[1].event
        #expect(!unmined.tags.contains { $0.first == "nonce" })
        // The local echo still carries the signed event's ID.
        #expect(context.appendedPublicMessages.map(\.message.id) == [mined.id, unmined.id])
    }

    @Test @MainActor
    func sendMessage_onLocationChannel_reportsMiningUntilTheEventIsSigned() async {
        let context = MockChatOutgoingContext()
        let status = LocationPoWMiningStatus()
        var target = 8
        let coordinator = ChatOutgoingCoordinator(context: context, powTargetBits: { target }, miningStatus: status, finishAnimationDuration: 0)
        context.activeChannel = .location(GeohashChannel(level: .city, geohash: "u4pruydq"))

        // The send is pending from the moment it is sent, so its bubble can
        // show progress, and stops once the message is out.
        coordinator.sendMessage("mined")
        #expect(status.isMining)
        await coordinator.geohashMiningTask?.value
        #expect(!status.isMining)
        #expect(context.sentGeohashContexts.count == 1)

        // With proof of work off there is nothing to wait for or show.
        target = 0
        coordinator.sendMessage("not mined")
        #expect(!status.isMining)
        await coordinator.geohashMiningTask?.value
        #expect(!status.isMining)
        #expect(context.sentGeohashContexts.count == 2)
    }

    @Test @MainActor
    func expeditingASlowSendStillSendsItWithAnHonestLowerCommitment() async throws {
        let context = MockChatOutgoingContext()
        let status = LocationPoWMiningStatus()
        // 40 bits is out of reach, so only expediting ("send now") ends it.
        let coordinator = ChatOutgoingCoordinator(context: context, powTargetBits: { 40 }, miningStatus: status, finishAnimationDuration: 0)
        context.activeChannel = .location(GeohashChannel(level: .city, geohash: "u4pruydq"))

        coordinator.sendMessage("send it now")
        #expect(status.isMining)
        coordinator.expeditePendingGeohashMining()
        await coordinator.geohashMiningTask?.value

        #expect(!status.isMining)
        let event = try #require(context.sentGeohashContexts.first?.event)
        let nonceTag = try #require(event.tags.first { $0.first == "nonce" })
        let committed = try #require(Int(nonceTag[2]))
        #expect(committed < 40)
        #expect(NostrPoW.validatedDifficulty(idHex: event.id, tags: event.tags) == committed)
    }

    @Test @MainActor
    func aMinedSendShowsItsBubbleAtOnceAndKeepsItsPlace() async throws {
        let context = MockChatOutgoingContext()
        let status = LocationPoWMiningStatus()
        // Out of reach, so the bubble is certainly still pending below.
        let coordinator = ChatOutgoingCoordinator(
            context: context, powTargetBits: { 40 }, miningStatus: status, finishAnimationDuration: 0
        )
        context.activeChannel = .location(GeohashChannel(level: .city, geohash: "u4pruydq"))

        coordinator.sendMessage("hello @bob")

        // The bubble is there before any mining finished: mine, pending,
        // under a temporary ID, in the channel's conversation.
        #expect(context.appendedPublicMessages.count == 1)
        let pending = context.appendedPublicMessages[0]
        #expect(pending.conversationID == .geohash("u4pruydq"))
        #expect(pending.message.id.hasPrefix(ChatOutgoingCoordinator.pendingMessageIDPrefix))
        #expect(pending.message.deliveryStatus == .sending)
        #expect(pending.message.content == "hello @bob")
        #expect(pending.message.mentions == ["bob"])
        #expect(pending.message.isUnsentLocationMessage)
        #expect(status.send(for: pending.message.id)?.isMining == true)
        #expect(context.sentGeohashContexts.isEmpty)

        coordinator.expeditePendingGeohashMining()
        await coordinator.geohashMiningTask?.value

        // The sent message took the bubble's place: same timestamp (the
        // event's created_at), the event's ID, and no pending state left.
        let event = try #require(context.sentGeohashContexts.first?.event)
        #expect(context.replacedMessageIDs == [pending.message.id])
        #expect(context.appendedPublicMessages.count == 1)
        let sent = context.appendedPublicMessages[0].message
        #expect(sent.id == event.id)
        #expect(sent.timestamp == pending.message.timestamp)
        #expect(event.created_at == Int(pending.message.timestamp.timeIntervalSince1970))
        #expect(!sent.isUnsentLocationMessage)
        #expect(status.send(for: pending.message.id) == nil)
    }

    @Test @MainActor
    func leavingTheChannelDropsASendThatIsStillMining() async throws {
        let context = MockChatOutgoingContext()
        let status = LocationPoWMiningStatus()
        var target = 40
        let coordinator = ChatOutgoingCoordinator(
            context: context, powTargetBits: { target }, miningStatus: status, finishAnimationDuration: 0
        )
        context.activeChannel = .location(GeohashChannel(level: .city, geohash: "u4pruydq"))

        coordinator.sendMessage("never mind")
        let pendingID = try #require(context.appendedPublicMessages.first?.message.id)
        coordinator.abandonPendingGeohashSends()
        await coordinator.geohashMiningTask?.value

        // Not sent, and the bubble says so the way a failed message does.
        #expect(context.sentGeohashContexts.isEmpty)
        #expect(context.recordedActivityKeys.isEmpty)
        #expect(context.appendedPublicMessages.map(\.message.id) == [pendingID])
        #expect(context.appendedPublicMessages[0].message.deliveryStatus
                == .failed(reason: ChatOutgoingCoordinator.leftChannelReason))
        #expect(status.send(for: pendingID) == nil)

        // Leaving drops only what was pending then: the next send goes out.
        target = 8
        coordinator.sendMessage("back again")
        await coordinator.geohashMiningTask?.value
        #expect(context.sentGeohashContexts.count == 1)
        #expect(context.appendedPublicMessages.count == 2)
    }

    @Test @MainActor
    func aSendThatCannotBeSignedLeavesItsBubbleFailed() async throws {
        let context = MockChatOutgoingContext()
        let status = LocationPoWMiningStatus()
        context.identity = MockChatOutgoingContext.unsignableIdentity
        let coordinator = ChatOutgoingCoordinator(context: context, powTargetBits: { 8 }, miningStatus: status, finishAnimationDuration: 0)
        context.activeChannel = .location(GeohashChannel(level: .city, geohash: "u4pruydq"))

        coordinator.sendMessage("doomed")
        await coordinator.geohashMiningTask?.value

        #expect(context.sentGeohashContexts.isEmpty)
        let failed = try #require(context.appendedPublicMessages.first?.message)
        #expect(failed.deliveryStatus == .failed(reason: ChatOutgoingCoordinator.sendErrorReason))
        // The bubble tells; no extra system message on top.
        #expect(context.systemMessages.isEmpty)
        #expect(status.sends.isEmpty)
    }

    @Test @MainActor
    func sendMessage_onLocationChannel_serializesRapidSendsInSendOrder() async {
        let context = MockChatOutgoingContext()
        let coordinator = ChatOutgoingCoordinator(context: context, miningStatus: LocationPoWMiningStatus(), finishAnimationDuration: 0)
        let channel = GeohashChannel(level: .city, geohash: "u4pruydq")
        context.activeChannel = .location(channel)

        // Two back-to-back sends. The first carries much larger content, so
        // its NIP-13 mining hashes a bigger event per attempt and runs longer
        // than the second's. Without serialization the second (faster) task
        // could finish first and reorder both the local timeline and the
        // relayed events. The coordinator chains the mining tasks — each send
        // awaits the previous send's task before it echoes and relays — so the
        // visible order must always match the send order.
        let first = "first " + String(repeating: "x", count: 4000)
        let second = "second"
        coordinator.sendMessage(first)
        coordinator.sendMessage(second)

        // The stored task is the second send, which awaits the first.
        await coordinator.geohashMiningTask?.value
        await drainMainActorTasks()

        // Local echoes land in send order…
        #expect(context.appendedPublicMessages.map(\.message.content) == [first, second])
        // …and so do the relayed events (IDs match the echoes 1:1, in order).
        #expect(context.sentGeohashContexts.count == 2)
        #expect(context.sentGeohashContexts.map(\.event.id)
                == context.appendedPublicMessages.map(\.message.id))
    }
}
