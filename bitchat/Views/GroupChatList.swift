import BitFoundation
import SwiftUI

/// The "groups" section of the people sheet: one row per private group this
/// device belongs to, tappable to open the group chat.
struct GroupChatList: View {
    @ThemedPalette private var palette

    let groups: [GroupChatRow]
    let onTapGroup: (PeerID) -> Void

    private enum Strings {
        static let header = String(localized: "groups.section.header", comment: "Section header above the private groups list")
        static let creator = String(localized: "groups.state.creator", comment: "State label for a group the user created")
        static let unread = String(localized: "mesh_peers.state.unread", comment: "State label for a peer with unread private messages")
        static let openGroupHint = String(localized: "groups.accessibility.open_group_hint", comment: "Accessibility hint on a group row explaining activation opens the group chat")
        static let memberCountFormat = String(localized: "groups.member_count %@", comment: "Member count shown next to a group name; placeholder is the count")
    }

    var body: some View {
        if !groups.isEmpty {
            Section {
                ForEach(groups) { group in
                    Button {
                        onTapGroup(group.peerID)
                    } label: {
                        PeopleRow(systemImage: "person.3.fill", iconColor: Color.accentColor) {
                            HStack(spacing: 4) {
                                hashtagText(for: group)
                                    .foregroundColor(palette.primary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Text(verbatim: memberCount(for: group))
                                    .foregroundColor(palette.secondary)
                                    .fixedSize()
                            }
                        } accessories: {
                            if group.isCreator {
                                Image(systemName: "crown.fill")
                                    .foregroundColor(.yellow)
                                    .help(Strings.creator)
                            }
                            if group.hasUnread {
                                PeopleUnreadIndicator()
                            }
                        }
                    }
                    .peopleRowButtonStyle()
                    .accessibilityLabel(accessibilityDescription(for: group))
                    .accessibilityHint(Strings.openGroupHint)
                }
            } header: {
                Text(verbatim: Strings.header)
            }
        }
    }

    private func memberCount(for group: GroupChatRow) -> String {
        String(format: Strings.memberCountFormat, locale: .current, "\(group.memberCount)")
    }

    /// "#name", not localized: there is nothing to translate, and a
    /// letterless "#%@" catalog key breaks string catalog symbol generation
    /// (SwiftPM's default build system). It renders as the localized lookup
    /// did: the name is isolated (the lookup isolates names containing
    /// right-to-left text; isolating every name renders the same), so the
    /// "#" stays on the same side of RTL names, and the text is tagged with
    /// the app language, as text from a localization table is.
    private func hashtagText(for group: GroupChatRow) -> Text {
        var hashtag = AttributedString("#\u{2068}\(group.name)\u{2069}")
        hashtag.languageIdentifier = Bundle.main.preferredLocalizations.first ?? "en"
        return Text(hashtag)
    }

    private func accessibilityDescription(for group: GroupChatRow) -> String {
        var parts: [String] = [group.name, memberCount(for: group)]
        if group.isCreator { parts.append(Strings.creator) }
        if group.hasUnread { parts.append(Strings.unread) }
        return parts.joined(separator: ", ")
    }
}
