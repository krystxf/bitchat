import SwiftUI

/// Per-conversation outgoing bubble color. “Default” removes the override so
/// the current Settings default continues to apply.
struct ConversationMessageColorPickerRow: View {
    let conversationKey: ComposerDraftStore.Key
    @State private var selection: String = "default"
    @AppStorage(MessageBubbleColorSettings.key) private var defaultColorRawValue = MessageBubbleColor.blue.rawValue

    var body: some View {
        Menu {
            Picker(String(localized: "appearance.message_color", defaultValue: "Message Color"), selection: $selection) {
                Text(String(localized: "appearance.default", defaultValue: "Default")).tag("default")
                ForEach(MessageBubbleColor.allCases) { color in
                    Label {
                        Text(color.rawValue.capitalized)
                    } icon: {
                        Circle().fill(color.color).frame(width: 14, height: 14)
                    }
                    .tag(color.rawValue)
                }
            }
        } label: {
            Label {
                Text(String(localized: "appearance.message_color", defaultValue: "Message Color"))
            } icon: {
                Circle()
                    .fill(MessageBubbleColor(rawValue: selection)?.color ?? MessageBubbleColor(rawValue: defaultColorRawValue)?.color ?? MessageBubbleColor.blue.color)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(.primary.opacity(0.2), lineWidth: 1))
            }
        }
        .onAppear { load() }
        .onChange(of: selection) { raw in
            ConversationMessageColorStore.shared.set(raw == "default" ? nil : MessageBubbleColor(rawValue: raw), for: conversationKey)
        }
    }

    private func load() {
        selection = ConversationMessageColorStore.shared.override(for: conversationKey)?.rawValue ?? "default"
    }
}
