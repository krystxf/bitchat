//
// BlockedAccountsSheet.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import SwiftUI

/// Everyone the user blocked, opened from the Privacy section of settings,
/// with an unblock button per row, so a block can be undone without typing
/// `/unblock`.
struct BlockedAccountsSheet: View {
    let load: @MainActor () -> [BlockedAccount]
    let onUnblock: @MainActor (BlockedAccount) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var accounts: [BlockedAccount] = []

    enum Strings {
        static let title = String(localized: "blocked_accounts.title", defaultValue: "Blocked Accounts", comment: "Title of the blocked accounts list, and of the settings row that opens it")
        static let empty = String(localized: "blocked_accounts.empty", defaultValue: "No Blocked Accounts", comment: "Shown in the blocked accounts list when nobody is blocked")
        static let footer = String(localized: "blocked_accounts.footer", defaultValue: "Blocked people can't message you and their messages stay hidden. Unblock someone to see them again.", comment: "Footer under the blocked accounts list explaining what blocking does")
        static let mesh = String(localized: "blocked_accounts.kind.mesh", defaultValue: "Mesh", comment: "Label for an account blocked on the Bluetooth mesh, in the blocked accounts list")
        static let location = String(localized: "blocked_accounts.kind.location", defaultValue: "Location channels", comment: "Label for an account blocked in location (geohash) channels, in the blocked accounts list")
        static let unblock = String(localized: "geohash_people.action.unblock", comment: "Action to unblock a person")
    }

    var body: some View {
        Group {
            if accounts.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        ForEach(accounts) { account in
                            row(for: account)
                        }
                    } footer: {
                        Text(verbatim: Strings.footer)
                            .novaSectionText()
                    }
                    .novaRows()
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #else
                .listStyle(.inset)
                #endif
                .novaGroupedList()
            }
        }
        .sheetChrome(title: Text(verbatim: Strings.title), onClose: { dismiss() })
        .onAppear {
            accounts = load()
            #if DEBUG
            if SidebarSampleData.isEnabled { accounts = SidebarSampleData.blockedAccounts }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 360, idealHeight: 480)
        #endif
    }

    private func row(for account: BlockedAccount) -> some View {
        HStack(spacing: 12) {
            InitialsAvatar(name: account.name, peerID: avatarPeerID(for: account), size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: account.name)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(verbatim: kindLabel(for: account))
                    Text(verbatim: "·")
                    // A key: monospaced, so similar ones line up. It never
                    // truncates; the kind does first.
                    Text(verbatim: account.shortKey)
                        .monospaced()
                        .fixedSize()
                }
                .font(.footnote)
                .foregroundStyle(.novaSecondaryText)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(Strings.unblock) {
                unblock(account)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text(verbatim: Strings.unblock)) {
            unblock(account)
        }
        #if os(iOS)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(Strings.unblock) {
                unblock(account)
            }
            .tint(.novaAccent)
        }
        #endif
    }

    private var emptyState: some View {
        SheetEmptyState(title: Strings.empty, systemImage: "hand.raised.slash", message: Strings.footer)
    }

    private func unblock(_ account: BlockedAccount) {
        onUnblock(account)
        withAnimation {
            accounts = load()
        }
    }

    /// The peer ID the rest of the app seeds this person's avatar with, so
    /// the avatar matches the one beside their messages: a mesh peer's
    /// short ID is the start of their fingerprint.
    private func avatarPeerID(for account: BlockedAccount) -> PeerID {
        switch account.kind {
        case .mesh(let fingerprint): return PeerID(str: fingerprint.prefix(16))
        case .nostr(let pubkeyHex): return PeerID(nostr_: pubkeyHex)
        }
    }

    private func kindLabel(for account: BlockedAccount) -> String {
        switch account.kind {
        case .mesh: return Strings.mesh
        case .nostr: return Strings.location
        }
    }
}
