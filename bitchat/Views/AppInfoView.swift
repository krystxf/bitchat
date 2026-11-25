import SwiftUI

/// The sheet behind the "bitchat/" logo: a segmented Settings/Info surface.
/// Settings gathers every user preference (language, voice, connectivity
/// toggles, panic wipe); Info keeps the about content (how-to, features,
/// privacy, symbols legend).
struct AppInfoView: View {
    @Environment(\.dismiss) var dismiss
    @ThemedPalette private var palette
    @EnvironmentObject private var locationChannelsModel: LocationChannelsModel
    @ObservedObject private var bridgeService = BridgeService.shared

    /// Supplies the mesh topology map data. Nil (previews, missing wiring)
    /// hides the topology row entirely.
    var topologyProvider: (@MainActor () -> MeshTopologyDisplayModel)?
    /// Wipes all local data. Nil (previews, missing wiring) hides the danger
    /// zone entirely.
    var onPanicWipe: (@MainActor () -> Void)?
    /// Edits the nickname, which the main title bar shows as its subtitle.
    /// Nil (previews, missing wiring) hides the row.
    var nickname: Binding<String>?
    /// Validates and saves the nickname when editing ends.
    var onNicknameCommit: (@MainActor () -> Void)?
    /// Lists everyone the user blocked. Nil (previews, missing wiring) hides
    /// the blocked accounts row.
    var blockedAccountsProvider: (@MainActor () -> [BlockedAccount])?
    /// Undoes one block from the blocked accounts list.
    var onUnblock: (@MainActor (BlockedAccount) -> Void)?

    @State private var showTopology = false
    @State private var showBlockedAccounts = false
    @FocusState private var isNicknameFocused: Bool
    @State private var liveVoiceEnabled = PTTSettings.liveVoiceEnabled
    @State private var locationNotesEnabled = LocationNotesSettings.enabled
    @State private var hideMessagePreviews = NotificationPrivacySettings.hideMessagePreviews
    @State private var autoRevealFavoriteImages = MediaRevealSettings.autoRevealFavorites
    @State private var customRelays = NostrRelaySettings.customRelays()
    @State private var relayInput = ""
    @State private var relayError: String?
    @ObservedObject private var locationManager = LocationChannelManager.shared
    /// Sticky across opens: first-ever open lands on Info (the gentler
    /// introduction), and afterwards the sheet reopens wherever it was left.
    @AppStorage("appInfo.selectedPane") private var selectedPane: Pane = .info
    @State private var showPanicConfirmation = false
    @AppStorage(AppLanguageSettings.overrideKey) private var languageOverride = ""
    /// The override changed this session; localization resolves at process
    /// start, so surface the restart hint.
    @State private var showLanguageRestartNote = false

    private enum Pane: String {
        case settings
        case info
    }

    // MARK: - Constants
    private enum Strings {
        static let appName: LocalizedStringKey = "app_info.app_name"
        static let tagline: LocalizedStringKey = "app_info.tagline"

        /// New keys carry their English copy inline (defaultValue) until the
        /// i18n pass lands them in the catalog; moved keys keep their homes.
        enum Settings {
            static let tabPickerLabel = String(localized: "app_info.tab.picker_label", defaultValue: "view", comment: "Accessibility label for the segmented control switching between the settings and info panes of the app info sheet")
            static let tabSettings = String(localized: "app_info.tab.settings", defaultValue: "settings", comment: "Segmented control label for the settings pane of the app info sheet")
            static let tabInfo = String(localized: "app_info.tab.info", defaultValue: "info", comment: "Segmented control label for the info pane of the app info sheet")

            static let connectivityTitle = String(localized: "app_info.settings.connectivity.title", defaultValue: "CONNECTIVITY", comment: "Section header (uppercase) for the connectivity toggles: mesh bridge, internet gateway, tor routing")

            static let languageTitle = String(localized: "app_info.settings.language.title", defaultValue: "LANGUAGE", comment: "Section header (uppercase) for the app language picker in settings")
            static let nicknameTitle = String(localized: "app_info.settings.nickname.title", defaultValue: "NICKNAME", comment: "Section header (uppercase) for the nickname field in settings")
            static let languagePickerLabel = String(localized: "app_info.settings.language.picker_label", defaultValue: "app language", comment: "Label of the app language picker row in settings")
            static let languageSystem = String(localized: "app_info.settings.language.system", defaultValue: "system default", comment: "Menu option that clears the in-app language override so the app follows the device language")
            static let languageRestartNote = String(localized: "app_info.settings.language.restart_note", defaultValue: "restart bitchat to apply the new language", comment: "Caption shown after the user picks a different app language; the change takes effect on next launch")

            static let bridgeTitle = String(localized: "app_info.settings.bridge.title", defaultValue: "mesh bridge", comment: "Title of the mesh bridge toggle in settings")
            static let bridgeSubtitle = String(localized: "app_info.settings.bridge.subtitle", defaultValue: "joins nearby mesh islands over the internet: what you say in the mesh channel also reaches people in your area beyond radio range, and their messages appear here marked with the network glyph. while you have internet, your device also carries bridge and location-channel traffic for phones around you that have none.", comment: "Subtitle explaining what the mesh bridge toggle does")
            static func bridgeCell(_ cell: String) -> String {
                String(
                    format: String(localized: "app_info.settings.bridge.cell", defaultValue: "rendezvous cell: %@", comment: "Caption under the mesh bridge toggle showing the geohash cell the bridge is meeting on"),
                    locale: .current,
                    cell
                )
            }
            static let bridgeNoCell = String(localized: "app_info.settings.bridge.no_cell", defaultValue: "no rendezvous cell yet — needs location access or a nearby bridge peer", comment: "Caption under the mesh bridge toggle when the bridge is on but has no geohash cell to meet on")

            // Moved from LocationChannelsSheet; keys unchanged. (The former
            // internet-gateway toggle is gone: the bridge switch drives all
            // internet sharing, including geohash-channel gatewaying.)
            static let torTitle: LocalizedStringKey = "location_channels.tor.title"
            // Replaces `location_channels.tor.subtitle`, which described the
            // setting as location-channels-only. It covers private messages and
            // relay-directory refreshes too, and said nothing about the cost of
            // switching it off.
            static let torSubtitle = String(localized: "app_info.settings.tor.subtitle", defaultValue: "sends internet traffic through tor, so relay operators see tor's address instead of yours. covers location channels and private messages delivered over the internet. recommended: on.", comment: "Subtitle for the tor routing toggle in settings, explaining what it covers")
            static let torOffWarning = String(localized: "app_info.settings.tor.off_warning", defaultValue: "tor is off: every relay you connect to can see your IP address, including relays carrying your private messages.", comment: "Warning shown under the tor toggle while tor is switched off, stating that relay operators can see the device IP address")

            static let relaysTitle = String(localized: "app_info.settings.relays.title", defaultValue: "private message relays", comment: "Title of the relay list editor in settings")
            static let relaysSubtitle = String(localized: "app_info.settings.relays.subtitle", defaultValue: "when the mesh can't reach someone, private messages travel through these relays. the built-in ones are well-known addresses that a network filter can block, so you can add your own — including .onion addresses.", comment: "Subtitle explaining what the relay list is for and why someone would add a relay")
            static let relayBuiltIn = String(localized: "app_info.settings.relays.built_in", defaultValue: "built in", comment: "Label marking a relay as one of the built-in relays, which cannot be removed")
            static let relayPlaceholder = String(localized: "app_info.settings.relays.placeholder", defaultValue: "wss://relay.example.com", comment: "Placeholder text in the field for adding a relay address")
            static let relayAdd = String(localized: "app_info.settings.relays.add", defaultValue: "add", comment: "Button that adds the typed relay address to the list")
            static let relayRemove = String(localized: "app_info.settings.relays.remove", defaultValue: "remove relay", comment: "Accessibility label for the button that removes an added relay")

            static func relayError(_ failure: NostrRelaySettings.AddFailure) -> String {
                switch failure {
                case .malformed:
                    return String(localized: "app_info.settings.relays.error.malformed", defaultValue: "that doesn't look like a relay address. try wss://host.", comment: "Error shown when a typed relay address cannot be parsed")
                case .alreadyPresent:
                    return String(localized: "app_info.settings.relays.error.duplicate", defaultValue: "that relay is already in the list.", comment: "Error shown when the typed relay address is already in the list")
                case .limitReached:
                    return String(
                        format: String(localized: "app_info.settings.relays.error.limit", defaultValue: "you can add up to %d relays.", comment: "Error shown when the relay list is already at its maximum size; %d is that maximum"),
                        locale: .current,
                        NostrRelaySettings.maxCustomRelays
                    )
                }
            }
            static let privacyTitle = String(localized: "app_info.settings.privacy.title", defaultValue: "PRIVACY", comment: "Section header (uppercase) for privacy settings such as hiding notification previews")
            static let hidePreviewsTitle = String(localized: "app_info.settings.hide_previews.title", defaultValue: "hide message previews", comment: "Title of the setting that keeps message text, sender names, and geohashes out of lock-screen notifications")
            static let hidePreviewsSubtitle = String(localized: "app_info.settings.hide_previews.subtitle", defaultValue: "notifications say that something arrived without showing the message, who sent it, or which location channel it came from. anyone holding your locked phone learns nothing from the lock screen. on by default.", comment: "Subtitle explaining what hiding notification message previews does")
            static let autoRevealFavoritesTitle = String(localized: "app_info.settings.auto_reveal_favorites.title", defaultValue: "show images from favorites", comment: "Title of the setting that shows images from favorite contacts without the tap-to-reveal blur")
            static let autoRevealFavoritesSubtitle = String(localized: "app_info.settings.auto_reveal_favorites.subtitle", defaultValue: "images from people you marked as favorites show right away. images from everyone else stay blurred until you tap them. off by default.", comment: "Subtitle explaining that only favorite contacts' images skip the blur")

            static let dangerTitle = String(localized: "app_info.settings.danger.title", defaultValue: "DANGER ZONE", comment: "Section header (uppercase) for destructive actions in settings")
            static let panicButton = String(localized: "app_info.settings.danger.panic_button", defaultValue: "panic wipe", comment: "Button in the settings danger zone that erases all local data after confirmation")
            static let panicNote = String(localized: "app_info.settings.danger.panic_note", defaultValue: "erases all messages, keys, and identity. triple-tapping the bitchat/ logo does the same, instantly.", comment: "Caption under the panic wipe button explaining what it does and the triple-tap shortcut")
            static let panicConfirmTitle = String(localized: "app_info.settings.danger.panic_confirm_title", defaultValue: "wipe all data?", comment: "Title of the confirmation dialog before a panic wipe")
            static let panicConfirmAction = String(localized: "app_info.settings.danger.panic_confirm_action", defaultValue: "wipe everything", comment: "Destructive confirmation button that performs the panic wipe")
        }

        enum Features {
            static let title = String(localized: "app_info.features.title")
            static let offlineComm = AppInfoFeatureInfo(
                icon: "wifi.slash",
                title: "app_info.features.offline.title",
                description: "app_info.features.offline.description"
            )
            static let encryption = AppInfoFeatureInfo(
                icon: "lock.shield",
                title: "app_info.features.encryption.title",
                description: "app_info.features.encryption.description"
            )
            static let extendedRange = AppInfoFeatureInfo(
                icon: "antenna.radiowaves.left.and.right",
                title: "app_info.features.extended_range.title",
                description: "app_info.features.extended_range.description"
            )
            static let mentions = AppInfoFeatureInfo(
                icon: "at",
                title: "app_info.features.mentions.title",
                description: "app_info.features.mentions.description"
            )
            static let favorites = AppInfoFeatureInfo(
                icon: "star.fill",
                title: "app_info.features.favorites.title",
                description: "app_info.features.favorites.description"
            )
            static let geohash = AppInfoFeatureInfo(
                icon: "number",
                title: "app_info.features.geohash.title",
                description: "app_info.features.geohash.description"
            )
            static let bridge = AppInfoFeatureInfo(
                icon: "network",
                resolvedTitle: String(localized: "app_info.features.bridge.title", defaultValue: "mesh bridging", comment: "Feature row title for the mesh bridge in the app info sheet"),
                resolvedDescription: String(localized: "app_info.features.bridge.description", defaultValue: "links nearby mesh islands through the internet so one crowd isn't split by radio range", comment: "Feature row description for the mesh bridge in the app info sheet")
            )
        }

        enum Legend {
            static let title = String(localized: "app_info.legend.title")
            /// Every glyph the peer lists and headers use, in one place —
            /// nothing else in the app defines them. A nil color renders in
            /// the theme's primary text color.
            static let items: [(icon: String, color: Color?, text: String)] = [
                ("antenna.radiowaves.left.and.right", nil, String(localized: "app_info.legend.mesh_connected")),
                ("point.3.filled.connected.trianglepath.dotted", nil, String(localized: "app_info.legend.mesh_relayed")),
                ("globe", nil, String(localized: "app_info.legend.nostr")),
                ("network", Color.cyan, String(localized: "app_info.legend.bridged", defaultValue: "message arrived across a mesh bridge", comment: "Symbols legend entry for the cyan network glyph shown on messages carried across a mesh bridge")),
                ("person", nil, String(localized: "app_info.legend.offline")),
                ("mappin.and.ellipse", nil, String(localized: "app_info.legend.location_nearby")),
                ("face.dashed", nil, String(localized: "app_info.legend.teleported")),
                ("lock.fill", nil, String(localized: "app_info.legend.encrypted")),
                ("lock.slash", nil, String(localized: "app_info.legend.encryption_failed")),
                ("checkmark.seal.fill", nil, String(localized: "app_info.legend.verified")),
                ("star.fill", nil, String(localized: "app_info.legend.favorite")),
                ("envelope.fill", nil, String(localized: "app_info.legend.unread")),
                ("nosign", nil, String(localized: "app_info.legend.blocked"))
            ]
        }

        enum Voice {
            static let title = String(localized: "app_info.voice.title")
            // The live-voice title/description keys are referenced inline at
            // the toggle (they ride the shared settingToggle now).
        }

        enum Location {
            static let notes = AppInfoFeatureInfo(
                icon: "mappin.and.ellipse",
                title: "app_info.location.notes.title",
                description: "app_info.location.notes.description"
            )
        }

        enum Network {
            static let title = String(localized: "app_info.network.title")
            static let topology = AppInfoFeatureInfo(
                icon: "point.3.connected.trianglepath.dotted",
                title: "app_info.network.topology.title",
                description: "app_info.network.topology.description"
            )
        }

        enum Privacy {
            static let title = String(localized: "app_info.privacy.title")
            static let noTracking = AppInfoFeatureInfo(
                icon: "eye.slash",
                title: "app_info.privacy.no_tracking.title",
                description: "app_info.privacy.no_tracking.description"
            )
            static let ephemeral = AppInfoFeatureInfo(
                icon: "shuffle",
                title: "app_info.privacy.ephemeral.title",
                description: "app_info.privacy.ephemeral.description"
            )
            static let panic = AppInfoFeatureInfo(
                icon: "hand.raised.fill",
                title: "app_info.privacy.panic.title",
                description: "app_info.privacy.panic.description"
            )
        }

        enum HowToUse {
            static let title = String(localized: "app_info.how_to_use.title")
            /// One row per instruction, with an icon for each.
            static var items: [(icon: String, text: String)] {
                // The translations carry their legacy bullet-list prefix
                // ("• "), so it is stripped here.
                func item(_ icon: String, _ text: String) -> (icon: String, text: String) {
                    (icon, text.hasPrefix("• ") ? String(text.dropFirst(2)) : text)
                }
                return [
                    item("number", String(localized: "app_info.how_to_use.change_channels")),
                    item("hand.tap", String(localized: "app_info.how_to_use.clear_chat")),
                    item("slash.circle", String(localized: "app_info.how_to_use.commands"))
                ]
            }
        }

    }

    var body: some View {
        paneContent
            // A segmented control in the title slot, as in the system apps;
            // it replaces the title on screen.
            .sheetChrome(
                title: Text(Strings.appName),
                onClose: { dismiss() },
                principal: { panePicker }
            )
            #if os(macOS)
            .frame(width: 600, height: 700)
            #endif
            .sheet(isPresented: $showTopology) {
                if let topologyProvider {
                    MeshTopologyView(provider: topologyProvider)
                }
            }
    }

    // MARK: - Pane switching

    private var panePicker: some View {
        Picker(Strings.Settings.tabPickerLabel, selection: $selectedPane) {
            Text(Strings.Settings.tabInfo).tag(Pane.info)
            Text(Strings.Settings.tabSettings).tag(Pane.settings)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        // The control's own width, not the whole title slot.
        .fixedSize()
    }

    @ViewBuilder
    private var paneContent: some View {
        switch selectedPane {
        case .settings:
            settingsContent
        case .info:
            infoContent
        }
    }

    /// A section header in title case. The catalog keeps the old all-caps
    /// headers; iOS sets its own case for grouped headers, and macOS shows
    /// them as written.
    private func sectionHeader(_ title: String) -> Text {
        Text(verbatim: title.localizedCapitalized)
    }

    // MARK: - Settings pane

    /// A native settings form: grouped sections, system text styles and
    /// system controls (inset grouped on iOS, the System Settings look on
    /// macOS).
    private var settingsContent: some View {
        Form {
            if let nickname {
                nicknameSection(nickname)
            }
            languageSection
            voiceSection
            bridgeSection
            torSection
            relaySection
            locationSection
            bubbleAppearanceSection
            privacySection
            if onPanicWipe != nil {
                dangerSection
            }
        }
        .formStyle(.grouped)
        // The default on macOS is a checkbox; settings use the switch.
        .toggleStyle(.switch)
        // Commit the nickname when editing ends: focus leaves the field, or
        // the pane or sheet goes away.
        .onChange(of: isNicknameFocused) { isFocused in
            if !isFocused {
                onNicknameCommit?()
            }
        }
        .onDisappear { onNicknameCommit?() }
    }

    /// Nickname editor. It lived in the main header until the header became
    /// a native title bar, which shows the nickname as its subtitle.
    private func nicknameSection(_ nickname: Binding<String>) -> some View {
        Section {
            HStack(spacing: 2) {
                Text(verbatim: "@")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                // An explicit prompt: a macOS form shows the title as a
                // label, not as a placeholder.
                TextField(
                    text: nickname,
                    prompt: Text("content.input.nickname_placeholder")
                ) {
                    Text("content.input.nickname_placeholder")
                }
                .labelsHidden()
                .textFieldStyle(.plain)
                .focused($isNicknameFocused)
                .autocorrectionDisabled(true)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .submitLabel(.done)
                .onSubmit { onNicknameCommit?() }
            }
        } header: {
            sectionHeader(Strings.Settings.nicknameTitle)
        }
    }

    /// Language: an in-app override so the UI language can differ from the
    /// device language. It takes effect on the next launch.
    private var languageSection: some View {
        Section {
            Picker(selection: languageSelection) {
                Text(Strings.Settings.languageSystem).tag("")
                Divider()
                ForEach(AppLanguageSettings.availableLanguages, id: \.self) { code in
                    Text(AppLanguageSettings.endonym(for: code)).tag(code)
                }
            } label: {
                Text(Strings.Settings.languagePickerLabel)
            }
            .pickerStyle(.menu)
        } header: {
            sectionHeader(Strings.Settings.languageTitle)
        } footer: {
            if showLanguageRestartNote {
                Text(Strings.Settings.languageRestartNote)
            }
        }
    }

    private var languageSelection: Binding<String> {
        Binding(
            get: { languageOverride },
            set: { selectLanguage($0.isEmpty ? nil : $0) }
        )
    }

    private var voiceSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { liveVoiceEnabled },
                set: { newValue in
                    liveVoiceEnabled = newValue
                    PTTSettings.liveVoiceEnabled = newValue
                }
            )) {
                Text("app_info.voice.live.title")
                Text("app_info.voice.live.description")
            }
        } header: {
            sectionHeader(Strings.Voice.title)
        }
    }

    /// Mesh bridge. The row's secondary text says where the bridge meets:
    /// the geohash rendezvous cell, or why there isn't one yet (no location
    /// and no bridge peer advertising a cell).
    private var bridgeSection: some View {
        Section {
            Toggle(isOn: bridgeToggleBinding) {
                Text(Strings.Settings.bridgeTitle)
                if bridgeService.isEnabled {
                    Text(bridgeService.activeCell.map(Strings.Settings.bridgeCell) ?? Strings.Settings.bridgeNoCell)
                }
            }
        } header: {
            sectionHeader(Strings.Settings.connectivityTitle)
        } footer: {
            Text(Strings.Settings.bridgeSubtitle)
        }
    }

    private var torSection: some View {
        Section {
            Toggle(isOn: torToggleBinding) {
                Text(Strings.Settings.torTitle)
            }
            // Turning tor off is not a location-channels-only choice, so say
            // what it costs while it is off, in the section, rather than in
            // the footer everyone skims.
            if !locationChannelsModel.userTorEnabled {
                Label {
                    Text(verbatim: Strings.Settings.torOffWarning)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.footnote)
                .foregroundStyle(palette.alertRed)
            }
        } footer: {
            Text(verbatim: Strings.Settings.torSubtitle)
        }
    }

    /// Relay list editor. The built-in relays are four well-known hostnames, so
    /// a filter blocking four names ends internet-delivered private messages;
    /// adding one here is the only fix that does not need a new build.
    private var relaySection: some View {
        Section {
            ForEach(NostrRelayManager.builtInRelayURLs.sorted(), id: \.self) { relay in
                LabeledContent {
                    Text(verbatim: Strings.Settings.relayBuiltIn)
                } label: {
                    relayText(relay)
                }
            }

            ForEach(customRelays, id: \.self) { relay in
                #if os(iOS)
                relayText(relay)
                #else
                // A macOS form has no swipe to delete.
                LabeledContent {
                    Button(role: .destructive) {
                        removeRelay(relay)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Strings.Settings.relayRemove)
                } label: {
                    relayText(relay)
                }
                #endif
            }
            .onDelete { offsets in
                offsets.map { customRelays[$0] }.forEach(removeRelay)
            }

            if customRelays.count < NostrRelaySettings.maxCustomRelays {
                HStack {
                    TextField(
                        text: $relayInput,
                        prompt: Text(Strings.Settings.relayPlaceholder)
                    ) {
                        Text(Strings.Settings.relayPlaceholder)
                    }
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled(true)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .onSubmit(addRelay)
                    Button(Strings.Settings.relayAdd, action: addRelay)
                        .buttonStyle(.borderless)
                        .disabled(relayInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if let relayError {
                Text(verbatim: relayError)
                    .font(.footnote)
                    .foregroundStyle(palette.alertRed)
            }
        } header: {
            sectionHeader(Strings.Settings.relaysTitle)
        } footer: {
            Text(Strings.Settings.relaysSubtitle)
        }
        // The store can change from outside this view — a panic wipe clears it —
        // so follow it rather than trusting the value read at creation.
        .onReceive(NotificationCenter.default.publisher(for: NostrRelaySettings.didChangeNotification)) { _ in
            reloadCustomRelays()
        }
    }

    /// A relay address: one line, truncated in the middle so the host's
    /// both ends stay visible.
    private func relayText(_ relay: String) -> some View {
        Text(verbatim: relay)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    /// Location notes (dead drops) and the location permission. Location
    /// powers the channels list and the bridge cell, so its control lives
    /// with the other connectivity settings. Platform reality shapes the
    /// three states: the app may only prompt while never-asked;
    /// granted/denied both flip in the system permission screen.
    private var locationSection: some View {
        Section {
            // Turning notes on may need the location prompt; the permission
            // rows below cover the denied path.
            Toggle(isOn: Binding(
                get: { locationNotesEnabled },
                set: { newValue in
                    locationNotesEnabled = newValue
                    LocationNotesSettings.enabled = newValue
                    if newValue {
                        locationManager.enableLocationChannels()
                    }
                }
            )) {
                Strings.Location.notes.title
                Strings.Location.notes.description
            }

            switch locationChannelsModel.permissionState {
            case .authorized:
                Button(role: .destructive, action: SystemSettings.location.open) {
                    Text("location_channels.action.remove_access")
                }
            case .notDetermined:
                Button(action: { locationChannelsModel.enableLocationChannels() }) {
                    Text("location_channels.action.request_permissions")
                }
            case .denied, .restricted:
                Text("location_channels.permission_denied")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("location_channels.action.open_settings", action: SystemSettings.location.open)
            }
        }
    }

    /// Privacy: what a locked, seized, or borrowed phone gives away without
    /// being unlocked, and which images show without the blur. Two rows
    /// share the section, so each explanation is its row's secondary text.
    private var privacySection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { hideMessagePreviews },
                set: { newValue in
                    hideMessagePreviews = newValue
                    NotificationPrivacySettings.hideMessagePreviews = newValue
                }
            )) {
                Text(verbatim: Strings.Settings.hidePreviewsTitle)
                Text(verbatim: Strings.Settings.hidePreviewsSubtitle)
            }

            Toggle(isOn: Binding(
                get: { autoRevealFavoriteImages },
                set: { newValue in
                    autoRevealFavoriteImages = newValue
                    MediaRevealSettings.autoRevealFavorites = newValue
                }
            )) {
                Text(verbatim: Strings.Settings.autoRevealFavoritesTitle)
                Text(verbatim: Strings.Settings.autoRevealFavoritesSubtitle)
            }

            if let blockedAccountsProvider, let onUnblock {
                Button {
                    showBlockedAccounts = true
                } label: {
                    HStack {
                        Text(verbatim: BlockedAccountsSheet.Strings.title)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showBlockedAccounts) {
                    BlockedAccountsSheet(load: blockedAccountsProvider, onUnblock: onUnblock)
                }
            }
        } header: {
            sectionHeader(Strings.Settings.privacyTitle)
        }
    }

    private var bubbleAppearanceSection: some View {
        Section {
            MessageBubbleColorPicker(selection: Binding(
                get: { MessageBubbleColorSettings.selected.rawValue },
                set: { rawValue in
                    if let color = MessageBubbleColor(rawValue: rawValue) {
                        MessageBubbleColorSettings.selected = color
                    }
                }
            ))
        } header: {
            sectionHeader(String(localized: "app_info.settings.appearance.title", defaultValue: "appearance", comment: "Settings section for the user's outgoing message bubble color"))
        }
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                showPanicConfirmation = true
            } label: {
                Text(Strings.Settings.panicButton)
            }
            .confirmationDialog(
                Strings.Settings.panicConfirmTitle,
                isPresented: $showPanicConfirmation,
                titleVisibility: .visible
            ) {
                Button(Strings.Settings.panicConfirmAction, role: .destructive) {
                    onPanicWipe?()
                }
                Button("common.cancel", role: .cancel) {}
            }
        } header: {
            sectionHeader(Strings.Settings.dangerTitle)
        } footer: {
            Text(Strings.Settings.panicNote)
        }
    }

    private func selectLanguage(_ code: String?) {
        let previous = languageOverride
        AppLanguageSettings.setOverride(code)
        languageOverride = code ?? ""
        if languageOverride != previous {
            showLanguageRestartNote = true
        }
    }

    private var bridgeToggleBinding: Binding<Bool> {
        Binding(
            get: { bridgeService.isEnabled },
            set: { bridgeService.setEnabled($0) }
        )
    }

    private func addRelay() {
        let candidate = relayInput
        switch NostrRelaySettings.add(candidate, builtIn: NostrRelayManager.builtInRelayURLs) {
        case .success:
            relayInput = ""
            relayError = nil
            reloadCustomRelays()
        case .failure(let failure):
            relayError = Strings.Settings.relayError(failure)
        }
    }

    private func removeRelay(_ relay: String) {
        NostrRelaySettings.remove(relay)
        reloadCustomRelays()
    }

    private func reloadCustomRelays() {
        customRelays = NostrRelaySettings.customRelays()
    }

    private var torToggleBinding: Binding<Bool> {
        Binding(
            get: { locationChannelsModel.userTorEnabled },
            set: { locationChannelsModel.setUserTorEnabled($0) }
        )
    }

    // MARK: - Info pane

    /// The about content as a native grouped form: the app name, then one
    /// section each for how to use, network diagnostics, features, privacy
    /// and the symbols legend, every entry a label row.
    private var infoContent: some View {
        Form {
            Section {
                VStack(spacing: 4) {
                    Text(Strings.appName)
                        .font(.largeTitle.bold())
                    Text(Strings.tagline)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .listRowBackground(Color.clear)
            }

            Section {
                ForEach(Strings.HowToUse.items, id: \.icon) { item in
                    Label {
                        Text(verbatim: item.text)
                    } icon: {
                        Image(systemName: item.icon)
                    }
                }
            } header: {
                sectionHeader(Strings.HowToUse.title)
            }

            if topologyProvider != nil {
                Section {
                    topologyRow
                } header: {
                    sectionHeader(Strings.Network.title)
                }
            }

            Section {
                FeatureRow(info: Strings.Features.offlineComm)
                FeatureRow(info: Strings.Features.encryption)
                FeatureRow(info: Strings.Features.extendedRange)
                FeatureRow(info: Strings.Features.bridge)
                FeatureRow(info: Strings.Features.favorites)
                FeatureRow(info: Strings.Features.geohash)
                FeatureRow(info: Strings.Features.mentions)
            } header: {
                sectionHeader(Strings.Features.title)
            }

            Section {
                FeatureRow(info: Strings.Privacy.noTracking)
                FeatureRow(info: Strings.Privacy.ephemeral)
                FeatureRow(info: Strings.Privacy.panic)
            } header: {
                sectionHeader(Strings.Privacy.title)
            }

            Section {
                ForEach(Strings.Legend.items, id: \.icon) { item in
                    Label {
                        Text(verbatim: item.text)
                    } icon: {
                        Image(systemName: item.icon)
                            .foregroundStyle(item.color ?? Color.primary)
                    }
                }
            } header: {
                sectionHeader(Strings.Legend.title)
            }
        }
        .formStyle(.grouped)
    }

    /// Opens the mesh topology map in a sheet of its own.
    private var topologyRow: some View {
        Button {
            showTopology = true
        } label: {
            HStack {
                FeatureRow(info: Strings.Network.topology)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        #if os(macOS)
        // A macOS form draws a push button; this is a row.
        .buttonStyle(.plain)
        #else
        // A row, not an accent-colored action.
        .tint(.primary)
        #endif
        .accessibilityHint(Text("app_info.network.topology.hint"))
    }
}

struct AppInfoFeatureInfo {
    let icon: String
    let title: Text
    let description: Text

    /// Catalog-backed strings (existing keys).
    init(icon: String, title: LocalizedStringKey, description: LocalizedStringKey) {
        self.icon = icon
        self.title = Text(title)
        self.description = Text(description)
    }

    /// Pre-resolved strings — new keys that carry their English defaultValue
    /// inline until the i18n pass adds them to the catalog.
    init(icon: String, resolvedTitle: String, resolvedDescription: String) {
        self.icon = icon
        self.title = Text(resolvedTitle)
        self.description = Text(resolvedDescription)
    }
}

/// A feature or fact in the info pane: a label row with the title and its
/// description as secondary text, in system text styles.
struct FeatureRow: View {
    let info: AppInfoFeatureInfo

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                info.title
                info.description
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: info.icon)
        }
    }
}

#Preview("Default") {
    AppInfoView()
        .environmentObject(LocationChannelsModel())
}

#Preview("Dynamic Type XXL") {
    AppInfoView()
        .environmentObject(LocationChannelsModel())
        .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
}

#Preview("Dynamic Type XS") {
    AppInfoView()
        .environmentObject(LocationChannelsModel())
        .environment(\.sizeCategory, .extraSmall)
}
