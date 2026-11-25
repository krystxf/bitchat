//
// PersonInfoPage.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import SwiftUI

/// The info page of the open direct conversation: the person's avatar and
/// name with how they are reachable, a link to set a nickname only this
/// device uses, favorite, verify and new group, the background, and block
/// or unblock.
struct PersonInfoPage: View {
    @EnvironmentObject private var appChromeModel: AppChromeModel
    @EnvironmentObject private var conversationUIModel: ConversationUIModel
    @EnvironmentObject private var privateConversationModel: PrivateConversationModel
    @EnvironmentObject private var verificationModel: VerificationModel
    // Republishes when a block or favorite changes the person's row.
    @EnvironmentObject private var peerListModel: PeerListModel

    /// How the person is reachable, as the title bar says it.
    let subtitle: String
    @Binding var background: ChatBackgroundOption
    let backgroundKey: ComposerDraftStore.Key

    @State private var showsNicknamePrompt = false
    @State private var nickname = ""
    @State private var showsCreateGroupPrompt = false
    @State private var newGroupName = ""
    @State private var showsBlockConfirmation = false

    var body: some View {
        if let headerState = privateConversationModel.selectedHeaderState, !headerState.isGroupConversation {
            page(for: headerState)
        }
    }

    private func page(for headerState: PrivateConversationHeaderState) -> some View {
        let person = PersonFacts(headerState: headerState, model: conversationUIModel)
        let layout = ConversationInfoPolicy.layout(for: .person(person.policyFacts))

        return ConversationInfoPage(
            title: Text(verbatim: headerState.displayName),
            subtitle: subtitle,
            avatar: {
                InitialsAvatar(
                    name: person.avatarName,
                    peerID: headerState.headerPeerID,
                    size: ConversationInfoMetrics.avatarSize
                )
            },
            headerAction: {
                if layout.headerAction == .setNickname {
                    Button {
                        nickname = verificationModel
                            .fingerprintPresentation(for: headerState.headerPeerID)
                            .localPetname ?? ""
                        showsNicknamePrompt = true
                    } label: {
                        Text(verbatim: Strings.setNickname)
                    }
                }
            },
            quickActions: {
                ForEach(layout.quickActions, id: \.self) { action in
                    quickAction(action, headerState: headerState, person: person)
                }
            },
            sections: {
                ForEach(layout.rows, id: \.self) { row in
                    if row == .background {
                        Section {
                            ChatBackgroundPickerRow(conversationKey: backgroundKey, selection: $background)
                        }
                    }
                }
                if let footer = layout.footerAction {
                    Section {
                        footerButton(footer, headerState: headerState, person: person)
                    }
                }
            }
        )
        .alert(Text(verbatim: Strings.setNickname), isPresented: $showsNicknamePrompt) {
            TextField(Strings.nicknamePlaceholder, text: $nickname)
            Button("common.cancel", role: .cancel) {}
            Button("save") {
                verificationModel.setLocalPetname(nickname, for: headerState.headerPeerID)
            }
        } message: {
            Text(verbatim: Strings.nicknameHint)
        }
        .alert("group.create.title", isPresented: $showsCreateGroupPrompt) {
            TextField("group.create.name", text: $newGroupName)
            Button("common.cancel", role: .cancel) {}
            Button("group.create.action") {
                // Opens the new group's chat, which closes this page.
                _ = conversationUIModel.createGroup(named: newGroupName, inviting: person.actionPeerID)
            }
        } message: {
            Text("group.create.prompt")
        }
        .confirmationDialog(
            Text(verbatim: Strings.blockConfirmTitle(headerState.displayName)),
            isPresented: $showsBlockConfirmation,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                conversationUIModel.block(peerID: person.actionPeerID, displayName: headerState.displayName)
            } label: {
                Text(verbatim: Strings.block)
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text(verbatim: Strings.blockConfirmMessage)
        }
    }

    @ViewBuilder
    private func quickAction(
        _ action: ConversationInfoPolicy.QuickAction,
        headerState: PrivateConversationHeaderState,
        person: PersonFacts
    ) -> some View {
        switch action {
        case .favorite:
            ConversationQuickAction(
                title: Strings.favorite,
                systemImage: "star",
                isOn: headerState.isFavorite,
                accessibilityLabel: headerState.isFavorite ? Strings.removeFavorite : Strings.addFavorite
            ) {
                privateConversationModel.toggleFavoriteForSelectedConversation()
            }
        case .verify:
            ConversationQuickAction(
                title: Strings.verify,
                systemImage: "checkmark.shield",
                accessibilityLabel: Strings.verifyEncryption,
                accessibilityHint: Strings.viewFingerprintHint
            ) {
                appChromeModel.showFingerprint(for: headerState.headerPeerID)
            }
        case .createGroup:
            ConversationQuickAction(
                title: String(localized: "group.create.title", comment: "Title of the prompt that names a new group"),
                systemImage: "person.3",
                accessibilityLabel: String(
                    format: String(localized: "group.action.create_with_peer", comment: "Action that starts a new group with the person; placeholder is their name"),
                    locale: .current,
                    headerState.displayName
                )
            ) {
                newGroupName = GroupManagementPolicy.defaultName(with: headerState.displayName)
                showsCreateGroupPrompt = true
            }
        case .notices, .bookmark, .share, .channels, .addPeople:
            // Not offered for a person (see ConversationInfoPolicy).
            EmptyView()
        }
    }

    @ViewBuilder
    private func footerButton(
        _ action: ConversationInfoPolicy.FooterAction,
        headerState: PrivateConversationHeaderState,
        person: PersonFacts
    ) -> some View {
        switch action {
        case .block:
            Button(role: .destructive) {
                showsBlockConfirmation = true
            } label: {
                Text(verbatim: Strings.block)
            }
        case .unblock:
            Button {
                conversationUIModel.unblock(peerID: person.actionPeerID, displayName: headerState.displayName)
            } label: {
                Text(verbatim: Strings.unblock)
            }
        case .leaveGroup:
            // Not offered for a person (see ConversationInfoPolicy).
            EmptyView()
        }
    }
}

/// What the page needs to know about the person, read once per render.
private struct PersonFacts {
    let policyFacts: ConversationInfoPolicy.Person
    /// The ID that block, unblock and a new group act on: the short mesh
    /// ID, or the geohash DM key, which maps to their full Nostr key.
    let actionPeerID: PeerID
    /// The name the initials come from. A geohash DM's title is
    /// "#geohash/@name", and the initials belong to the name.
    let avatarName: String

    @MainActor
    init(headerState: PrivateConversationHeaderState, model: ConversationUIModel) {
        let isGeohashDM = headerState.conversationPeerID.isGeoDM
        actionPeerID = isGeohashDM ? headerState.conversationPeerID : headerState.headerPeerID
        policyFacts = ConversationInfoPolicy.Person(
            isGeohashDM: isGeohashDM,
            hasFingerprint: !isGeohashDM && model.getFingerprint(for: headerState.headerPeerID) != nil,
            canCreateGroup: !isGeohashDM && model.canCreateGroup(with: headerState.headerPeerID),
            isBlocked: model.isBlocked(peerID: actionPeerID)
        )
        if isGeohashDM, let range = headerState.displayName.range(of: "/@") {
            avatarName = String(headerState.displayName[range.upperBound...])
        } else {
            avatarName = headerState.displayName
        }
    }
}

private enum Strings {
    static let setNickname = String(localized: "conversation_info.action.set_nickname", defaultValue: "Set Nickname", comment: "Link under a person's name on their details page; opens a prompt for a nickname that only this device uses")
    static let nicknamePlaceholder = String(localized: "fingerprint.local_alias.placeholder", comment: "Placeholder for the local alias (petname) field")
    static let nicknameHint = String(localized: "fingerprint.local_alias.hint", comment: "Hint under the local alias field")
    static let favorite = String(localized: "mesh_peers.state.favorite", comment: "State label for a favorited peer")
    static let addFavorite = String(localized: "content.accessibility.add_favorite", comment: "Accessibility label to add a favorite")
    static let removeFavorite = String(localized: "content.accessibility.remove_favorite", comment: "Accessibility label to remove a favorite")
    static let verify = String(localized: "conversation_info.action.verify", defaultValue: "Verify", comment: "Short label of the button on a person's details page that shows the encryption fingerprints to verify")
    static let verifyEncryption = String(localized: "content.accessibility.verification", comment: "Accessibility label for the verification QR button")
    static let viewFingerprintHint = String(localized: "content.accessibility.view_fingerprint_hint", comment: "Accessibility hint for viewing encryption fingerprint")
    static let block = String(localized: "content.actions.block", comment: "Action that blocks the person")
    static let unblock = String(localized: "geohash_people.action.unblock", comment: "Context menu action to unblock a person")
    static let blockConfirmMessage = String(localized: "conversation_info.block.message", defaultValue: "You will no longer see their messages. You can unblock them in Settings.", comment: "Message of the confirmation before blocking a person from their details page")

    static func blockConfirmTitle(_ name: String) -> String {
        String(
            format: String(localized: "conversation_info.block.confirm", defaultValue: "Block %@?", comment: "Title of the confirmation before blocking a person from their details page; placeholder is their name"),
            locale: .current,
            name
        )
    }
}
