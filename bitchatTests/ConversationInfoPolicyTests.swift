//
// ConversationInfoPolicyTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Testing
@testable import bitchat

struct ConversationInfoPolicyTests {
    private typealias Policy = ConversationInfoPolicy

    private static func person(
        isGeohashDM: Bool = false,
        hasFingerprint: Bool = true,
        canCreateGroup: Bool = false,
        isBlocked: Bool = false
    ) -> Policy.Subject {
        .person(Policy.Person(
            isGeohashDM: isGeohashDM,
            hasFingerprint: hasFingerprint,
            canCreateGroup: canCreateGroup,
            isBlocked: isBlocked
        ))
    }

    private static func group(isCreator: Bool, memberCount: Int = 3) -> Policy.Subject {
        .group(Policy.Group(isCreator: isCreator, memberCount: memberCount))
    }

    // MARK: - Channels

    @Test func meshHasNoBookmarkOrShare() {
        let layout = Policy.layout(for: .meshChannel)
        #expect(layout.quickActions == [.notices])
        #expect(layout.rows == [.background, .people])
        #expect(layout.headerAction == nil)
        #expect(layout.footerAction == nil)
    }

    @Test func aLocationChannelCanBeBookmarkedAndShared() {
        let layout = Policy.layout(for: .locationChannel)
        #expect(layout.quickActions == [.notices, .bookmark, .share])
        #expect(layout.rows == [.background, .people])
        #expect(layout.headerAction == nil)
        #expect(layout.footerAction == nil)
    }

    // MARK: - People

    @Test func aMeshPersonCanBeFavoritedVerifiedNamedAndBlocked() {
        let layout = Policy.layout(for: Self.person())
        #expect(layout.quickActions == [.favorite, .verify])
        #expect(layout.headerAction == .setNickname)
        #expect(layout.rows == [.background])
        #expect(layout.footerAction == .block)
    }

    @Test func aGroupStartsOnlyWithSomeoneWhoCanJoinIt() {
        #expect(Policy.layout(for: Self.person(canCreateGroup: true)).quickActions == [.favorite, .verify, .createGroup])
        #expect(!Policy.layout(for: Self.person(canCreateGroup: false)).quickActions.contains(.createGroup))
    }

    @Test func aNicknameNeedsAFingerprintToBeStoredOn() {
        #expect(Policy.layout(for: Self.person(hasFingerprint: false)).headerAction == nil)
    }

    @Test func aGeohashDMHasNoMeshIdentityActions() {
        let layout = Policy.layout(for: Self.person(isGeohashDM: true, hasFingerprint: true, canCreateGroup: true))
        #expect(layout.quickActions.isEmpty)
        #expect(layout.headerAction == nil)
        #expect(layout.rows == [.background])
        #expect(layout.footerAction == .block)
    }

    @Test func aBlockedPersonCanBeUnblockedButNotFavoritedOrGrouped() {
        let layout = Policy.layout(for: Self.person(canCreateGroup: true, isBlocked: true))
        #expect(layout.quickActions == [.verify])
        #expect(layout.headerAction == .setNickname)
        #expect(layout.footerAction == .unblock)
    }

    // MARK: - Groups

    @Test func theCreatorRenamesTheGroupAndAddsAndRemovesMembers() {
        let layout = Policy.layout(for: Self.group(isCreator: true))
        #expect(layout.headerAction == .renameGroup)
        #expect(layout.quickActions == [.addPeople])
        #expect(layout.rows == [.background, .members(canRemove: true)])
        #expect(layout.footerAction == .leaveGroup)
    }

    @Test func aMemberOnlySeesTheMembersAndCanLeave() {
        let layout = Policy.layout(for: Self.group(isCreator: false))
        #expect(layout.headerAction == nil)
        #expect(layout.quickActions.isEmpty)
        #expect(layout.rows == [.background, .members(canRemove: false)])
        #expect(layout.footerAction == .leaveGroup)
    }

    @Test func aFullGroupTakesNoMorePeople() {
        let full = Policy.layout(for: Self.group(isCreator: true, memberCount: BitchatGroup.maxMembers))
        #expect(full.quickActions.isEmpty)
        #expect(full.rows.contains(.members(canRemove: true)))
        let oneSeatLeft = Policy.layout(for: Self.group(isCreator: true, memberCount: BitchatGroup.maxMembers - 1))
        #expect(oneSeatLeft.quickActions == [.addPeople])
    }

    // MARK: - People in a list

    private static func listed(
        isMe: Bool = false,
        hasMeshIdentity: Bool = true,
        isFavorite: Bool = false,
        isBlocked: Bool = false,
        canCreateGroup: Bool = false
    ) -> Policy.ListedPerson {
        Policy.ListedPerson(
            isMe: isMe,
            hasMeshIdentity: hasMeshIdentity,
            isFavorite: isFavorite,
            isBlocked: isBlocked,
            canCreateGroup: canCreateGroup
        )
    }

    @Test func nothingIsOfferedOnMyself() {
        #expect(Policy.personActions(for: Self.listed(isMe: true, canCreateGroup: true)).isEmpty)
    }

    @Test func aMeshPersonCanBeFavoritedGroupedAndBlocked() {
        #expect(Policy.personActions(for: Self.listed(canCreateGroup: true)) == [.favorite, .createGroup, .block])
        #expect(Policy.personActions(for: Self.listed(isFavorite: true)) == [.unfavorite, .block])
    }

    @Test func aGroupNeedsSomeoneWhoCanJoinIt() {
        #expect(!Policy.personActions(for: Self.listed(canCreateGroup: false)).contains(.createGroup))
    }

    @Test func aLocationChannelPersonCanOnlyBeBlocked() {
        let actions = Policy.personActions(for: Self.listed(hasMeshIdentity: false, canCreateGroup: true))
        #expect(actions == [.block])
    }

    @Test func aBlockedPersonCanOnlyBeUnblocked() {
        #expect(Policy.personActions(for: Self.listed(isFavorite: true, isBlocked: true, canCreateGroup: true)) == [.unblock])
        #expect(Policy.personActions(for: Self.listed(hasMeshIdentity: false, isBlocked: true)) == [.unblock])
    }
}
