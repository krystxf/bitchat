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
/// or unblock. Block and new group run through the shared person actions
/// (`personActionsHost()`), as in the people lists.
struct PersonInfoPage: View {
    /// How the person is reachable, as the title bar says it.
    let subtitle: String
    @Binding var background: ChatBackgroundOption
    let backgroundKey: ComposerDraftStore.Key

    var body: some View {
        PersonInfoContent(subtitle: subtitle, background: $background, backgroundKey: backgroundKey)
            .personActionsHost()
    }
}

private struct PersonInfoContent: View {
    @Environment(\.personActions) private var personActions
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
                            ConversationAppearanceRows(conversationKey: backgroundKey, background: $background)
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
                accessibilityLabel: headerState.isFavorite ? PersonActionStrings.unfavorite : PersonActionStrings.favorite
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
                title: Strings.newGroup,
                systemImage: "person.3",
                accessibilityLabel: PersonActionStrings.createGroup(with: headerState.displayName)
            ) {
                // Asks for the name; the new group's chat then replaces
                // this page.
                personActions?.perform(.createGroup, person.actionTarget)
            }
        case .notices, .bookmark, .share, .addPeople:
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
                personActions?.perform(.block, person.actionTarget)
            } label: {
                Text(verbatim: PersonActionStrings.block)
            }
        case .unblock:
            Button {
                personActions?.perform(.unblock, person.actionTarget)
            } label: {
                Text(verbatim: PersonActionStrings.unblock)
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
    /// What block, unblock and a new group act on: the short mesh ID, or
    /// the geohash DM key, which maps to their full Nostr key.
    let actionTarget: PersonActionTarget
    /// The name the initials come from. A geohash DM's title is
    /// "#geohash/@name", and the initials belong to the name.
    let avatarName: String

    @MainActor
    init(headerState: PrivateConversationHeaderState, model: ConversationUIModel) {
        let isGeohashDM = headerState.conversationPeerID.isGeoDM
        let actionPeerID = isGeohashDM ? headerState.conversationPeerID : headerState.headerPeerID
        let canCreateGroup = !isGeohashDM && model.canCreateGroup(with: headerState.headerPeerID)
        let isBlocked = model.isBlocked(peerID: actionPeerID)
        policyFacts = ConversationInfoPolicy.Person(
            isGeohashDM: isGeohashDM,
            hasFingerprint: !isGeohashDM && model.getFingerprint(for: headerState.headerPeerID) != nil,
            canCreateGroup: canCreateGroup,
            isBlocked: isBlocked
        )
        actionTarget = PersonActionTarget(
            identity: isGeohashDM ? .geohashDM(actionPeerID) : .mesh(actionPeerID),
            displayName: headerState.displayName,
            facts: ConversationInfoPolicy.ListedPerson(
                isMe: false,
                hasMeshIdentity: !isGeohashDM,
                isFavorite: headerState.isFavorite,
                isBlocked: isBlocked,
                canCreateGroup: canCreateGroup
            )
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
    static let favorite = String(localized: "conversation_info.action.favorite", defaultValue: "Favorite", comment: "Short label of the button on a person's details page that adds them to favorites or removes them")
    static let newGroup = String(localized: "conversation_info.action.new_group", defaultValue: "New Group", comment: "Short label of the button on a person's details page that starts a new group with them")
    static let verify = String(localized: "conversation_info.action.verify", defaultValue: "Verify", comment: "Short label of the button on a person's details page that shows the encryption fingerprints to verify")
    static let verifyEncryption = String(localized: "content.accessibility.verification", comment: "Accessibility label for the verification QR button")
    static let viewFingerprintHint = String(localized: "content.accessibility.view_fingerprint_hint", comment: "Accessibility hint for viewing encryption fingerprint")
}
