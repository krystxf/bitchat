//
// SheetCloseToolbarItem.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// The close button of a sheet, as a native toolbar item. Put it in the
/// toolbar of the sheet's `NavigationStack` root:
///
///     .toolbar { SheetCloseToolbarItem { dismiss() } }
///
/// Where it shows:
/// - iOS: the leading edge of the navigation bar (`.cancellationAction`).
/// - macOS: the trailing edge of the sheet's bottom button bar. A macOS
///   sheet has no title bar, so modal actions go to that bar.
struct SheetCloseToolbarItem: ToolbarContent {
    var placement: ToolbarItemPlacement = .cancellationAction
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: placement) {
            SheetCloseToolbarButton(action: action)
        }
    }
}

/// The button inside `SheetCloseToolbarItem`, for toolbars that group it
/// with other items. OS 26 uses the system close role: iOS draws the glass
/// "X", macOS draws a "Close" push button. Older systems get a text button
/// with the standard toolbar look.
struct SheetCloseToolbarButton: View {
    let action: () -> Void

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            Button(role: .close, action: action)
        } else {
            fallbackButton
        }
        #else
        fallbackButton
        #endif
    }

    private var fallbackButton: some View {
        Button(action: action) {
            Text(String(localized: "common.close", comment: "Accessibility label for close buttons"))
        }
    }
}
