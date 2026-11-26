//
// EmojiPickerView.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// The full reaction picker: every emoji in Unicode, Frequently Used on
/// top, Unicode's categories with a bar to jump between them, search by
/// name and keyword, and skin tones on a long press (iOS) or a secondary
/// click (macOS). My current reactions are marked; choosing one of them
/// takes it back, as a pill does.
///
/// iOS shows it in a sheet with the shared sheet chrome; macOS in a
/// popover anchored to the button that opened it.
struct EmojiPickerView: View {
    let selected: Set<String>
    let tint: MessageBubbleColor
    let onSelect: (String) -> Void
    /// Closes the sheet (iOS).
    var onClose: () -> Void = {}

    @ObservedObject private var preferences = ReactionEmojiPreferences.shared
    @State private var query = ""
    @State private var currentSection = EmojiPickerSection.frequent
    #if os(iOS)
    @State private var isKeyboardActive = false
    #else
    @FocusState private var isSearchFocused: Bool
    @Environment(\.dismiss) private var dismiss
    #endif

    private let catalog = EmojiCatalog.shared

    var body: some View {
        #if os(iOS)
        grid
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("emoji.picker.search", comment: "Placeholder of the emoji search field")
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if query.isEmpty {
                    categoryBar
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .reactionGlassSurface(in: Capsule())
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
            // The system emoji keyboard, as an extra way to pick.
            .background {
                EmojiKeyboardInput(isActive: $isKeyboardActive) { emoji in
                    onSelect(emoji)
                }
                .frame(width: 1, height: 1)
                .opacity(0.01)
            }
            .sheetChrome(
                title: Text("content.reaction.add", comment: "Menu item or title for adding a reaction to a message"),
                onClose: onClose,
                trailing: {
                    Button {
                        isKeyboardActive = true
                    } label: {
                        Label(String(localized: "emoji.picker.keyboard", comment: "Button that opens the system emoji keyboard to pick a reaction"), systemImage: "keyboard")
                    }
                }
            )
        #else
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                searchField
                characterViewerButton
            }
            .padding([.horizontal, .top], 10)
            .padding(.bottom, 6)
            if query.isEmpty {
                categoryBar
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
            }
            Divider()
            grid
        }
        .frame(width: 352, height: 420)
        .onAppear { isSearchFocused = true }
        #endif
    }

    // MARK: Grid

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: EmojiGridCell.side, maximum: EmojiGridCell.side + 6), spacing: 2)],
                    spacing: 2,
                    pinnedViews: [.sectionHeaders]
                ) {
                    if query.isEmpty {
                        section(.frequent, title: String(localized: "emoji.picker.frequent", comment: "Title of the recently and often used emoji in the reaction picker")) {
                            ForEach(preferences.frequentWithDefaults, id: \.self) { emoji in
                                cell(emoji: emoji, entry: catalog.entry(for: emoji))
                            }
                        }
                        ForEach(catalog.groups) { group in
                            section(.group(group.kind), title: group.kind.title) {
                                ForEach(group.entries) { entry in
                                    cell(emoji: preferences.preferredVariant(of: entry), entry: entry)
                                }
                            }
                        }
                    } else {
                        let results = catalog.search(query)
                        if results.isEmpty {
                            Text("emoji.picker.no_results", comment: "Shown when an emoji search finds nothing")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                                .gridCellColumns(8)
                        } else {
                            ForEach(results) { entry in
                                cell(emoji: preferences.preferredVariant(of: entry), entry: entry)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: currentSection) { section in
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(section.id, anchor: .top)
                }
            }
        }
    }

    private func section<Content: View>(_ id: EmojiPickerSection, title: String, @ViewBuilder content: () -> Content) -> some View {
        Section {
            content()
        } header: {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .background(.bar)
                .id(id.id)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func cell(emoji: String, entry: EmojiCatalog.Entry?) -> some View {
        EmojiGridCell(
            emoji: emoji,
            variants: entry.map { $0.skinTones.isEmpty ? [] : [$0.emoji] + $0.skinTones } ?? [],
            isSelected: selected.contains(emoji),
            tint: tint,
            onSelect: { choose(emoji, base: entry?.emoji) }
        ) { variant in
            choose(variant, base: entry?.emoji)
        }
    }

    private func choose(_ emoji: String, base: String?) {
        if let base, let entry = catalog.entry(for: base), !entry.skinTones.isEmpty {
            preferences.rememberVariant(emoji, for: base)
        }
        onSelect(emoji)
    }

    // MARK: Category bar

    private var categoryBar: some View {
        HStack(spacing: 0) {
            categoryButton(.frequent, systemImage: "clock", title: String(localized: "emoji.picker.frequent", comment: "Title of the recently and often used emoji in the reaction picker"))
            ForEach(catalog.groups) { group in
                categoryButton(.group(group.kind), systemImage: group.kind.systemImage, title: group.kind.title)
            }
        }
    }

    private func categoryButton(_ section: EmojiPickerSection, systemImage: String, title: String) -> some View {
        let isCurrent = currentSection == section
        return Button {
            currentSection = section
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? tint.color : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: macOS search

    #if os(macOS)
    /// Opens the system Character Viewer; its first emoji is the pick.
    private var characterViewerButton: some View {
        Button {
            dismiss()
            // Once the popover is gone, so the chat window takes the focus.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                CharacterViewerBridge.shared.request { emoji in onSelect(emoji) }
            }
        } label: {
            Image(systemName: "globe")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(String(localized: "emoji.picker.character_viewer", comment: "Button that opens the system Emoji & Symbols viewer to pick a reaction"))
        .accessibilityLabel(String(localized: "emoji.picker.character_viewer", comment: "Button that opens the system Emoji & Symbols viewer to pick a reaction"))
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(String(localized: "emoji.picker.search", comment: "Placeholder of the emoji search field"), text: $query)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit {
                    if let first = catalog.search(query).first {
                        choose(preferences.preferredVariant(of: first), base: first.emoji)
                    }
                }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("common.close", comment: "Accessibility label for close buttons"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
    #endif
}

/// Where the picker's category bar jumps to.
enum EmojiPickerSection: Hashable {
    case frequent
    case group(EmojiGroup)

    var id: String {
        switch self {
        case .frequent: "frequent"
        case .group(let group): group.rawValue
        }
    }
}

/// One emoji in the picker grid. A tap chooses it. An emoji with skin
/// tones offers them in a menu: a long press on iOS, a secondary click or
/// a press and hold on macOS.
struct EmojiGridCell: View {
    static let side: CGFloat = 40

    let emoji: String
    /// The base emoji and its five skin tones, or empty.
    let variants: [String]
    let isSelected: Bool
    let tint: MessageBubbleColor
    let onSelect: () -> Void
    let onChooseVariant: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    @State private var showsVariants = false

    var body: some View {
        content
            .contextMenu {
                if !variants.isEmpty {
                    SkinToneMenuRow(variants: variants, tint: tint, onSelect: onChooseVariant)
                }
            }
            .accessibilityLabel(Text(verbatim: emoji))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        face
            .onTapGesture(perform: onSelect)
            .onLongPressGesture(minimumDuration: 0.4) {
                if !variants.isEmpty { showsVariants = true }
            }
            .onHover { isHovered = $0 }
            .accessibilityAction(.default, onSelect)
            .popover(isPresented: $showsVariants, arrowEdge: .top) {
                HStack(spacing: 2) {
                    ForEach(variants, id: \.self) { variant in
                        Button {
                            showsVariants = false
                            onChooseVariant(variant)
                        } label: {
                            EmojiGlyph(emoji: variant, side: 28)
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
            }
        #else
        Button(action: onSelect) { face }
            .buttonStyle(.plain)
        #endif
    }

    private var face: some View {
        EmojiGlyph(emoji: emoji, side: 30)
            .frame(width: Self.side, height: Self.side)
            .background {
                if isSelected {
                    Circle().fill(tint.color.opacity(colorScheme == .dark ? 0.55 : 0.22))
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.08))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                // The small corner mark the system keyboard uses for an
                // emoji with skin tones.
                if !variants.isEmpty {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 4))
                        .rotationEffect(.degrees(135))
                        .foregroundStyle(.tertiary)
                        .padding(3)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
    }
}

/// An emoji drawn to fit a square, whatever its width: a flag, a keycap, a
/// family ZWJ sequence, or one this OS draws as several glyphs.
struct EmojiGlyph: View {
    let emoji: String
    let side: CGFloat

    var body: some View {
        Text(verbatim: emoji)
            .font(.system(size: side * 0.82))
            .lineLimit(1)
            .minimumScaleFactor(0.3)
            .frame(width: side, height: side)
    }
}

/// The skin tones of an emoji in its menu: a palette of round choices
/// (iOS 17, macOS), plain items before that.
struct SkinToneMenuRow: View {
    let variants: [String]
    let tint: MessageBubbleColor
    let onSelect: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            palette
        } else {
            ForEach(variants, id: \.self) { variant in
                Button(variant) { onSelect(variant) }
            }
        }
        #else
        palette
        #endif
    }

    @available(iOS 17.0, macOS 14.0, *)
    private var palette: some View {
        ControlGroup {
            ForEach(variants, id: \.self) { variant in
                Button {
                    onSelect(variant)
                } label: {
                    Label {
                        Text(verbatim: variant)
                    } icon: {
                        EmojiMenuImage.image(for: variant, isSelected: false, tint: tint, colorScheme: colorScheme)
                    }
                }
            }
        }
        .controlGroupStyle(.palette)
    }
}

extension View {
    /// Liquid Glass on OS 26 (interactive where `interactive` is set), a
    /// thick material before that.
    @ViewBuilder
    func reactionGlassSurface<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
        #else
        background(.regularMaterial, in: shape)
            .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        #endif
    }
}
