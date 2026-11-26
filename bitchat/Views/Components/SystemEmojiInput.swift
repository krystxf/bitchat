//
// SystemEmojiInput.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

#if os(iOS)
/// A hidden text field that raises the system emoji keyboard, for picking a
/// reaction the way the user knows from typing. The first emoji typed is
/// the pick; anything else is ignored. The emoji keyboard opens only when
/// it is turned on in Settings; otherwise the field gets the current
/// keyboard, whose globe key reaches it.
struct EmojiKeyboardInput: UIViewRepresentable {
    @Binding var isActive: Bool
    let onEmoji: (String) -> Void

    func makeUIView(context: Context) -> EmojiTextField {
        let field = EmojiTextField()
        field.delegate = context.coordinator
        field.tintColor = .clear
        field.textColor = .clear
        field.autocorrectionType = .no
        field.isAccessibilityElement = false
        return field
    }

    func updateUIView(_ field: EmojiTextField, context: Context) {
        context.coordinator.parent = self
        if isActive, !field.isFirstResponder {
            DispatchQueue.main.async { field.becomeFirstResponder() }
        } else if !isActive, field.isFirstResponder {
            DispatchQueue.main.async { field.resignFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: EmojiKeyboardInput

        init(parent: EmojiKeyboardInput) {
            self.parent = parent
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if let emoji = string.first.map(String.init), MessageReaction.isReactionEmoji(emoji) {
                parent.isActive = false
                parent.onEmoji(emoji)
            }
            return false
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            if parent.isActive { parent.isActive = false }
        }
    }
}

/// Asks for the emoji keyboard: a text field reports the emoji input mode
/// as its own, the common way to open it. Returning an empty context
/// identifier keeps iOS from restoring the last keyboard instead.
final class EmojiTextField: UITextField {
    override var textInputContextIdentifier: String? { "" }

    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
    }
}
#endif

#if os(macOS)
/// Picks a reaction with the system Character Viewer ("Emoji & Symbols").
/// The viewer types into the key window's focused field, so a hidden field
/// in the chat window (`CharacterViewerHost`) takes the focus, the viewer
/// opens, and the first emoji typed goes to the waiting pick. The picker's
/// popover closes first: clicking in the viewer would close it anyway.
final class CharacterViewerBridge: ObservableObject {
    static let shared = CharacterViewerBridge()

    /// Bumped on each request; the host focuses its field and opens the
    /// viewer.
    @Published private(set) var requestCount = 0
    private var handler: ((String) -> Void)?

    func request(_ handler: @escaping (String) -> Void) {
        self.handler = handler
        requestCount += 1
    }

    /// Hands the first emoji in `text` to the waiting pick. Returns false
    /// when nothing waits or `text` holds no emoji.
    @discardableResult
    func deliver(_ text: String) -> Bool {
        guard let handler, let emoji = text.first.map(String.init), MessageReaction.isReactionEmoji(emoji) else {
            return false
        }
        self.handler = nil
        handler(emoji)
        return true
    }

    func cancel() {
        handler = nil
    }
}

/// The hidden field the Character Viewer types into; mounted once in the
/// chat.
struct CharacterViewerHost: View {
    @ObservedObject private var bridge = CharacterViewerBridge.shared
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .accessibilityHidden(true)
            .onChange(of: bridge.requestCount) { _ in
                isFocused = true
                DispatchQueue.main.async { NSApp.orderFrontCharacterPalette(nil) }
            }
            .onChange(of: text) { newText in
                guard !newText.isEmpty else { return }
                // A pick, or something else typed: either way the wait ends.
                if !bridge.deliver(newText) { bridge.cancel() }
                text = ""
                isFocused = false
            }
            .onChange(of: isFocused) { focused in
                if !focused { bridge.cancel() }
            }
    }
}
#endif
