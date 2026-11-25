import SwiftUI
import PhotosUI

/// A small preview of the conversation's background photo.
struct ChatBackgroundMenuThumbnail: View {
    let url: URL
    @State private var image: Image?
    var body: some View {
        Group {
            if let image { image.resizable().scaledToFill() }
            else { Image(systemName: "photo") }
        }
        .frame(width: 16, height: 16).clipShape(RoundedRectangle(cornerRadius: 3))
        .task(id: url) {
            image = await Task.detached(priority: .utility) { ChatBackgroundRasterCache.shared.image(at: url) }.value
        }
    }
}

/// The background row of the conversation info page: a menu picker whose
/// icon is a swatch of the current background. The choice applies at once
/// and is stored for this conversation.
struct ChatBackgroundPickerRow: View {
    let conversationKey: ComposerDraftStore.Key
    @Binding var selection: ChatBackgroundOption
    @State private var pickedPhoto: PhotosPickerItem?

    var body: some View {
        Menu {
            Picker(String(localized: "chat.background.title", comment: "Menu title for choosing a chat conversation background"), selection: $selection) {
                ForEach(ChatBackgroundOption.allCases.filter { $0 != .image }) { option in
                    Text(option.label).tag(option)
                }
            }
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                Label(String(localized: "chat.background.choose_image", comment: "Choose a local chat background photo"), systemImage: "photo")
            }
            if selection == .image {
                Label {
                    Text(String(localized: "chat.background.image", comment: "Custom image chat background"))
                } icon: {
                    ChatBackgroundMenuThumbnail(url: ChatBackgroundImageStore.shared.fileURL(for: conversationKey))
                        .overlay(alignment: .bottomTrailing) { Image(systemName: "checkmark.circle.fill").font(.system(size: 9)).foregroundStyle(.green) }
                }
                Button(role: .destructive) {
                    ChatBackgroundImageStore.shared.remove(for: conversationKey)
                    selection = .default
                } label: {
                    Label(String(localized: "chat.background.remove_image", comment: "Remove the custom chat background image"), systemImage: "trash")
                }
            }
        } label: {
            Label {
                Text(String(localized: "chat.background.title", comment: "Menu title for choosing a chat conversation background"))
            } icon: {
                if selection == .image {
                    ChatBackgroundMenuThumbnail(url: ChatBackgroundImageStore.shared.fileURL(for: conversationKey))
                        .overlay(alignment: .bottomTrailing) { Image(systemName: "checkmark.circle.fill").font(.system(size: 9)).foregroundStyle(.green) }
                } else {
                    ChatBackgroundSwatch(option: selection)
                }
            }
        }
        .onChange(of: selection) { option in ChatBackgroundStore.shared.set(option, for: conversationKey) }
        .task(id: pickedPhoto) {
            guard let pickedPhoto, let data = try? await pickedPhoto.loadTransferable(type: Data.self),
                  (try? ChatBackgroundImageStore.shared.save(data, for: conversationKey)) != nil else { return }
            selection = .image
        }
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
        case .image: String(localized: "chat.background.image", comment: "Custom image chat background")
        }
    }

    var swatch: Color {
        switch self {
        case .default: Color(red: 0.28, green: 0.30, blue: 0.40)
        case .dusk: Color(red: 0.36, green: 0.21, blue: 0.39)
        case .ocean: Color(red: 0.12, green: 0.34, blue: 0.48)
        case .forest: Color(red: 0.17, green: 0.36, blue: 0.28)
        case .oled: .black
        case .image: Color.purple
        }
    }
}
