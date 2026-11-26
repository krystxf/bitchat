//
// BlockedAccountsSheet.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

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
        static let empty = String(localized: "blocked_accounts.empty", defaultValue: "No blocked accounts", comment: "Shown in the blocked accounts list when nobody is blocked")
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
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #else
                .listStyle(.inset)
                #endif
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
            Image(systemName: icon(for: account))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: account.name)
                    .font(.body)
                    .lineLimit(1)
                Text(verbatim: "\(kindLabel(for: account)) · \(account.shortKey)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(Strings.unblock) {
                unblock(account)
            }
            .buttonStyle(.bordered)
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
            .tint(.blue)
        }
        #endif
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "hand.raised.slash")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(verbatim: Strings.empty)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func unblock(_ account: BlockedAccount) {
        onUnblock(account)
        withAnimation {
            accounts = load()
        }
    }

    private func icon(for account: BlockedAccount) -> String {
        switch account.kind {
        case .mesh: return "antenna.radiowaves.left.and.right"
        case .nostr: return "number"
        }
    }

    private func kindLabel(for account: BlockedAccount) -> String {
        switch account.kind {
        case .mesh: return Strings.mesh
        case .nostr: return Strings.location
        }
    }
}
