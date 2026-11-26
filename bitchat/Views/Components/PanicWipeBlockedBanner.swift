//
// PanicWipeBlockedBanner.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// Shown under the header while a panic wipe has not committed
/// (`ChatViewModel.panicRecoveryBlocked`). A wipe that fails must be as loud
/// as the wipe itself: the person who triggered it may be relying on the
/// device being clean, and networking stays disabled until a relaunch retries
/// the transaction — without this banner the app just looks silently dead.
struct PanicWipeBlockedBanner: View {
    @ThemedPalette private var palette

    private var message: String {
        String(
            localized: "content.banner.panic_blocked",
            defaultValue: "wipe incomplete — some data may remain. quit and reopen bitchat to retry.",
            comment: "Banner shown when a panic wipe did not fully commit; relaunching the app retries the wipe"
        )
    }

    var body: some View {
        ChatBanner(systemImage: "exclamationmark.triangle.fill", symbolColor: palette.alertRed) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(palette.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
