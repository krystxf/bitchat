//
// ProfileSheet.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// The user's own profile, opened from the sidebar's title bar: the avatar
/// others see, the nickname shown next to their messages, and the QR code to
/// verify encryption in person.
struct ProfileSheet: View {
    @EnvironmentObject private var appChromeModel: AppChromeModel
    @EnvironmentObject private var verificationModel: VerificationModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNicknameFocused: Bool
    @State private var showsVerification = false

    private enum Strings {
        static let title = String(localized: "profile.title", defaultValue: "Profile", comment: "Title of the sheet where the user edits their own profile, and the label of the sidebar button that opens it")
        static let nicknameHeader = String(localized: "app_info.settings.nickname.title", defaultValue: "Nickname", comment: "Section header (uppercase) for the nickname field in settings")
        static let verification = String(localized: "content.accessibility.verification", comment: "Accessibility label for the verification QR button")
        static let verificationDetail = String(localized: "content.help.verification", comment: "Help text for verification button")
        static let nicknameFooter = String(localized: "profile.nickname.footer", defaultValue: "People nearby see this name next to your messages. You can change it any time.", comment: "Footer under the nickname field in the profile sheet")
    }

    private var nickname: Binding<String> {
        Binding(
            get: { appChromeModel.nickname },
            set: { appChromeModel.setNickname($0) }
        )
    }

    var body: some View {
        Form {
            // The avatar and name others see, as the header of an account
            // page. No row background: it sits on the sheet.
            Section {
                VStack(spacing: 12) {
                    InitialsAvatar(name: appChromeModel.nickname, peerID: appChromeModel.myPeerID, size: 88)
                    if !appChromeModel.nickname.isEmpty {
                        Text(verbatim: appChromeModel.nickname)
                            .font(.title2.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .accessibilityElement(children: .combine)
            }

            Section {
                HStack(spacing: 2) {
                    Text(verbatim: "@")
                        .foregroundStyle(.novaSecondaryText)
                    TextField(
                        "content.input.nickname_placeholder",
                        text: nickname,
                        prompt: Text("content.input.nickname_placeholder")
                    )
                    .textFieldStyle(.plain)
                    .focused($isNicknameFocused)
                    .autocorrectionDisabled(true)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .submitLabel(.done)
                    .onSubmit(commitAndClose)
                }
            } header: {
                Text(verbatim: Strings.nicknameHeader)
                    .foregroundStyle(.novaSecondaryText)
            } footer: {
                Text(verbatim: Strings.nicknameFooter)
                    .foregroundStyle(.novaSecondaryText)
                    // Wrap once at the given width; a footer whose height
                    // depends on a width that depends on its height shakes.
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Color.novaSurface)

            // My QR code and the scanner, to verify encryption in person.
            Section {
                Button {
                    showsVerification = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "qrcode")
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: Strings.verification)
                                .foregroundStyle(.primary)
                            Text(verbatim: Strings.verificationDetail)
                                .font(.footnote)
                                .foregroundStyle(.novaSecondaryText)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.novaSecondaryText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listRowBackground(Color.novaSurface)
        }
        .formStyle(.grouped)
        .novaListBackground()
        .sheet(isPresented: $showsVerification) {
            VerificationSheetView(isPresented: $showsVerification)
                .environmentObject(verificationModel)
        }
        .sheetChrome(title: Text(verbatim: Strings.title), onClose: commitAndClose)
        #if os(macOS)
        // On iPhone the keyboard would cover half the sheet before the user
        // chose to edit; there, a tap on the field starts editing.
        .onAppear { isNicknameFocused = true }
        #endif
        // Swipe-to-dismiss skips the close button; save on the way out too.
        .onDisappear { appChromeModel.validateAndSaveNickname() }
        #if os(macOS)
        // A fixed width and room for every row: when the content is about
        // as tall as the sheet, a legacy scroll bar appears and disappears,
        // the text re-wraps each time and the footer shakes.
        .scrollIndicators(.never)
        .frame(width: 440)
        .frame(minHeight: 480, idealHeight: 520)
        #endif
    }

    private func commitAndClose() {
        appChromeModel.validateAndSaveNickname()
        dismiss()
    }
}
