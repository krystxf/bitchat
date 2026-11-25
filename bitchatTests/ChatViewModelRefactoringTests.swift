//
// ChatViewModelRefactoringTests.swift
// bitchatTests
//
// Pinning tests to characterize ChatViewModel behavior before refactoring.
// These tests act as a safety net to ensure we don't break existing functionality.
//

import Testing
import Foundation
import BitFoundation
@testable import bitchat

struct ChatViewModelRefactoringTests {

    // Helper to setup the environment
    @MainActor
    private func makePinnedViewModel() -> (viewModel: ChatViewModel, transport: MockTransport, identity: MockIdentityManager) {
        let keychain = MockKeychain()
        let keychainHelper = MockKeychainHelper()
        let idBridge = NostrIdentityBridge(keychain: keychainHelper)
        let identityManager = MockIdentityManager(keychain)
        let transport = MockTransport()

        let viewModel = ChatViewModel(
            keychain: keychain,
            idBridge: idBridge,
            identityManager: identityManager,
            transport: transport
        )

        return (viewModel, transport, identityManager)
    }

    // MARK: - Command Processor Integration "Pinning"
    
    @Test @MainActor
    func command_block_updatesIdentity() async throws {
        let (viewModel, transport, identity) = makePinnedViewModel()
        
        // Setup: Use simulateConnect
        let peerID = PeerID(str: "0000000000000002")
        // Mock the fingerprint so the block command finds it
        transport.peerFingerprints[peerID] = "fingerprint_123"
        transport.simulateConnect(peerID, nickname: "troll")

        let didResolve = await TestHelpers.waitUntil({ viewModel.getPeerIDForNickname("troll") != nil },
                                                     timeout: TestConstants.settleTimeout)
        #expect(didResolve)
        
        // Action
        viewModel.sendMessage("/block @troll")
        
        // Assert
        // Verify identity manager was called to block "fingerprint_123"
        let didBlock = await TestHelpers.waitUntil({ identity.isBlocked(fingerprint: "fingerprint_123") },
                                                   timeout: TestConstants.settleTimeout)
        #expect(didBlock)
    }

    // MARK: - Message Routing Logic

    @Test @MainActor
    func routing_incomingPrivateMessage_addsToPrivateChats() async {
        let (viewModel, _, _) = makePinnedViewModel()
        let senderID = PeerID(str: "sender_1")

        // Setup
        let message = BitchatMessage(
            id: "msg_1",
            sender: "bob",
            content: "Secret",
            timestamp: Date(),
            isRelay: false,
            originalSender: nil,
            isPrivate: true,
            recipientNickname: "me",
            senderPeerID: senderID,
            mentions: nil
        )

        // Action: Simulate incoming private message
        viewModel.didReceiveMessage(message)

        // Wait for async processing with proper timeout
        let found = await TestHelpers.waitUntil(
            { viewModel.privateChats[senderID]?.first?.content == "Secret" },
            timeout: TestConstants.settleTimeout
        )

        // Assert
        #expect(found)
    }

    @Test @MainActor
    func routing_incomingPublicMessage_addsToPublicTimeline() async {
        let (viewModel, _, _) = makePinnedViewModel()
        let senderID = PeerID(str: "sender_2")

        // Action
        viewModel.didReceivePublicMessage(
            from: senderID,
            nickname: "charlie",
            content: "Public Hi",
            timestamp: Date(),
            messageID: "msg_2"
        )

        // Wait for async processing with proper timeout
        let found = await TestHelpers.waitUntil(
            {
                viewModel.publicMessages(for: .mesh).contains(where: { $0.content == "Public Hi" })
            },
            timeout: TestConstants.settleTimeout
        )

        // Assert
        #expect(found)
    }
}
