//
// FingerprintView.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI
import BitFoundation

struct FingerprintView: View {
    @EnvironmentObject private var verificationModel: VerificationModel
    let peerID: PeerID
    @Environment(\.dismiss) var dismiss
    @State private var aliasDraft: String = ""
    @State private var didLoadAlias = false

    private enum Strings {
        static let title: LocalizedStringKey = "fingerprint.title"
        static let theirFingerprintKey: String.LocalizationValue = "fingerprint.their_label"
        static let handshakePending: LocalizedStringKey = "fingerprint.handshake_pending"
        static let yourFingerprintKey: String.LocalizationValue = "fingerprint.your_label"
        static let copy: LocalizedStringKey = "common.copy"
        static let verifiedMessage: LocalizedStringKey = "fingerprint.message.verified"
        static let localAlias = String(
            localized: "fingerprint.local_alias.label",
            defaultValue: "Local Alias",
            comment: "Label for the local-only alias field on the fingerprint sheet"
        )
        static let localAliasPlaceholder = String(
            localized: "fingerprint.local_alias.placeholder",
            defaultValue: "Name for this person",
            comment: "Placeholder for the local alias field on the fingerprint sheet"
        )
        static let localAliasHint = String(
            localized: "fingerprint.local_alias.hint",
            defaultValue: "Only on this device. Leave blank to use their claimed nickname.",
            comment: "Explanation under the local alias field"
        )
        static func verifyHint(_ nickname: String) -> String {
            String(
                format: String(localized: "fingerprint.message.verify_hint", comment: "Instruction to compare fingerprints with a named peer"),
                locale: .current,
                nickname
            )
        }
        static let markVerified: LocalizedStringKey = "fingerprint.action.mark_verified"
        static let removeVerification: LocalizedStringKey = "fingerprint.action.remove_verification"
        static let vouchedBadgeKey: String.LocalizationValue = "fingerprint.badge.vouched"
        static func vouchedBy(_ count: Int) -> String {
            String(
                format: String(localized: "fingerprint.message.vouched_by", comment: "How many people the user verified have vouched for this peer"),
                locale: .current,
                count
            )
        }
    }
    
    var body: some View {
        let fingerprintState = verificationModel.fingerprintPresentation(for: peerID)

        NovaForm {
            Section {
                header(fingerprintState)
                    .listRowBackground(Color.clear)
            }

            if fingerprintState.canEditLocalAlias {
                Section {
                    TextField(Strings.localAliasPlaceholder, text: $aliasDraft)
                        .autocorrectionDisabled(true)
                        .onSubmit { commitAlias() }
                } header: {
                    Text(verbatim: Strings.localAlias)
                        .novaSectionText()
                } footer: {
                    Text(verbatim: Strings.localAliasHint)
                        .novaSectionText()
                }
            }

            Section {
                if let fingerprint = fingerprintState.theirFingerprint {
                    fingerprintRow(fingerprint)
                } else {
                    Label {
                        Text(Strings.handshakePending)
                    } icon: {
                        ProgressView()
                    }
                    .foregroundStyle(.novaSecondaryText)
                }
            } header: {
                Text(verbatim: Self.sectionTitle(Strings.theirFingerprintKey))
                    .novaSectionText()
            }

            Section {
                fingerprintRow(fingerprintState.myFingerprint)
            } header: {
                Text(verbatim: Self.sectionTitle(Strings.yourFingerprintKey))
                    .novaSectionText()
            }

            // Vouched (transitively verified) status: shown whenever the
            // peer isn't explicitly verified but people I verified vouch
            // for them, independent of the current session state.
            if fingerprintState.isVouched && !fingerprintState.isVerified {
                Section {
                    Label {
                        Text(verbatim: Self.badgeTitle(Strings.vouchedBadgeKey))
                    } icon: {
                        Image(systemName: "checkmark.seal")
                    }
                    .foregroundStyle(.teal)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Strings.vouchedBy(fingerprintState.voucherCount))
                        if !fingerprintState.voucherNames.isEmpty {
                            Text(verbatim: fingerprintState.voucherNames.joined(separator: ", "))
                        }
                    }
                    .novaSectionText()
                }
                .accessibilityElement(children: .combine)
            }

            if fingerprintState.canToggleVerification {
                Section {
                    if fingerprintState.isVerified {
                        Button(role: .destructive) {
                            verificationModel.unverifyFingerprint(for: peerID)
                            dismiss()
                        } label: {
                            Text(Strings.removeVerification)
                        }
                    } else {
                        Button {
                            verificationModel.verifyFingerprint(for: peerID)
                            dismiss()
                        } label: {
                            Label(Strings.markVerified, systemImage: "checkmark.seal")
                        }
                    }
                } footer: {
                    Group {
                        if fingerprintState.isVerified {
                            Text(Strings.verifiedMessage)
                        } else {
                            Text(Strings.verifyHint(fingerprintState.peerNickname))
                        }
                    }
                    .novaSectionText()
                }
            }
        }
        // The host supplies the way out: the system back button when this
        // view is pushed onto a navigation stack, or the sheet top bar's
        // close button when it is a sheet of its own (`FingerprintSheet`).
        .navigationTitle(Text(Strings.title))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            syncAliasDraft(from: fingerprintState, force: true)
        }
        .onChange(of: fingerprintState.theirFingerprint) { _ in
            // Fingerprint can arrive after the sheet opens; load (or reload)
            // the saved alias then, otherwise an empty draft looks like a clear.
            syncAliasDraft(from: fingerprintState, force: false)
        }
        .onDisappear {
            commitAlias()
        }
    }

    /// The person's avatar and name, with the encryption state under it:
    /// green once verified, as the verified badge is elsewhere.
    private func header(_ state: FingerprintPresentationState) -> some View {
        VStack(spacing: 8) {
            InitialsAvatar(name: state.peerNickname, peerID: peerID, size: 72)
            Text(verbatim: state.peerNickname)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Label {
                Text(verbatim: state.encryptionStatus.description)
            } icon: {
                if let icon = state.encryptionStatus.icon {
                    Image(systemName: icon)
                }
            }
            .font(.subheadline)
            .foregroundStyle(state.encryptionStatus == .noiseVerified ? Color.green : Color.novaSecondaryText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// A fingerprint in groups of four, monospaced so the groups line up
    /// for comparing, with a copy action.
    private func fingerprintRow(_ fingerprint: String) -> some View {
        Text(verbatim: formatFingerprint(fingerprint))
            .font(.body.monospaced())
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .textSelection(.enabled)
            .contextMenu {
                Button {
                    copyToPasteboard(fingerprint)
                } label: {
                    Label(Strings.copy, systemImage: "doc.on.doc")
                }
            }
    }

    private func copyToPasteboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    /// The catalog's fingerprint labels end in a colon ("Their
    /// fingerprint:"); a section header has none.
    static func sectionTitle(_ key: String.LocalizationValue) -> String {
        String(localized: key)
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":："))
            .trimmingCharacters(in: .whitespaces)
    }

    /// The catalog's badge texts start with a symbol ("✓ Verified"); a
    /// row draws the symbol as an SF Symbol instead.
    static func badgeTitle(_ key: String.LocalizationValue) -> String {
        let text = String(localized: key)
        guard let first = text.firstIndex(where: { $0.isLetter }) else { return text }
        return String(text[first...])
    }

    /// Populate `aliasDraft` from the persisted petname once we know the
    /// fingerprint. `force` reloads even if we already loaded (onAppear).
    private func syncAliasDraft(from state: FingerprintPresentationState, force: Bool) {
        guard state.canEditLocalAlias else { return }
        if didLoadAlias && !force { return }
        aliasDraft = state.localPetname ?? ""
        didLoadAlias = true
    }

    private func commitAlias() {
        let fingerprintState = verificationModel.fingerprintPresentation(for: peerID)
        guard fingerprintState.canEditLocalAlias else { return }
        // Don't treat "never loaded a draft" as an intentional clear.
        guard didLoadAlias else { return }
        let current = fingerprintState.localPetname ?? ""
        let draft = aliasDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard draft != current else { return }
        verificationModel.setLocalPetname(draft.isEmpty ? nil : draft, for: peerID)
    }
    
    private func formatFingerprint(_ fingerprint: String) -> String {
        // Convert to uppercase and format into 4 lines (4 groups of 4 on each line)
        let uppercased = fingerprint.uppercased()
        var formatted = ""
        
        for (index, char) in uppercased.enumerated() {
            // Add space every 4 characters (but not at the start)
            if index > 0 && index % 4 == 0 {
                // Add newline after every 16 characters (4 groups of 4)
                if index % 16 == 0 {
                    formatted += "\n"
                } else {
                    formatted += " "
                }
            }
            formatted += String(char)
        }
        
        return formatted
    }
}

/// `FingerprintView` presented as a sheet of its own, with the shared
/// sheet top bar: the title and the glass close button.
struct FingerprintSheet: View {
    let peerID: PeerID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FingerprintView(peerID: peerID)
            .sheetChrome(title: Text("fingerprint.title"), onClose: { dismiss() })
    }
}
