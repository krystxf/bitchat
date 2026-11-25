//
// SidebarPeopleTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import Foundation
import Testing
@testable import bitchat

struct ContactStandingTests {
    @Test func aStrangerIsNotAContact() {
        #expect(!ContactStanding().isContact)
    }

    @Test func aFavoriteIsAContact() {
        #expect(ContactStanding(isFavorite: true).isContact)
    }

    @Test func aVerifiedPersonIsAContact() {
        #expect(ContactStanding(isVerified: true).isContact)
    }

    @Test func anAcceptedConversationMakesAContact() {
        #expect(ContactStanding(hasAcceptedConversation: true).isContact)
    }

    @Test func youAreNeverYourOwnContact() {
        #expect(!ContactStanding(isMe: true, isFavorite: true, isVerified: true).isContact)
    }

    @Test func blockingMovesAContactOut() {
        #expect(!ContactStanding(
            isBlocked: true,
            isFavorite: true,
            isVerified: true,
            hasAcceptedConversation: true
        ).isContact)
    }
}

struct SidebarPeopleTests {
    @Test func splitsEachRosterIntoContactsAndUnknownPeople() {
        let me = meshPeer("me", isMe: true, isFavorite: true)
        let favorite = meshPeer("friend", isFavorite: true)
        let verified = meshPeer("verified", isVerified: true)
        let stranger = meshPeer("stranger", hasUnread: true)
        let blockedFavorite = meshPeer("blocked", isFavorite: true, isBlocked: true)

        let geoMe = geohashPerson("ab", isMe: true)
        let geoAccepted = geohashPerson("cd", hasAcceptedConversation: true)
        let geoStranger = geohashPerson("ef")

        let acceptedChat = chat("00000000000000c1", hasAcceptedConversation: true)
        let request = chat("00000000000000c2", hasUnread: true)
        let verifiedChat = chat("00000000000000c3", isVerified: true)

        let bridged = BridgeService.BridgedParticipant(pubkey: "ff", nickname: "far", lastSeen: Date())

        let people = SidebarPeople(
            meshPeers: [me, favorite, stranger, verified, blockedFavorite],
            geohashPeople: [geoMe, geoStranger, geoAccepted],
            chats: [request, acceptedChat, verifiedChat],
            bridgedPeople: [bridged]
        )

        #expect(people.contacts.meshPeers == [favorite, verified])
        #expect(people.contacts.geohashPeople == [geoAccepted])
        #expect(people.contacts.chats == [acceptedChat, verifiedChat])
        #expect(people.contacts.bridgedPeople.isEmpty)

        #expect(people.unknown.meshPeers == [stranger, blockedFavorite])
        #expect(people.unknown.geohashPeople == [geoStranger])
        #expect(people.unknown.chats == [request])
        #expect(people.unknown.bridgedPeople == [bridged])
    }

    @Test func countsUnknownPeopleAndTheirUnreadChats() {
        let people = SidebarPeople(
            meshPeers: [meshPeer("quiet"), meshPeer("loud", hasUnread: true)],
            geohashPeople: [geohashPerson("ab")],
            chats: [chat("00000000000000c2", hasUnread: true), chat("00000000000000c4")],
            bridgedPeople: [BridgeService.BridgedParticipant(pubkey: "ff", nickname: nil, lastSeen: Date())]
        )

        #expect(people.contacts.isEmpty)
        #expect(people.unknown.count == 6)
        #expect(people.unknown.unreadCount == 2)
    }

    @Test func yourOwnRowsAreLeftOut() {
        let people = SidebarPeople(
            meshPeers: [meshPeer("me", isMe: true)],
            geohashPeople: [geohashPerson("ab", isMe: true)],
            chats: []
        )

        #expect(people.contacts.isEmpty)
        #expect(people.unknown.isEmpty)
    }

    // MARK: - Helpers

    private func meshPeer(
        _ name: String,
        isMe: Bool = false,
        isFavorite: Bool = false,
        isVerified: Bool = false,
        isBlocked: Bool = false,
        hasUnread: Bool = false,
        hasAcceptedConversation: Bool = false
    ) -> MeshPeerRow {
        MeshPeerRow(
            peerID: PeerID(str: name),
            displayName: name,
            isMe: isMe,
            hasUnread: hasUnread,
            isBlocked: isBlocked,
            isFavorite: isFavorite,
            isConnected: true,
            isReachable: true,
            isMutualFavorite: false,
            encryptionStatus: .noHandshake,
            showsVerifiedBadgeWhenOffline: false,
            showsVouchedBadge: false,
            isVerified: isVerified,
            hasAcceptedConversation: hasAcceptedConversation
        )
    }

    private func geohashPerson(
        _ id: String,
        isMe: Bool = false,
        hasAcceptedConversation: Bool = false
    ) -> GeohashPersonRow {
        GeohashPersonRow(
            id: id,
            displayName: id,
            isMe: isMe,
            isTeleported: false,
            isBlocked: false,
            hasAcceptedConversation: hasAcceptedConversation
        )
    }

    private func chat(
        _ peerID: String,
        hasUnread: Bool = false,
        isVerified: Bool = false,
        hasAcceptedConversation: Bool = false
    ) -> RecentChatRow {
        RecentChatRow(
            peerID: PeerID(str: peerID),
            displayName: peerID,
            hasUnread: hasUnread,
            lastActivity: Date(timeIntervalSince1970: 100),
            isFavorite: false,
            isVerified: isVerified,
            hasAcceptedConversation: hasAcceptedConversation
        )
    }
}

/// How `PeerListModel` decides that a conversation was accepted.
@MainActor
struct PeerListModelContactTests {
    @Test func aConversationWithOnlyTheirMessagesIsARequest() async throws {
        let viewModel = makeViewModel()
        let model = makeModel(viewModel)
        let peerID = PeerID(str: "00000000000000d1")

        viewModel.seedPrivateChat([message(id: "in-1", from: peerID)], for: peerID)

        let listed = await TestHelpers.waitUntil({
            model.recentChatRows.contains { $0.peerID == peerID }
        }, timeout: TestConstants.settleTimeout)
        try #require(listed)
        #expect(model.recentChatRows.first { $0.peerID == peerID }?.hasAcceptedConversation == false)
    }

    @Test func replyingAcceptsTheConversation() async {
        let viewModel = makeViewModel()
        let model = makeModel(viewModel)
        let peerID = PeerID(str: "00000000000000d2")

        viewModel.seedPrivateChat([
            message(id: "in-1", from: peerID),
            message(id: "out-1", from: viewModel.meshService.myPeerID)
        ], for: peerID)

        let accepted = await TestHelpers.waitUntil({
            model.recentChatRows.first { $0.peerID == peerID }?.hasAcceptedConversation == true
        }, timeout: TestConstants.settleTimeout)
        #expect(accepted)
    }

    @Test func openingAcceptsTheConversationUntilItIsRemoved() async throws {
        let viewModel = makeViewModel()
        let model = makeModel(viewModel)
        let peerID = PeerID(str: "00000000000000d3")

        viewModel.seedPrivateChat([message(id: "in-1", from: peerID)], for: peerID)
        viewModel.conversations.setSelectedPrivatePeer(peerID)
        viewModel.conversations.setSelectedPrivatePeer(nil)

        let accepted = await TestHelpers.waitUntil({
            model.recentChatRows.first { $0.peerID == peerID }?.hasAcceptedConversation == true
        }, timeout: TestConstants.settleTimeout)
        try #require(accepted)

        // A wipe removes the conversation, and its acceptance with it: a
        // new message from the same person arrives as a request again.
        viewModel.conversations.clearAll()
        let wiped = await TestHelpers.waitUntil({
            !model.recentChatRows.contains { $0.peerID == peerID }
        }, timeout: TestConstants.settleTimeout)
        try #require(wiped)
        viewModel.seedPrivateChat([message(id: "in-2", from: peerID)], for: peerID)

        let requestAgain = await TestHelpers.waitUntil({
            model.recentChatRows.first { $0.peerID == peerID }?.hasAcceptedConversation == false
        }, timeout: TestConstants.settleTimeout)
        #expect(requestAgain)
    }

    // MARK: - Helpers

    private func message(id: String, from sender: PeerID) -> BitchatMessage {
        BitchatMessage(
            id: id,
            sender: "someone",
            content: "hello",
            timestamp: Date(timeIntervalSince1970: 100),
            isRelay: false,
            isPrivate: true,
            recipientNickname: "me",
            senderPeerID: sender
        )
    }

    private func makeModel(_ viewModel: ChatViewModel) -> PeerListModel {
        PeerListModel(
            chatViewModel: viewModel,
            conversations: viewModel.conversations,
            locationChannelsModel: LocationChannelsModel(manager: makeLocationManager())
        )
    }

    private func makeViewModel() -> ChatViewModel {
        let keychain = MockKeychain()
        return ChatViewModel(
            keychain: keychain,
            idBridge: NostrIdentityBridge(keychain: MockKeychainHelper()),
            identityManager: MockIdentityManager(keychain),
            transport: MockTransport(),
            locationManager: makeLocationManager()
        )
    }

    private func makeLocationManager() -> LocationChannelManager {
        let suiteName = "SidebarPeopleTests.\(UUID().uuidString)"
        let storage = UserDefaults(suiteName: suiteName) ?? .standard
        storage.removePersistentDomain(forName: suiteName)
        return LocationChannelManager(storage: storage)
    }
}
