import SwiftUI

/// Reusable group info content for the conversation info page and its sheet
/// presentation. Each operation is also exposed as a standalone component.
struct GroupInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let group: BitchatGroup
    let people: [MeshPeerRow]
    let isCreator: Bool
    let canInvite: (MeshPeerRow) -> Bool
    let onRename: (String) -> Void
    let onInvite: (String) -> Void
    let onRemove: (String) -> Void
    let onLeave: () -> Void

    var body: some View {
        List {
            if isCreator {
                GroupRenameControl(groupName: group.name, onRename: onRename)
                GroupMemberList(
                    members: group.members,
                    creatorFingerprint: group.creatorFingerprint,
                    canRemove: true,
                    onRemove: onRemove
                )
                GroupAddPeoplePicker(people: people.filter(canInvite), onInvite: onInvite)
            } else {
                GroupMemberList(
                    members: group.members,
                    creatorFingerprint: group.creatorFingerprint,
                    canRemove: false,
                    onRemove: onRemove
                )
            }
            GroupLeaveControl(onLeave: onLeave)
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .sheetChrome(title: Text("group.info.title"), onClose: { dismiss() })
    }
}

struct GroupMemberList: View {
    @State private var pendingRemoval: GroupMember?
    let members: [GroupMember]
    let creatorFingerprint: String
    let canRemove: Bool
    let onRemove: (String) -> Void

    var body: some View {
        Section("group.members.title") {
            ForEach(members, id: \.fingerprint) { member in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: member.nickname)
                        if member.fingerprint == creatorFingerprint {
                            Text("group.members.creator").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if canRemove && member.fingerprint != creatorFingerprint {
                        Button(role: .destructive) { pendingRemoval = member } label: {
                            Image(systemName: "person.crop.circle.badge.minus")
                        }
                        .accessibilityLabel(Text(verbatim: "\(String(localized: "group.member.remove")) \(member.nickname)"))
                    }
                }
            }
        }
        .confirmationDialog("group.member.remove_confirm", isPresented: Binding(
            get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }
        ), titleVisibility: .visible) {
            if let member = pendingRemoval {
                Button("group.member.remove", role: .destructive) {
                    onRemove(member.nickname)
                    pendingRemoval = nil
                }
            }
            Button("common.cancel", role: .cancel) { pendingRemoval = nil }
        }
    }
}

struct GroupAddPeoplePicker: View {
    let people: [MeshPeerRow]
    let onInvite: (String) -> Void

    var body: some View {
        Section("group.invite.title") {
            if people.isEmpty {
                Text("group.invite.empty").foregroundStyle(.secondary)
            }
            ForEach(people) { peer in
                Button {
                    onInvite(peer.displayName)
                } label: {
                    Label(peer.displayName, systemImage: "person.badge.plus")
                }
                .accessibilityLabel(Text(verbatim: "\(String(localized: "group.invite.person")) \(peer.displayName)"))
            }
        }
    }
}

struct GroupRenameControl: View {
    @State private var isPromptPresented = false
    @State private var name: String
    let onRename: (String) -> Void

    init(groupName: String, onRename: @escaping (String) -> Void) {
        _name = State(initialValue: groupName)
        self.onRename = onRename
    }

    var body: some View {
        Section {
            Button {
                isPromptPresented = true
            } label: {
                Label("group.rename.action", systemImage: "pencil")
            }
            .accessibilityLabel(Text("group.rename.action"))
        }
        .alert("group.rename.title", isPresented: $isPromptPresented) {
            TextField("group.create.name", text: $name)
            Button("common.cancel", role: .cancel) {}
            Button("group.rename.action") { onRename(name) }
        }
    }
}

struct GroupLeaveControl: View {
    @State private var isConfirmationPresented = false
    let onLeave: () -> Void

    var body: some View {
        Section {
            Button("group.leave.action", role: .destructive) {
                isConfirmationPresented = true
            }
            .accessibilityLabel(Text("group.leave.action"))
        }
        .confirmationDialog("group.leave.confirm", isPresented: $isConfirmationPresented, titleVisibility: .visible) {
            Button("group.leave.action", role: .destructive, action: onLeave)
            Button("common.cancel", role: .cancel) {}
        }
    }
}
