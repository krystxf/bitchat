import Foundation

/// Pure policy used by group creation and management views.
enum GroupManagementPolicy {
    static func defaultName(with nickname: String) -> String {
        let name = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "group" : "\(name) + me"
    }

    static func canInvite(isMe: Bool, isBlocked: Bool, isMember: Bool, isReachable: Bool,
                          hasVerifiedIdentity: Bool, isCreator: Bool, memberCount: Int) -> Bool {
        !isMe && !isBlocked && !isMember && isReachable && hasVerifiedIdentity && isCreator
            && memberCount < BitchatGroup.maxMembers
    }

    static func canManageMembers(isCreator: Bool) -> Bool { isCreator }
    static func canLeaveGroup(isMember: Bool) -> Bool { isMember }
}
