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
        canCreateGroup: Bool = false
    ) -> Policy.Subject {
        .person(Policy.Person(
            isGeohashDM: isGeohashDM,
            hasFingerprint: hasFingerprint,
            canCreateGroup: canCreateGroup
        ))
    }

    private static func group(isCreator: Bool, memberCount: Int = 3) -> Policy.Subject {
        .group(Policy.Group(isCreator: isCreator, memberCount: memberCount))
    }

    // MARK: - Channels

    @Test func meshHasNoBookmarkOrShare() {
        let layout = Policy.layout(for: .meshChannel)
        #expect(layout.quickActions == [.notices, .channels])
        #expect(layout.rows == [.background, .people])
        #expect(layout.headerAction == nil)
        #expect(layout.destructiveAction == nil)
    }

    @Test func aLocationChannelCanBeBookmarkedAndShared() {
        let layout = Policy.layout(for: .locationChannel)
        #expect(layout.quickActions == [.notices, .bookmark, .share, .channels])
        #expect(layout.rows == [.background, .people])
        #expect(layout.headerAction == nil)
        #expect(layout.destructiveAction == nil)
    }

    // MARK: - People

    @Test func aMeshPersonCanBeFavoritedVerifiedNamedAndBlocked() {
        let layout = Policy.layout(for: Self.person())
        #expect(layout.quickActions == [.favorite, .verify])
        #expect(layout.headerAction == .setNickname)
        #expect(layout.rows == [.background])
        #expect(layout.destructiveAction == .block)
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
        #expect(layout.destructiveAction == .block)
    }

    // MARK: - Groups

    @Test func theCreatorRenamesTheGroupAndAddsAndRemovesMembers() {
        let layout = Policy.layout(for: Self.group(isCreator: true))
        #expect(layout.headerAction == .renameGroup)
        #expect(layout.quickActions == [.addPeople])
        #expect(layout.rows == [.background, .members(canRemove: true)])
        #expect(layout.destructiveAction == .leaveGroup)
    }

    @Test func aMemberOnlySeesTheMembersAndCanLeave() {
        let layout = Policy.layout(for: Self.group(isCreator: false))
        #expect(layout.headerAction == nil)
        #expect(layout.quickActions.isEmpty)
        #expect(layout.rows == [.background, .members(canRemove: false)])
        #expect(layout.destructiveAction == .leaveGroup)
    }

    @Test func aFullGroupTakesNoMorePeople() {
        let full = Policy.layout(for: Self.group(isCreator: true, memberCount: BitchatGroup.maxMembers))
        #expect(full.quickActions.isEmpty)
        #expect(full.rows.contains(.members(canRemove: true)))
        let oneSeatLeft = Policy.layout(for: Self.group(isCreator: true, memberCount: BitchatGroup.maxMembers - 1))
        #expect(oneSeatLeft.quickActions == [.addPeople])
    }
}
