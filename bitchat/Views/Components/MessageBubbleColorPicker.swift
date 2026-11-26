import SwiftUI

/// Compact reusable palette picker for the default outgoing bubble color.
struct MessageBubbleColorPicker: View {
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "appearance.default_message_color", defaultValue: "Default Message Color"))
            HStack(spacing: 7) {
                ForEach(MessageBubbleColor.allCases) { option in
                    Button {
                        selection = option.rawValue
                    } label: {
                        ZStack {
                            Circle().fill(option.color)
                            if selection == option.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(.primary.opacity(0.18), lineWidth: 1))
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.label)
                    .accessibilityAddTraits(selection == option.rawValue ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
        }
    }
}
