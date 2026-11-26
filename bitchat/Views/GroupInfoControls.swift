import SwiftUI

// The group controls the conversation info page hosts (`GroupInfoPage`):
// the member list, the add-people picker, rename for the creator, and
// leave.

struct GroupMemberList: View {
    @State private var pendingRemoval: GroupMember?
    let members: [GroupMember]
    let creatorFingerprint: String
    let canRemove: Bool
    let onRemove: (String) -> Void
    /// Who a member's context menu acts on (`personActions(for:)`), or nil
    /// for no menu: myself, or a member with no route right now.
    var actionTarget: (GroupMember) -> PersonActionTarget? = { _ in nil }

    var body: some View {
        Section {
            ForEach(members, id: \.fingerprint) { member in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: member.nickname)
                            .lineLimit(1)
                        if member.fingerprint == creatorFingerprint {
                            Text("group.members.creator")
                                .font(.footnote)
                                .foregroundStyle(.novaSecondaryText)
                        }
                    }
                    Spacer(minLength: 8)
                    if canRemove && member.fingerprint != creatorFingerprint {
                        Button(role: .destructive) { pendingRemoval = member } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .red)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text(verbatim: "\(String(localized: "group.member.remove")) \(member.nickname)"))
                    }
                }
                .contentShape(Rectangle())
                .personActions(for: actionTarget(member))
            }
        } header: {
            Text("group.members.title")
                .foregroundColor(.novaSecondaryText)
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
        Section {
            if people.isEmpty {
                Text("group.invite.empty")
                    .foregroundStyle(.novaSecondaryText)
            }
            ForEach(people) { peer in
                Button {
                    onInvite(peer.displayName)
                } label: {
                    Label(peer.displayName, systemImage: "person.badge.plus")
                }
                .accessibilityLabel(Text(verbatim: "\(String(localized: "group.invite.person")) \(peer.displayName)"))
            }
        } header: {
            Text("group.invite.title")
                .foregroundColor(.novaSecondaryText)
        }
    }
}

/// Renames the group, for its creator: a button that asks for the new
/// name. The page shows it as the link under the group's name.
struct GroupRenameControl: View {
    @State private var isPromptPresented = false
    @State private var name = ""
    let groupName: String
    let onRename: (String) -> Void

    init(groupName: String, onRename: @escaping (String) -> Void) {
        self.groupName = groupName
        self.onRename = onRename
    }

    var body: some View {
        Button {
            // Start from the current name, also after a rename.
            name = groupName
            isPromptPresented = true
        } label: {
            Text("group.rename.action")
        }
        .accessibilityLabel(Text("group.rename.title"))
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
