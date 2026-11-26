import SwiftUI

/// Per-conversation outgoing bubble color. “Default” removes the override so
/// the current Settings default continues to apply.
struct ConversationMessageColorPickerRow: View {
    let conversationKey: ComposerDraftStore.Key
    @State private var selection: String = "default"
    @AppStorage(MessageBubbleColorSettings.key) private var defaultColorRawValue = MessageBubbleColor.blue.rawValue

    var body: some View {
        Menu {
            Picker(Strings.title, selection: $selection) {
                Text(Strings.defaultChoice).tag("default")
                ForEach(MessageBubbleColor.allCases) { color in
                    Label {
                        Text(color.label)
                    } icon: {
                        Circle().fill(color.color).frame(width: 14, height: 14)
                    }
                    .tag(color.rawValue)
                }
            }
        } label: {
            #if os(iOS)
            // A Settings menu row, like the background row under it: the
            // title in the text color and the current choice at the
            // trailing edge, so the whole row opens the menu.
            HStack(spacing: 6) {
                rowLabel
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(verbatim: selectionName)
                    .foregroundStyle(.novaSecondaryText)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.novaSecondaryText)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            #else
            rowLabel
            #endif
        }
        .onAppear { load() }
        .onChange(of: selection) { raw in
            ConversationMessageColorStore.shared.set(raw == "default" ? nil : MessageBubbleColor(rawValue: raw), for: conversationKey)
        }
    }

    private var rowLabel: some View {
        Label {
            Text(Strings.title)
        } icon: {
            Circle()
                .fill(MessageBubbleColor(rawValue: selection)?.color ?? MessageBubbleColor(rawValue: defaultColorRawValue)?.color ?? MessageBubbleColor.blue.color)
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(.primary.opacity(0.2), lineWidth: 1))
        }
    }

    /// The current choice as the row shows it: the color's name, or
    /// "Default" while the conversation follows the Settings default.
    private var selectionName: String {
        MessageBubbleColor(rawValue: selection)?.label ?? Strings.defaultChoice
    }

    private func load() {
        selection = ConversationMessageColorStore.shared.override(for: conversationKey)?.rawValue ?? "default"
    }

    private enum Strings {
        static let title = String(localized: "appearance.message_color", defaultValue: "Message Color")
        static let defaultChoice = String(localized: "appearance.default", defaultValue: "Default")
    }
}
