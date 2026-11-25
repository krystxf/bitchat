import SwiftUI

/// Shared submenu for choosing the backdrop of a single conversation.
struct ChatBackgroundPickerMenu: View {
    let conversationKey: ComposerDraftStore.Key
    @Binding var selection: ChatBackgroundOption

    var body: some View {
        Menu {
            Picker(
                String(localized: "chat.background.title", comment: "Menu title for choosing a chat conversation background"),
                selection: $selection
            ) {
                ForEach(ChatBackgroundOption.allCases) { option in
                    Label {
                        Text(option.label)
                    } icon: {
                        Circle()
                            .fill(option.swatch)
                            .frame(width: 11, height: 11)
                            .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
                    }
                    .tag(option)
                }
            }
        } label: {
            Label {
                Text(String(localized: "chat.background.title", comment: "Menu title for choosing a chat conversation background"))
            } icon: {
                Image(systemName: "circle.lefthalf.filled")
            }
        }
        .onChange(of: selection) { option in
            ChatBackgroundStore.shared.set(option, for: conversationKey)
        }
    }
}

/// The background row of the conversation info page: a menu picker whose
/// icon is a swatch of the current background. The choice applies at once
/// and is stored for this conversation.
struct ChatBackgroundPickerRow: View {
    let conversationKey: ComposerDraftStore.Key
    @Binding var selection: ChatBackgroundOption

    var body: some View {
        Picker(selection: Binding(
            get: { selection },
            set: { option in
                selection = option
                ChatBackgroundStore.shared.set(option, for: conversationKey)
            }
        )) {
            ForEach(ChatBackgroundOption.allCases) { option in
                Text(option.label).tag(option)
            }
        } label: {
            Label {
                Text(String(localized: "chat.background.title", comment: "Menu title for choosing a chat conversation background"))
            } icon: {
                ChatBackgroundSwatch(option: selection)
            }
        }
        .pickerStyle(.menu)
    }
}

/// A small disc in a background's color, with a hairline so the black OLED
/// swatch shows on a dark row.
private struct ChatBackgroundSwatch: View {
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 18
    let option: ChatBackgroundOption

    var body: some View {
        Circle()
            .fill(option.swatch)
            .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private extension ChatBackgroundOption {
    var label: String {
        switch self {
        case .default: String(localized: "chat.background.default", comment: "The default chat background option")
        case .dusk: String(localized: "chat.background.dusk", comment: "The dusk chat background option")
        case .ocean: String(localized: "chat.background.ocean", comment: "The ocean chat background option")
        case .forest: String(localized: "chat.background.forest", comment: "The forest chat background option")
        case .oled: String(localized: "chat.background.oled", comment: "The OLED black chat background option")
        }
    }

    var swatch: Color {
        switch self {
        case .default: Color(red: 0.28, green: 0.30, blue: 0.40)
        case .dusk: Color(red: 0.36, green: 0.21, blue: 0.39)
        case .ocean: Color(red: 0.12, green: 0.34, blue: 0.48)
        case .forest: Color(red: 0.17, green: 0.36, blue: 0.28)
        case .oled: .black
        }
    }
}
