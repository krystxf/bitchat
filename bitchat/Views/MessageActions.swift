//
// MessageActions.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// Something to do with a message: one source for the native context menu
/// (macOS, and iOS before 16.4), the iOS long-press card and the VoiceOver
/// actions.
struct MessageAction: Identifiable {
    enum Kind: String {
        case resend, mention, directMessage, copy, block
    }

    let kind: Kind
    let perform: () -> Void

    var id: Kind { kind }

    var title: String {
        switch kind {
        case .resend: String(localized: "content.actions.resend", comment: "Message action that sends a failed message again")
        case .mention: String(localized: "content.actions.mention", comment: "Message action that @mentions the sender in the composer")
        case .directMessage: String(localized: "content.actions.direct_message", comment: "Message action that opens a private chat with the sender")
        case .copy: String(localized: "content.message.copy", comment: "Message action that copies the text")
        case .block: String(localized: "content.actions.block", comment: "Message action that blocks the sender")
        }
    }

    var systemImage: String {
        switch kind {
        case .resend: "arrow.clockwise"
        case .mention: "arrowshape.turn.up.left"
        case .directMessage: "bubble.left.and.bubble.right"
        case .copy: "doc.on.doc"
        case .block: "hand.raised"
        }
    }

    var isDestructive: Bool { kind == .block }

    /// A row of its own in the long-press card. The rest wait under More.
    var isPrimary: Bool { kind != .block }
}

/// The actions as native menu items, for a context menu.
struct MessageActionMenuItems: View {
    let actions: [MessageAction]

    var body: some View {
        ForEach(actions) { action in
            Button(role: action.isDestructive ? .destructive : nil, action: action.perform) {
                Label(action.title, systemImage: action.systemImage)
            }
        }
    }
}

/// Opens a message's actions. On iOS 16.4 and later a long press opens the
/// Liquid Glass overlay (`MessageActionsOverlay`) with the row's frame on
/// screen; before that, and on macOS, the native context menu shows
/// `menu`.
struct MessageMenuModifier<MenuContent: View>: ViewModifier {
    let onLongPress: (CGRect) -> Void
    @ViewBuilder let menu: () -> MenuContent

    /// The row's frame on screen, kept current without re-rendering the
    /// row on every scroll step.
    @State private var frameBox = FrameBox()

    final class FrameBox {
        var frame: CGRect = .zero
    }

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 16.4, *) {
            content
                .background {
                    GeometryReader { proxy in
                        let _ = frameBox.frame = proxy.frame(in: .global)
                        Color.clear
                    }
                }
                .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 10) {
                    onLongPress(frameBox.frame)
                }
        } else {
            content.contextMenu { menu() }
        }
        #else
        content.contextMenu { menu() }
        #endif
    }
}
