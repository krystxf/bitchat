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
                HStack(spacing: 10) {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(unseenCount > 0 ? Color.orange : palette.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(noticeCount > 1
                             ? "\(String(localized: "content.accessibility.notices", comment: "Label for pinned notices").lowercased()) · \(noticeCount)"
                             : String(localized: "content.accessibility.notices", comment: "Label for pinned notices").lowercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.primary)
                        Text(previewPost?.content ?? String(localized: "app_info.location.notes.title", comment: "Preview for location notes"))
                            .font(.caption)
                            .foregroundStyle(palette.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if unseenCount > 0 {
                        Circle()
                            .fill(.orange)
                            .frame(width: 7, height: 7)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface(in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(String(localized: "content.accessibility.notices", comment: "Accessibility label for notices")): \(previewPost?.content ?? String(localized: "app_info.location.notes.title", comment: "Preview for location notes"))")
            .accessibilityHint(String(localized: "content.header.notices", comment: "Hint for opening notices"))
            .accessibilityValue(unseenCount > 0 ? String(format: String(localized: "content.accessibility.notices_new", comment: "Unseen notice count"), unseenCount) : "")
        }
    }

    private var noticeCount: Int { relevantPosts.count + nearbyNoteCount }
}
