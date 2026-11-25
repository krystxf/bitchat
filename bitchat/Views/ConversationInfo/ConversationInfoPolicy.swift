//
// ConversationInfoPolicy.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation

/// Decides what the conversation info page offers for one conversation:
/// the link under the name, the quick action buttons, the rows, and the
/// destructive action at the bottom.
///
/// The page lists only what the app can really do for that kind of
/// conversation. A row with no feature behind it (search, mute, invite
/// links) does not appear.
enum ConversationInfoPolicy {
    /// The open conversation, with the facts the choice depends on.
    enum Subject: Equatable {
        /// The public #mesh channel.
        case meshChannel
        /// A public location (geohash) channel.
        case locationChannel
        /// A direct conversation with one person.
        case person(Person)
        /// A private group.
        case group(Group)
    }

    struct Person: Equatable {
        /// A geohash DM. It runs over Nostr with a per-channel key, so the
        /// person has no Noise identity to favorite, verify or name.
        var isGeohashDM: Bool
        /// Their Noise fingerprint is known. A nickname (petname) is stored
        /// against it, so there is nothing to store it on before.
        var hasFingerprint: Bool
        /// A new group with them can start now: they are connected, not
        /// blocked, and their identity is known.
        var canCreateGroup: Bool
    }

    struct Group: Equatable {
        /// I created the group. Only the creator renames it and adds and
        /// removes members.
        var isCreator: Bool
        var memberCount: Int
    }

    /// A link-style button under the name.
    enum HeaderAction: Equatable {
        /// Set a nickname (petname) for the person, only on this device.
        case setNickname
        /// Rename the group for everyone in it.
        case renameGroup
    }

    /// An icon-over-label button in the row under the header.
    enum QuickAction: Equatable {
        /// Open the channel's notices board.
        case notices
        /// Bookmark the location channel, or remove the bookmark.
        case bookmark
        /// Share an invite to the location channel.
        case share
        /// Open the channel list to go to another channel.
        case channels
        /// Add the person to favorites, or remove them.
        case favorite
        /// Show the fingerprints to verify the encryption.
        case verify
        /// Start a new group with the person.
        case createGroup
        /// Invite people to the group.
        case addPeople
    }

    enum Row: Equatable {
        /// The chat background picker.
        case background
        /// Who is in the public channel, on a page of its own.
        case people
        /// The group's members, listed in place. `canRemove` adds a remove
        /// button to everyone but the creator.
        case members(canRemove: Bool)
    }

    /// The red action at the bottom of the page. It asks first.
    enum DestructiveAction: Equatable {
        case block
        case leaveGroup
    }

    struct Layout: Equatable {
        var headerAction: HeaderAction?
        var quickActions: [QuickAction]
        var rows: [Row]
        var destructiveAction: DestructiveAction?
    }

    static func layout(for subject: Subject) -> Layout {
        switch subject {
        case .meshChannel:
            return Layout(
                headerAction: nil,
                quickActions: [.notices, .channels],
                rows: [.background, .people],
                destructiveAction: nil
            )

        case .locationChannel:
            return Layout(
                headerAction: nil,
                quickActions: [.notices, .bookmark, .share, .channels],
                rows: [.background, .people],
                destructiveAction: nil
            )

        case .person(let person):
            var quickActions: [QuickAction] = []
            if !person.isGeohashDM {
                quickActions = [.favorite, .verify]
                if person.canCreateGroup {
                    quickActions.append(.createGroup)
                }
            }
            return Layout(
                headerAction: !person.isGeohashDM && person.hasFingerprint ? .setNickname : nil,
                quickActions: quickActions,
                rows: [.background],
                // A blocked person's chat does not open, so the page never
                // needs "unblock": settings lists blocked accounts.
                destructiveAction: .block
            )

        case .group(let group):
            let canManageMembers = GroupManagementPolicy.canManageMembers(isCreator: group.isCreator)
            let canAddPeople = canManageMembers && group.memberCount < BitchatGroup.maxMembers
            return Layout(
                headerAction: canManageMembers ? .renameGroup : nil,
                quickActions: canAddPeople ? [.addPeople] : [],
                rows: [.background, .members(canRemove: canManageMembers)],
                // The page shows only for a group I am in, so I can leave.
                destructiveAction: .leaveGroup
            )
        }
    }
}
