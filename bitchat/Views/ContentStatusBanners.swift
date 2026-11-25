//
// ContentStatusBanners.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// Status that floats under a conversation's title bar while it applies:
/// a panic wipe that did not commit, and lost connectivity. Every
/// conversation shows it, public or private, so the signal stays on screen
/// wherever the user is.
struct ContentStatusBanners: View {
    @EnvironmentObject private var appChromeModel: AppChromeModel

    var body: some View {
        VStack(spacing: 0) {
            // Failed-wipe outranks connectivity: "your data may still be
            // here" matters more than "the radio is off".
            if appChromeModel.panicWipeBlocked {
                PanicWipeBlockedBanner()
            }

            if let issue = ConnectivityIssue.resolve(
                bluetoothState: appChromeModel.bluetoothState,
                torBlocked: appChromeModel.torBlocked
            ) {
                ConnectivityStatusBanner(issue: issue)
            }
        }
    }
}
