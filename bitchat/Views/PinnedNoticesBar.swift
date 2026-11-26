import SwiftUI

struct PinnedNoticesBar: View {
    let posts: [BoardPostPacket]
    let geoScope: String?
    let nearbyNoteCount: Int
    let openNotices: () -> Void

    @EnvironmentObject private var appChromeModel: AppChromeModel
    @EnvironmentObject private var boardAlertsModel: BoardAlertsModel
    @ThemedPalette private var palette

    private var relevantPosts: [BoardPostPacket] {
        PinnedNoticesBarState.relevantPosts(posts, geoScope: geoScope)
    }

    private var unseenCount: Int {
        PinnedNoticesBarState.unseenCount(boardAlertsModel.unseenPostScopes, geoScope: geoScope)
    }

    private var previewPost: BoardPostPacket? {
        PinnedNoticesBarState.previewPost(posts, unseenScopes: boardAlertsModel.unseenPostScopes, geoScope: geoScope)
    }

    var body: some View {
        if !relevantPosts.isEmpty || nearbyNoteCount > 0 {
            Button(action: openNotices) {
                ChatBanner(
                    systemImage: "pin.fill",
                    symbolColor: unseenCount > 0 ? Color.novaHighlight : palette.secondary,
                    showsChevron: true
                ) {
                    HStack(spacing: 6) {
                        Text(verbatim: noticeCount > 1 ? "\(Strings.notices) · \(noticeCount)" : Strings.notices)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.primary)
                        if unseenCount > 0 {
                            Circle()
                                .fill(Color.novaHighlight)
                                .frame(width: 8, height: 8)
                        }
                    }
                    Text(verbatim: previewPost?.content ?? Strings.locationNotes)
                        .font(.footnote)
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Strings.notices): \(previewPost?.content ?? Strings.locationNotes)")
            .accessibilityHint(String(localized: "content.header.notices", comment: "Hint for opening notices"))
            .accessibilityValue(unseenCount > 0 ? String(format: String(localized: "content.accessibility.notices_new", comment: "Unseen notice count"), unseenCount) : "")
        }
    }

    private var noticeCount: Int { relevantPosts.count + nearbyNoteCount }

    private enum Strings {
        static let notices = String(localized: "content.accessibility.notices", comment: "Label for pinned notices")
        static let locationNotes = String(localized: "app_info.location.notes.title", comment: "Preview for location notes")
    }
}
