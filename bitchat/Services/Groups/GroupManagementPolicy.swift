import Foundation

/// Pure policy used by group creation and management views.
enum GroupManagementPolicy {
    static let maximumNameLength = 40

    static func defaultName(with nickname: String) -> String {
        let name = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "group" : "\(name) + me"
    }

    static func validatedName(_ rawName: String) -> String? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= maximumNameLength else { return nil }
        return name
    }

    static func canInvite(isMe: Bool, isBlocked: Bool, isMember: Bool, isReachable: Bool,
                          hasVerifiedIdentity: Bool, isCreator: Bool, memberCount: Int) -> Bool {
        !isMe && !isBlocked && !isMember && isReachable && hasVerifiedIdentity && isCreator
            && memberCount < BitchatGroup.maxMembers
    }

    static func canManageMembers(isCreator: Bool) -> Bool { isCreator }
    static func canLeaveGroup(isMember: Bool) -> Bool { isMember }
}
