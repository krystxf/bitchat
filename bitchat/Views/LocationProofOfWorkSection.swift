//
// LocationProofOfWorkSection.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// Settings sections for proof of work on location-channel messages (see
/// `LocationProofOfWorkSettings`): the switch, and while it is on, the
/// difficulty with an estimated mining time for each level; then the
/// separate receive-side filter, with its cost spelled out in its footer.
///
/// The Android app has the same option as a switch and a 0–32 bit slider.
/// Here the switch covers 0, and the picker offers Android's named levels
/// that a phone can reach within the mining time cap.
struct LocationProofOfWorkSection: View {
    @State private var isEnabled = LocationProofOfWorkSettings.isEnabled
    @State private var difficultyBits = LocationProofOfWorkSettings.difficultyBits
    @State private var hidesMessagesWithoutWork = LocationProofOfWorkSettings.hidesMessagesWithoutWork

    var body: some View {
        sendSection
        receiveSection
    }

    private var sendSection: some View {
        Section {
            Toggle(isOn: enabledBinding) {
                SettingsRowLabel(systemImage: "hammer.fill", color: .brown) {
                    Text(verbatim: Strings.title)
                }
            }

            if isEnabled {
                Picker(selection: difficultyBinding) {
                    ForEach(LocationProofOfWorkSettings.difficultyLevels, id: \.self) { bits in
                        Text(verbatim: Strings.level(bits)).tag(bits)
                    }
                } label: {
                    Text(verbatim: Strings.difficulty)
                }
                .pickerStyle(.menu)
            }
        } header: {
            Text(verbatim: Strings.header)
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: Strings.subtitle)
                if isEnabled {
                    Text(verbatim: Strings.footer)
                }
            }
        }
    }

    /// Off by default: most people in a channel run clients that mine
    /// nothing, and hiding them is invisible to them.
    private var receiveSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { hidesMessagesWithoutWork },
                set: { newValue in
                    hidesMessagesWithoutWork = newValue
                    LocationProofOfWorkSettings.hidesMessagesWithoutWork = newValue
                }
            )) {
                SettingsRowLabel(systemImage: "line.3.horizontal.decrease", color: .gray) {
                    Text(verbatim: Strings.hideUnprovenTitle)
                }
            }
        } footer: {
            Text(verbatim: Strings.hideUnprovenFooter)
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { newValue in
                isEnabled = newValue
                LocationProofOfWorkSettings.isEnabled = newValue
            }
        )
    }

    private var difficultyBinding: Binding<Int> {
        Binding(
            get: { difficultyBits },
            set: { newValue in
                LocationProofOfWorkSettings.difficultyBits = newValue
                difficultyBits = LocationProofOfWorkSettings.difficultyBits
            }
        )
    }
}

// MARK: - Mining time estimate

extension LocationProofOfWorkSection {
    /// How long a level takes to mine, in the words the picker uses.
    enum MiningTimeEstimate: Equatable {
        case instant
        case underASecond
        /// Whole seconds, at least 1.
        case about(seconds: Int)

        /// Uses `NostrPoW.estimatedMiningTime(forTargetBits:)`, which assumes
        /// an older phone, so newer devices finish sooner than it says.
        init(targetBits: Int) {
            let seconds = NostrPoW.estimatedMiningTime(forTargetBits: targetBits)
            if seconds < 0.1 {
                self = .instant
            } else if seconds < 1 {
                self = .underASecond
            } else {
                self = .about(seconds: Int(seconds.rounded()))
            }
        }
    }
}

// MARK: - Strings

extension LocationProofOfWorkSection {
    enum Strings {
        static let header = String(localized: "app_info.settings.location_channels.title", defaultValue: "Location Channels", comment: "Section header (uppercase) for location channel settings such as proof of work")
        static let title = String(localized: "app_info.settings.pow.title", defaultValue: "Proof of Work", comment: "Title of the setting that makes the device do NIP-13 proof of work before each location channel message")
        static let subtitle = String(localized: "app_info.settings.pow.subtitle", defaultValue: "Your device does a little extra work before each location channel message. It takes you a moment but makes flooding a channel slow for spammers, and apps that check it let your messages past their spam limits. On by default.", comment: "Subtitle explaining what proof of work on location channel messages does and why")
        static let difficulty = String(localized: "app_info.settings.pow.difficulty", defaultValue: "Difficulty", comment: "Label of the picker that chooses how much proof of work each location channel message carries")
        static let footer = String(localized: "app_info.settings.pow.footer", defaultValue: "Each step takes 16 times the work of the one before. Times are estimates for an older phone. A message never waits more than a minute: if mining runs long, or you send again, it goes out with the work done so far.", comment: "Footer under the proof of work settings explaining the difficulty levels, the time estimates, and the one-minute limit")

        static let hideUnprovenTitle = String(localized: "app_info.settings.pow.hide_unproven.title", defaultValue: "Hide Messages Without Proof of Work", comment: "Title of the setting that hides incoming location channel messages that carry no proof of work")
        static let hideUnprovenFooter = String(localized: "app_info.settings.pow.hide_unproven.footer", defaultValue: "Hides location channel messages that carry no proof of work. Many apps don't add it, including older versions of this one, so with this on you stop seeing the people who use them, and they can't tell. Off by default.", comment: "Footer explaining that hiding messages without proof of work also hides everyone on older or other clients, without them knowing")

        /// One picker option: "16 bits · under a second".
        static func level(_ bits: Int) -> String {
            "\(bitsLabel(bits)) · \(estimate(MiningTimeEstimate(targetBits: bits)))"
        }

        static func bitsLabel(_ bits: Int) -> String {
            String(
                format: String(localized: "app_info.settings.pow.bits", defaultValue: "%lld bits", comment: "Proof of work difficulty in leading zero bits, shown in the difficulty picker; %lld is the number of bits"),
                locale: .current,
                bits
            )
        }

        static func estimate(_ estimate: MiningTimeEstimate) -> String {
            switch estimate {
            case .instant:
                return String(localized: "app_info.settings.pow.time.instant", defaultValue: "Instant", comment: "Estimated mining time for a proof of work level that finishes at once")
            case .underASecond:
                return String(localized: "app_info.settings.pow.time.under_second", defaultValue: "Under a second", comment: "Estimated mining time for a proof of work level that takes less than one second")
            case .about(let seconds):
                let duration = Duration.seconds(seconds).formatted(
                    .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 1)
                )
                return String(
                    format: String(localized: "app_info.settings.pow.time.about", defaultValue: "About %@", comment: "Estimated mining time for a proof of work level; %@ is a short duration such as 4 sec or 1 min"),
                    locale: .current,
                    duration
                )
            }
        }
    }
}
