import SwiftUI
import CoreLocation
#if os(iOS)
import UIKit
#else
import AppKit
#endif
struct LocationChannelsSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var locationChannelsModel: LocationChannelsModel
    @EnvironmentObject private var peerListModel: PeerListModel
    @ThemedPalette private var palette
    @State private var customGeohash: String = ""
    @State private var customError: String? = nil
    /// Geohash waiting on the fine-precision OpSec confirmation before share.
    @State private var pendingShareGeohash: String?
    @State private var showSharePrecisionWarning = false
    @State private var activeSharePayload: ChannelSharePayload?
    @State private var showGlobePicker = false
    /// Geohash chosen on the globe; applied once the picker has dismissed.
    @State private var pickedGeohash: String?

    private enum Strings {
        static let title: LocalizedStringKey = "location_channels.title"
        static let description: LocalizedStringKey = "location_channels.description"
        static let requestPermissions: LocalizedStringKey = "location_channels.action.request_permissions"
        static let permissionDenied: LocalizedStringKey = "location_channels.permission_denied"
        static let openSettings: LocalizedStringKey = "location_channels.action.open_settings"
        static let loadingNearby: LocalizedStringKey = "location_channels.loading_nearby"
        static let grantToFind: LocalizedStringKey = "location_channels.grant_to_find"
        static let teleport: LocalizedStringKey = "location_channels.action.teleport"
        static let bookmarked: LocalizedStringKey = "location_channels.bookmarked_section_title"
        // Same string the settings pane shows under the tor toggle — the
        // warning belongs wherever the exposure is about to happen.
        static let torOffWarning = String(localized: "app_info.settings.tor.off_warning", defaultValue: "Tor is off: every relay you connect to can see your IP address, including relays carrying your private messages.", comment: "Warning shown under the tor toggle while tor is switched off, stating that relay operators can see the device IP address")

        static let quickJoinTitle = String(localized: "location_channels.quick_join.title", defaultValue: "Quick Join", comment: "Section header in the location channels sheet for the one-tap suggestion of the region channel derived from the device region")
        static func quickJoinDescription(_ regionName: String) -> String {
            String(
                format: String(localized: "location_channels.quick_join.description", defaultValue: "The region channel where people from %@ tend to gather — the wide cell around the main population center, not your location. It's public and well-known, so assume it's watched: quick join saves typing a geohash; it doesn't hide you or bypass blocks.", comment: "Caption under the quick join row; %@ is the localized country/region name. States plainly that the cell is the main population center's (not the person's location), that the channel must be assumed watched, and that quick join is discovery, not circumvention"),
                locale: .current,
                regionName
            )
        }
        static func quickJoinLabel(_ regionName: String) -> String {
            String(
                format: String(localized: "location_channels.quick_join.join_label", defaultValue: "Join the %@ region channel", comment: "Accessibility label for the quick join row; %@ is the localized country/region name"),
                locale: .current,
                regionName
            )
        }

        static let invalidGeohash = String(localized: "location_channels.error.invalid_geohash", comment: "Error shown when a custom geohash is invalid")
        static let switchChannelHint = String(localized: "location_channels.accessibility.switch_hint", comment: "Accessibility hint on a channel row explaining activation switches to it")
        static let addBookmark = String(localized: "location_channels.accessibility.add_bookmark", comment: "Accessibility action name for bookmarking a channel")
        static let removeBookmark = String(localized: "location_channels.accessibility.remove_bookmark", comment: "Accessibility action name for removing a channel bookmark")
        static let shareChannel = String(localized: "channel.share.action", defaultValue: "Share Channel", comment: "Context-menu / accessibility action that shares a location-channel invite")
        static let sharePrecisionTitle = String(localized: "channel.share.precision_warning.title", defaultValue: "Share a Precise Location Channel?", comment: "Title of the confirmation before sharing a neighborhood-or-finer geohash invite")
        static let sharePrecisionMessage = String(localized: "channel.share.precision_warning.message", defaultValue: "This Channel Covers a Small Area. An Invite Sent Over Sms or Imessage Is Visible to the Carrier and Both Handsets — It Discloses Interest in That Place, Not Only That Someone Uses Bitchat.", comment: "Body of the confirmation before sharing a fine-precision geohash invite")
        static let shareAnyway = String(localized: "channel.share.precision_warning.confirm", defaultValue: "Share Anyway", comment: "Confirms sharing a fine-precision location channel after the OpSec warning")
        static let openMap = String(localized: "location_channels.accessibility.open_map", defaultValue: "Open Map", comment: "Accessibility label for the button that opens the globe geohash picker")

        static func meshTitle(_ count: Int) -> String {
            let label = String(localized: "location_channels.mesh_label", comment: "Label for the mesh channel row")
            return rowTitle(label: label, count: count)
        }

        static func levelTitle(for level: GeohashChannelLevel, count: Int) -> String {
            // High-precision uncertainty: if count is 0 for high-precision levels,
            // show "?" because presence broadcasting is disabled for privacy.
            let isHighPrecision = (level == .neighborhood || level == .block || level == .building)
            if isHighPrecision && count == 0 {
                return String(
                    format: String(localized: "location_channels.row_title_unknown", defaultValue: "%@ [? people]"),
                    locale: .current,
                    level.displayName
                )
            }
            return rowTitle(label: level.displayName, count: count)
        }

        static func bookmarkTitle(geohash: String, count: Int) -> String {
            // Check precision for bookmarks too
            let len = geohash.count
            // Neighborhood=6, Block=7, Building=8+
            let isHighPrecision = (len >= 6)
            if isHighPrecision && count == 0 {
                return String(
                    format: String(localized: "location_channels.row_title_unknown", defaultValue: "%@ [? people]"),
                    locale: .current,
                    "#\(geohash)"
                )
            }
            return rowTitle(label: "#\(geohash)", count: count)
        }

        static func subtitlePrefix(geohash: String, coverage: String) -> String {
            String(
                format: String(localized: "location_channels.subtitle_prefix", comment: "Subtitle prefix showing geohash and coverage"),
                locale: .current,
                geohash, coverage
            )
        }

        static func subtitle(prefix: String, name: String?) -> String {
            guard let name, !name.isEmpty else { return prefix }
            return String(
                format: String(localized: "location_channels.subtitle_with_name", comment: "Subtitle combining prefix and resolved location name"),
                locale: .current,
                prefix, name
            )
        }

        private static func rowTitle(label: String, count: Int) -> String {
            String(
                format: String(localized: "location_channels.row_title", comment: "List row title with participant count"),
                locale: .current,
                label, count
            )
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { _ in
          List {
            Section {
                switch locationChannelsModel.permissionState {
                case .notDetermined:
                    Button {
                        locationChannelsModel.enableLocationChannels()
                    } label: {
                        Label(Strings.requestPermissions, systemImage: "location.fill")
                    }
                case .denied, .restricted:
                    Label {
                        Text(Strings.permissionDenied)
                    } icon: {
                        Image(systemName: "location.slash.fill")
                    }
                    .foregroundStyle(.novaSecondaryText)
                    Button(Strings.openSettings, action: SystemSettings.location.open)
                case .authorized:
                    EmptyView()
                }

                if !locationChannelsModel.userTorEnabled {
                    Label {
                        Text(verbatim: Strings.torOffWarning)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.footnote)
                    .foregroundStyle(palette.alertRed)
                }
            } header: {
                // The explanation leads the sheet, as a page's intro text
                // in Settings, not inside a row.
                Text(Strings.description)
                    .font(.footnote)
                    .foregroundStyle(.novaSecondaryText)
                    .textCase(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
            }
            .novaRows()

            channelListContent
                .novaRows()
          }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .novaGroupedList()
        .sheetChrome(title: Text(Strings.title), onClose: { isPresented = false })
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #else
        // Picking a channel fits in half the screen, as in Maps; drag up
        // for the full list.
        .presentationDetents([.medium, .large])
        #endif
        .onAppear {
            // Refresh channels when opening
            if locationChannelsModel.permissionState == .authorized {
                locationChannelsModel.refreshChannels()
            }
            // Begin periodic refresh while sheet is open
            locationChannelsModel.beginLiveRefresh()
            // Geohash sampling is now managed by ChatViewModel globally
        }
        .onDisappear {
            locationChannelsModel.endLiveRefresh()
        }
        .onChange(of: locationChannelsModel.permissionState) { newValue in
            if newValue == .authorized {
                locationChannelsModel.refreshChannels()
            }
        }
        .onChange(of: locationChannelsModel.availableChannels) { _ in }
        .confirmationDialog(
            Strings.sharePrecisionTitle,
            isPresented: $showSharePrecisionWarning,
            titleVisibility: .visible
        ) {
            Button(Strings.shareAnyway) {
                if let gh = pendingShareGeohash {
                    presentShare(forGeohash: gh)
                }
                pendingShareGeohash = nil
            }
            Button("common.cancel", role: .cancel) {
                pendingShareGeohash = nil
            }
        } message: {
            Text(Strings.sharePrecisionMessage)
        }
        .sheet(item: $activeSharePayload) { payload in
            ShareActivityView(text: payload.text)
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showGlobePicker, onDismiss: applyPickedGeohash) {
            globePicker
        }
        #else
        .sheet(isPresented: $showGlobePicker, onDismiss: applyPickedGeohash) {
            globePicker
        }
        #endif
    }

    /// Opens on the typed geohash, else the current location channel; the picker
    /// itself falls back to the coarsest nearby channel.
    private var globePicker: some View {
        let typed = customGeohash.trimmed.lowercased().replacingOccurrences(of: "#", with: "")
        let initial: String
        if !typed.isEmpty {
            initial = typed
        } else if case .location(let channel) = locationChannelsModel.selectedChannel {
            initial = channel.geohash
        } else {
            initial = ""
        }
        return GeohashPickerView(
            initialGeohash: initial,
            nearbyGeohashes: locationChannelsModel.availableChannels.map(\.geohash),
            clusters: locationChannelsModel.availableChannels.map {
                GeohashMapCluster(geohash: $0.geohash, peopleCount: peerListModel.participantCount(for: $0.geohash))
            },
            onSelect: { geohash in
                pickedGeohash = geohash
                showGlobePicker = false
            },
            onCancel: { showGlobePicker = false }
        )
    }

    private func applyPickedGeohash() {
        guard let geohash = pickedGeohash else { return }
        pickedGeohash = nil
        guard validateGeohash(geohash) else { return }
        customError = nil
        locationChannelsModel.teleport(to: geohash)
        isPresented = false
    }

    private func requestShare(forGeohash geohash: String) {
        if ChannelShare.shouldWarn(forGeohash: geohash) {
            pendingShareGeohash = geohash
            showSharePrecisionWarning = true
        } else {
            presentShare(forGeohash: geohash)
        }
    }

    private func presentShare(forGeohash geohash: String) {
        activeSharePayload = ChannelSharePayload(text: ChannelShare.payload(forGeohash: geohash))
    }

    /// Participant counts change as peers arrive and age out. Refresh them
    /// periodically while keeping the system List row layout.
    @ViewBuilder
    private var channelListContent: some View {
            Section {
                channelRow(
                    title: Strings.meshTitle(peerListModel.reachableMeshPeerCount),
                    subtitlePrefix: Strings.subtitlePrefix(geohash: "bluetooth", coverage: bluetoothRangeString()),
                    isSelected: isMeshSelected,
                    icon: "antenna.radiowaves.left.and.right",
                    tileColor: ChannelTitle.meshAvatarColor
                ) {
                    locationChannelsModel.select(ChannelID.mesh)
                    isPresented = false
                }
            }

            Section {
                let nearby = locationChannelsModel.availableChannels.filter { $0.level != .building }
                if !nearby.isEmpty {
                    ForEach(nearby) { channel in
                        let name = locationName(for: channel.level).map { formattedNamePrefix(for: channel.level) + $0 }
                        let count = peerListModel.participantCount(for: channel.geohash)
                        channelRow(
                            title: Strings.levelTitle(for: channel.level, count: count),
                            subtitlePrefix: Strings.subtitlePrefix(geohash: channel.geohash, coverage: coverageString(forPrecision: channel.geohash.count)),
                            subtitleName: name,
                            isSelected: isSelected(channel),
                            icon: iconName(for: channel.level),
                            trailingAccessory: {
                                bookmarkButton(for: channel.geohash)
                            },
                            accessoryActionTitle: locationChannelsModel.isBookmarked(channel.geohash) ? Strings.removeBookmark : Strings.addBookmark,
                            accessoryAction: { locationChannelsModel.toggleBookmark(channel.geohash) },
                            shareGeohash: channel.geohash,
                            onShare: { requestShare(forGeohash: channel.geohash) }
                        ) {
                            locationChannelsModel.markTeleported(for: channel.geohash, false)
                            locationChannelsModel.select(ChannelID.location(channel))
                            isPresented = false
                        }
                        .contextMenu {
                            Button { requestShare(forGeohash: channel.geohash) } label: {
                                Label(Strings.shareChannel, systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                } else if locationChannelsModel.permissionState == .authorized {
                    Label {
                        Text(Strings.loadingNearby)
                    } icon: {
                        ProgressView()
                    }
                    .foregroundStyle(.novaSecondaryText)
                } else {
                    Text(Strings.grantToFind)
                        .font(.subheadline)
                        .foregroundStyle(.novaSecondaryText)
                }
            }

            customTeleportSection

            if QuickJoinSuggestion.current() != nil {
                quickJoinSection
            }

            let bookmarks = locationChannelsModel.bookmarks
            if !bookmarks.isEmpty {
                Section {
                    bookmarkedRows(bookmarks)
                } header: {
                    Text(Strings.bookmarked)
                        .foregroundColor(.novaSecondaryText)
                }
            }
    }

    /// Teleport to a typed geohash, or pick one on the map: the field with
    /// the map button beside it, then the teleport action.
    private var customTeleportSection: some View {
        let normalized = customGeohash
            .trimmed
            .lowercased()
            .replacingOccurrences(of: "#", with: "")
        let isValid = validateGeohash(normalized)
        return Section {
            HStack(spacing: 8) {
                Text(verbatim: "#")
                    .foregroundStyle(.novaSecondaryText)
                TextField("geohash", text: $customGeohash)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.asciiCapable)
                    #endif
                    .textFieldStyle(.plain)
                    .onSubmit {
                        guard isValid else { return }
                        locationChannelsModel.teleport(to: normalized)
                        isPresented = false
                    }
                    .onChange(of: customGeohash) { newValue in
                        let allowed = Set("0123456789bcdefghjkmnpqrstuvwxyz")
                        let filtered = newValue
                            .lowercased()
                            .replacingOccurrences(of: "#", with: "")
                            .filter { allowed.contains($0) }
                        if filtered.count > 12 {
                            customGeohash = String(filtered.prefix(12))
                        } else if filtered != newValue {
                            customGeohash = filtered
                        }
                    }
                Button(action: { showGlobePicker = true }) {
                    Image(systemName: "map")
                        .frame(minWidth: 32, minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Strings.openMap)
                .help(Strings.openMap)
            }
            Button(action: {
                guard isValid else { customError = Strings.invalidGeohash; return }
                locationChannelsModel.teleport(to: normalized)
                isPresented = false
            }) {
                Label(Strings.teleport, systemImage: "location.north.circle")
                    // A row action in the accent; gray until the geohash
                    // is valid.
                    .foregroundStyle(isValid ? Color.novaAccent : Color.novaSecondaryText)
            }
            .disabled(!isValid)
        } footer: {
            if let err = customError {
                Text(err)
                    .foregroundStyle(palette.alertRed)
            }
        }
    }

    /// One tap into the region channel around the device region's main
    /// population center — derived from the locale, no location access, no
    /// roster (see QuickJoinSuggestion). The footer is deliberately blunt
    /// that the cell is public and watched: discovery, not circumvention.
    @ViewBuilder
    private var quickJoinSection: some View {
        if let suggestion = QuickJoinSuggestion.current() {
            Section {
                Button(action: {
                    locationChannelsModel.teleport(to: suggestion.geohash)
                    isPresented = false
                }) {
                    HStack(spacing: 12) {
                        Text(verbatim: suggestion.flag)
                            .font(.title2)
                            .frame(width: 32)
                        Text(verbatim: suggestion.localizedName)
                            // Color.primary: inside a button, .primary
                            // takes the tint.
                            .foregroundStyle(Color.primary)
                        Spacer(minLength: 8)
                        Text(verbatim: "#\(suggestion.geohash)")
                            .font(.subheadline)
                            .foregroundStyle(.novaSecondaryText)
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(Strings.quickJoinLabel(suggestion.localizedName))
                .accessibilityHint(Strings.switchChannelHint)
            } header: {
                Text(Strings.quickJoinTitle)
                    .foregroundColor(.novaSecondaryText)
            } footer: {
                Text(Strings.quickJoinDescription(suggestion.localizedName))
                    .novaSectionText()
            }
        }
    }

    @ViewBuilder
    private func bookmarkedRows(_ entries: [String]) -> some View {
        ForEach(entries, id: \.self) { gh in
            let level = levelForLength(gh.count)
            let channel = GeohashChannel(level: level, geohash: gh)
            let coverage = coverageString(forPrecision: gh.count)
            let subtitle = Strings.subtitlePrefix(geohash: gh, coverage: coverage)
            let name = locationChannelsModel.bookmarkNames[gh]
            let participantCount = peerListModel.participantCount(for: gh)
            channelRow(
                title: Strings.bookmarkTitle(geohash: gh, count: participantCount),
                subtitlePrefix: subtitle,
                subtitleName: name.map { formattedNamePrefix(for: level) + $0 },
                isSelected: locationChannelsModel.isSelected(channel),
                icon: iconName(for: level),
                trailingAccessory: {
                    bookmarkButton(for: gh)
                },
                accessoryActionTitle: locationChannelsModel.isBookmarked(gh) ? Strings.removeBookmark : Strings.addBookmark,
                accessoryAction: { locationChannelsModel.toggleBookmark(gh) },
                shareGeohash: gh,
                onShare: { requestShare(forGeohash: gh) }
            ) {
                let inRegional = locationChannelsModel.availableChannels.contains { $0.geohash == gh }
                if !inRegional && !locationChannelsModel.availableChannels.isEmpty {
                    locationChannelsModel.markTeleported(for: gh, true)
                } else {
                    locationChannelsModel.markTeleported(for: gh, false)
                }
                locationChannelsModel.select(ChannelID.location(channel))
                isPresented = false
            }
            .contextMenu {
                Button {
                    requestShare(forGeohash: gh)
                } label: {
                    Label(Strings.shareChannel, systemImage: "square.and.arrow.up")
                }
            }
            .onAppear { locationChannelsModel.resolveBookmarkNameIfNeeded(for: gh) }
        }
    }

    private func isSelected(_ channel: GeohashChannel) -> Bool {
        locationChannelsModel.isSelected(channel)
    }

    private var isMeshSelected: Bool {
        if case .mesh = locationChannelsModel.selectedChannel { return true }
        return false
    }

    private func channelRow(
        title: String,
        subtitlePrefix: String,
        subtitleName: String? = nil,
        isSelected: Bool,
        icon: String,
        tileColor: AvatarIdentity.RGB = ChannelTitle.locationAvatarColor,
        @ViewBuilder trailingAccessory: () -> some View = { EmptyView() },
        accessoryActionTitle: String? = nil,
        accessoryAction: (() -> Void)? = nil,
        shareGeohash: String? = nil,
        onShare: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let parts = splitTitleAndCount(title)
        return HStack(spacing: 4) {
            Button(action: action) {
                HStack(spacing: 12) {
                    // The channel's glyph on the tile its info page shows.
                    ConversationGlyphAvatar(systemImage: icon, color: tileColor, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(parts.base)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(Strings.subtitle(prefix: subtitlePrefix, name: subtitleName))
                            .font(.footnote)
                            .foregroundStyle(.novaSecondaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 4)
                    if let count = parts.countSuffix, !count.isEmpty {
                        Text(count)
                            .font(.subheadline)
                            .foregroundStyle(.novaSecondaryText)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.novaAccent)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: "\(title), \(Strings.subtitle(prefix: subtitlePrefix, name: subtitleName))"))
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityHint(Strings.switchChannelHint)
            .accessibilityAction(.default, action)
            .accessibilityActions {
                if let accessoryActionTitle, let accessoryAction {
                    Button(accessoryActionTitle, action: accessoryAction)
                }
                if shareGeohash != nil, let onShare {
                    Button(Strings.shareChannel, action: onShare)
                }
            }
            trailingAccessory()
        }
    }

    private func bookmarkButton(for geohash: String) -> some View {
        Button {
            locationChannelsModel.toggleBookmark(geohash)
        } label: {
            Image(systemName: locationChannelsModel.isBookmarked(geohash) ? "bookmark.fill" : "bookmark")
                .foregroundStyle(.novaAccent)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(locationChannelsModel.isBookmarked(geohash) ? Strings.removeBookmark : Strings.addBookmark)
    }

    private func iconName(for level: GeohashChannelLevel) -> String {
        switch level {
        case .block, .building: "mappin.and.ellipse"
        case .neighborhood: "house"
        case .city: "building.2"
        case .province: "map"
        case .region: "globe.americas"
        }
    }

    /// Splits a title like "Mesh [3 people]" into the name and the
    /// count, "3 people", which the row shows at its trailing edge.
    private func splitTitleAndCount(_ s: String) -> (base: String, countSuffix: String?) {
        guard let idx = s.lastIndex(of: "[") else { return (s, nil) }
        let prefix = String(s[..<idx]).trimmed
        let suffix = String(s[idx...])
            .trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        return (prefix, suffix)
    }
    private func validateGeohash(_ s: String) -> Bool {
        let allowed = Set("0123456789bcdefghjkmnpqrstuvwxyz")
        guard !s.isEmpty, s.count <= 12 else { return false }
        return s.allSatisfy { allowed.contains($0) }
    }

    private func levelForLength(_ len: Int) -> GeohashChannelLevel {
        switch len {
        case 0...2: return .region
        case 3...4: return .province
        case 5: return .city
        case 6: return .neighborhood
        case 7: return .block
        case 8: return .building
        default: return .block
        }
    }
}

// MARK: - Coverage helpers
extension LocationChannelsSheet {
    private func coverageString(forPrecision len: Int) -> String {
        GeohashCoverage.string(forPrecision: len)
    }

    private func bluetoothRangeString() -> String {
        // Approximate Bluetooth LE range for typical mobile devices; environment dependent
        GeohashCoverage.usesMetric() ? "~10–50 m" : "~30–160 ft"
    }

    private func locationName(for level: GeohashChannelLevel) -> String? {
        locationChannelsModel.locationName(for: level)
    }

    private func formattedNamePrefix(for level: GeohashChannelLevel) -> String {
        switch level {
        case .region:
            return ""
        case .building, .block, .neighborhood, .city, .province:
            return "~"
        }
    }
}
