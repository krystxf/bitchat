import SwiftUI
import PhotosUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

/// A small preview of the conversation's background photo.
struct ChatBackgroundMenuThumbnail: View {
    let url: URL
    @State private var image: Image?
    @State private var revision = 0
    var body: some View {
        Group {
            if let image { image.resizable().scaledToFill() }
            else { Image(systemName: "photo") }
        }
        .frame(width: 16, height: 16).clipShape(RoundedRectangle(cornerRadius: 3))
        .task(id: ChatBackgroundImageLoadID(url: url, revision: revision)) {
            image = await Task.detached(priority: .utility) { ChatBackgroundRasterCache.shared.image(at: url) }.value
        }
        .onReceive(NotificationCenter.default.publisher(for: .chatBackgroundImageDidChange)) { _ in
            revision &+= 1
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
    /// A PhotosPicker placed inside a Menu never presents on macOS (and is
    /// unreliable on iOS), so the menu item only raises this flag and the
    /// picker hangs off the menu itself, like the composer's image button.
    @State private var showsPhotoPicker = false

    var body: some View {
        Menu {
            Picker(String(localized: "chat.background.title", comment: "Menu title for choosing a chat conversation background"), selection: $selection) {
                ForEach(ChatBackgroundOption.allCases.filter { $0 != .image }) { option in
                    Text(option.label).tag(option)
                }
            }
            Button {
                showsPhotoPicker = true
            } label: {
                Label(String(localized: "chat.background.choose_image", comment: "Choose a local chat background photo"), systemImage: "photo")
            }
            #if os(macOS)
            Button {
                presentImageOpenPanel()
            } label: {
                Label(String(localized: "content.menu.choose_file", comment: "Menu option to choose an image file"), systemImage: "folder")
            }
            #endif
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
        .photosPicker(isPresented: $showsPhotoPicker, selection: $pickedPhoto, matching: .images)
        .onChange(of: selection) { option in ChatBackgroundStore.shared.set(option, for: conversationKey) }
        .task(id: pickedPhoto) {
            guard let item = pickedPhoto else { return }
            // Cleared so picking the same photo again runs this task again.
            defer { pickedPhoto = nil }
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
            useImage(data)
        }
    }

    /// Saves the image for this conversation and selects it. When the
    /// conversation already shows an image, the selection stays the same and
    /// the store's change notification redraws it.
    private func useImage(_ data: Data) {
        guard (try? ChatBackgroundImageStore.shared.save(data, for: conversationKey)) != nil else { return }
        if selection == .image {
            ChatBackgroundStore.shared.set(.image, for: conversationKey)
        } else {
            selection = .image
        }
    }

    #if os(macOS)
    private func presentImageOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
            Task { @MainActor in useImage(data) }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(panel.runModal())
        }
    }
    #endif
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
