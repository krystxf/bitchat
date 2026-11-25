import SwiftUI

/// Compact reusable palette picker for the global outgoing bubble color.
struct MessageBubbleColorPicker: View {
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "app_info.settings.bubble_color.title", defaultValue: "my message color", comment: "Label for the global outgoing message bubble color picker"))
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
                    .accessibilityLabel("#\(hexLabel(for: option))")
                    .accessibilityAddTraits(selection == option.rawValue ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func hexLabel(for option: MessageBubbleColor) -> String {
        let rgb = option.rgb
        return String(format: "%02X%02X%02X", Int(rgb.red * 255), Int(rgb.green * 255), Int(rgb.blue * 255))
    }
}
