//
// GroupInfoPage.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// The info page of the open private group: its name and member count,
/// rename for the creator, the members (the creator can remove them), the
/// background, and leave. The creator's "add people" button opens the
/// people who can join.
struct GroupInfoPage: View {
    @EnvironmentObject private var conversationUIModel: ConversationUIModel
    // Republishes when the group changes (a rename, a member joins or
    // leaves), so the page re-reads it.
    @EnvironmentObject private var privateConversationModel: PrivateConversationModel
    @EnvironmentObject private var peerListModel: PeerListModel

    @Binding var background: ChatBackgroundOption
    let backgroundKey: ComposerDraftStore.Key

    @State private var showsAddPeople = false

    var body: some View {
        if let group = conversationUIModel.selectedGroup() {
            page(for: group)
        }
    }

    private func page(for group: BitchatGroup) -> some View {
        let isCreator = group.creatorFingerprint == conversationUIModel.currentNoiseFingerprint
        let layout = ConversationInfoPolicy.layout(for: .group(.init(
            isCreator: isCreator,
            memberCount: group.members.count
        )))

        return ConversationInfoPage(
            title: GroupName.text(group.name),
            subtitle: ConversationInfoStrings.peopleCount(group.members.count),
            avatar: {
                ConversationGlyphAvatar(systemImage: "person.3.fill", color: .accentColor)
            },
            headerAction: {
                if layout.headerAction == .renameGroup {
                    GroupRenameControl(groupName: group.name) { name in
                        _ = conversationUIModel.groupRename(named: name)
                    }
                }
            },
            quickActions: {
                ForEach(layout.quickActions, id: \.self) { action in
                    quickAction(action)
                }
            },
            sections: {
                ForEach(layout.rows, id: \.self) { row in
                    section(row, group: group)
                }
                if layout.footerAction == .leaveGroup {
                    GroupLeaveControl {
                        _ = conversationUIModel.groupLeave()
                    }
                }
            }
        )
        .sheet(isPresented: $showsAddPeople) {
            GroupAddPeopleSheet(onClose: { showsAddPeople = false })
                .environmentObject(conversationUIModel)
                .environmentObject(peerListModel)
                .environmentObject(privateConversationModel)
        }
    }

    @ViewBuilder
    private func quickAction(_ action: ConversationInfoPolicy.QuickAction) -> some View {
        switch action {
        case .addPeople:
            ConversationQuickAction(
                title: String(localized: "group.invite.title", comment: "Title of the list of people the group creator can add"),
                systemImage: "person.badge.plus"
            ) {
                showsAddPeople = true
            }
        case .notices, .bookmark, .share, .channels, .favorite, .verify, .createGroup:
            // Not offered for a group (see ConversationInfoPolicy).
            EmptyView()
        }
    }

    @ViewBuilder
    private func section(_ row: ConversationInfoPolicy.Row, group: BitchatGroup) -> some View {
        switch row {
        case .background:
            Section {
                ChatBackgroundPickerRow(conversationKey: backgroundKey, selection: $background)
            }
        case .members(let canRemove):
            GroupMemberList(
                members: group.members,
                creatorFingerprint: group.creatorFingerprint,
                canRemove: canRemove,
                onRemove: { nickname in
                    _ = conversationUIModel.groupRemove(nickname: nickname)
                }
            )
        case .people:
            // Not offered for a group (see ConversationInfoPolicy).
            EmptyView()
        }
    }
}

/// The people the creator can add to the open group: connected, not
/// blocked, with a known identity, and not in it yet. Someone leaves the
/// list once added.
private struct GroupAddPeopleSheet: View {
    @EnvironmentObject private var conversationUIModel: ConversationUIModel
    @EnvironmentObject private var peerListModel: PeerListModel
    @EnvironmentObject private var privateConversationModel: PrivateConversationModel

    let onClose: () -> Void

    var body: some View {
        List {
            GroupAddPeoplePicker(people: candidates) { nickname in
                _ = conversationUIModel.groupInvite(nickname: nickname)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        .frame(minWidth: 360, minHeight: 360)
        #endif
        .sheetChrome(
            title: Text(String(localized: "group.invite.title", comment: "Title of the list of people the group creator can add")),
            onClose: onClose
        )
    }

    private var candidates: [MeshPeerRow] {
        guard let group = conversationUIModel.selectedGroup() else { return [] }
        let isCreator = group.creatorFingerprint == conversationUIModel.currentNoiseFingerprint
        return peerListModel.meshRows.filter { peer in
            GroupManagementPolicy.canInvite(
                isMe: peer.isMe,
                isBlocked: peer.isBlocked,
                isMember: conversationUIModel.isGroupMember(peer.peerID, group: group),
                isReachable: peer.isConnected,
                hasVerifiedIdentity: conversationUIModel.canCreateGroup(with: peer.peerID),
                isCreator: isCreator,
                memberCount: group.members.count
            )
        }
    }
}

/// "#name", as the sidebar shows a group. Not localized: there is nothing
/// to translate. The name is isolated, so the "#" stays on the same side of
/// a right-to-left name.
enum GroupName {
    static func text(_ name: String) -> Text {
        var hashtag = AttributedString("#\u{2068}\(name)\u{2069}")
        hashtag.languageIdentifier = Bundle.main.preferredLocalizations.first ?? "en"
        return Text(hashtag)
    }
}
