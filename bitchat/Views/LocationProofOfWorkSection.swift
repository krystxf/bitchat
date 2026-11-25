//
// LocationProofOfWorkSection.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// Settings section for proof of work on location-channel messages (see
/// `LocationProofOfWorkSettings`): the switch, and while it is on, the
/// difficulty with an estimated mining time for each level.
///
/// The Android app has the same option as a switch and a 0–32 bit slider.
/// Here the switch covers 0, and the picker offers Android's named levels
/// that a phone can reach within the mining time cap.
struct LocationProofOfWorkSection: View {
    @State private var isEnabled = LocationProofOfWorkSettings.isEnabled
    @State private var difficultyBits = LocationProofOfWorkSettings.difficultyBits

    var body: some View {
        Section {
            Toggle(isOn: enabledBinding) {
                Text(verbatim: Strings.title)
                Text(verbatim: Strings.subtitle)
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
            // Same treatment as the other settings headers: the catalog
            // keeps them all caps, the form shows them in title case.
            Text(verbatim: Strings.header.localizedCapitalized)
        } footer: {
            if isEnabled {
                Text(verbatim: Strings.footer)
            }
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
        static let header = String(localized: "app_info.settings.location_channels.title", defaultValue: "LOCATION CHANNELS", comment: "Section header (uppercase) for location channel settings such as proof of work")
        static let title = String(localized: "app_info.settings.pow.title", defaultValue: "proof of work", comment: "Title of the setting that makes the device do NIP-13 proof of work before each location channel message")
        static let subtitle = String(localized: "app_info.settings.pow.subtitle", defaultValue: "your device does a little extra work before each location channel message. it takes you a moment but makes flooding a channel slow for spammers, and apps that check it let your messages past their spam limits. on by default.", comment: "Subtitle explaining what proof of work on location channel messages does and why")
        static let difficulty = String(localized: "app_info.settings.pow.difficulty", defaultValue: "difficulty", comment: "Label of the picker that chooses how much proof of work each location channel message carries")
        static let footer = String(localized: "app_info.settings.pow.footer", defaultValue: "each step takes 16 times the work of the one before. times are estimates for an older phone. a message never waits more than a minute: if mining runs long, or you send again, it goes out with the work done so far.", comment: "Footer under the proof of work settings explaining the difficulty levels, the time estimates, and the one-minute limit")

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
                return String(localized: "app_info.settings.pow.time.instant", defaultValue: "instant", comment: "Estimated mining time for a proof of work level that finishes at once")
            case .underASecond:
                return String(localized: "app_info.settings.pow.time.under_second", defaultValue: "under a second", comment: "Estimated mining time for a proof of work level that takes less than one second")
            case .about(let seconds):
                let duration = Duration.seconds(seconds).formatted(
                    .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 1)
                )
                return String(
                    format: String(localized: "app_info.settings.pow.time.about", defaultValue: "about %@", comment: "Estimated mining time for a proof of work level; %@ is a short duration such as 4 sec or 1 min"),
                    locale: .current,
                    duration
                )
            }
        }
    }
}
