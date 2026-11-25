import XCTest
@testable import bitchat

final class GroupManagementPolicyTests: XCTestCase {
    func testDefaultNameUsesPeerNicknameAndFallback() {
        XCTAssertEqual(GroupManagementPolicy.defaultName(with: "  alex "), "alex + me")
        XCTAssertEqual(GroupManagementPolicy.defaultName(with: "  "), "group")
    }

    func testGroupNameValidationTrimsAndEnforcesLength() {
        XCTAssertEqual(GroupManagementPolicy.validatedName("  study group  "), "study group")
        XCTAssertNil(GroupManagementPolicy.validatedName(" \n "))
        XCTAssertEqual(GroupManagementPolicy.validatedName(String(repeating: "a", count: 40))?.count, 40)
        XCTAssertNil(GroupManagementPolicy.validatedName(String(repeating: "a", count: 41)))
    }

    func testInviteRequiresCreatorAndVerifiedReachableNonmember() {
        let eligible = GroupManagementPolicy.canInvite(isMe: false, isBlocked: false, isMember: false,
            isReachable: true, hasVerifiedIdentity: true, isCreator: true, memberCount: 2)
        XCTAssertTrue(eligible)
        XCTAssertFalse(GroupManagementPolicy.canInvite(isMe: true, isBlocked: false, isMember: false,
            isReachable: true, hasVerifiedIdentity: true, isCreator: true, memberCount: 2))
        XCTAssertFalse(GroupManagementPolicy.canInvite(isMe: false, isBlocked: true, isMember: false,
            isReachable: true, hasVerifiedIdentity: true, isCreator: true, memberCount: 2))
        XCTAssertFalse(GroupManagementPolicy.canInvite(isMe: false, isBlocked: false, isMember: true,
            isReachable: true, hasVerifiedIdentity: true, isCreator: true, memberCount: 2))
        XCTAssertFalse(GroupManagementPolicy.canInvite(isMe: false, isBlocked: false, isMember: false,
            isReachable: false, hasVerifiedIdentity: true, isCreator: true, memberCount: 2))
        XCTAssertFalse(GroupManagementPolicy.canInvite(isMe: false, isBlocked: false, isMember: false,
            isReachable: true, hasVerifiedIdentity: false, isCreator: true, memberCount: 2))
        XCTAssertFalse(GroupManagementPolicy.canInvite(isMe: false, isBlocked: false, isMember: false,
            isReachable: true, hasVerifiedIdentity: true, isCreator: false, memberCount: 2))
    }

    func testInviteHonorsGroupCapacityAndRoles() {
        XCTAssertFalse(GroupManagementPolicy.canInvite(isMe: false, isBlocked: false, isMember: false,
            isReachable: true, hasVerifiedIdentity: true, isCreator: true, memberCount: BitchatGroup.maxMembers))
        XCTAssertTrue(GroupManagementPolicy.canManageMembers(isCreator: true))
        XCTAssertFalse(GroupManagementPolicy.canManageMembers(isCreator: false))
        XCTAssertTrue(GroupManagementPolicy.canLeaveGroup(isMember: true))
        XCTAssertFalse(GroupManagementPolicy.canLeaveGroup(isMember: false))
    }
}
