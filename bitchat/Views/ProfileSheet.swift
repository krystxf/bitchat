//
// ProfileSheet.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// The user's own profile, opened from the sidebar's title bar: the avatar
/// others see and the nickname shown next to their messages.
struct ProfileSheet: View {
    @EnvironmentObject private var appChromeModel: AppChromeModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNicknameFocused: Bool

    private enum Strings {
        static let title = String(localized: "profile.title", defaultValue: "profile", comment: "Title of the sheet where the user edits their own profile, and the label of the sidebar button that opens it")
        static let nicknameHeader = String(localized: "app_info.settings.nickname.title", defaultValue: "NICKNAME", comment: "Section header (uppercase) for the nickname field in settings")
        static let nicknameFooter = String(localized: "profile.nickname.footer", defaultValue: "people nearby see this name next to your messages. you can change it any time.", comment: "Footer under the nickname field in the profile sheet")
    }

    private var nickname: Binding<String> {
        Binding(
            get: { appChromeModel.nickname },
            set: { appChromeModel.setNickname($0) }
        )
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    InitialsAvatar(name: appChromeModel.nickname, peerID: appChromeModel.myPeerID, size: 72)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section {
                HStack(spacing: 2) {
                    Text(verbatim: "@")
                        .foregroundStyle(.secondary)
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
                // The catalog keeps the legacy uppercase; forms show title case.
                Text(verbatim: Strings.nicknameHeader.localizedCapitalized)
            } footer: {
                Text(verbatim: Strings.nicknameFooter)
            }
        }
        .formStyle(.grouped)
        .sheetChrome(title: Text(verbatim: Strings.title), onClose: commitAndClose)
        .onAppear { isNicknameFocused = true }
        // Swipe-to-dismiss skips the close button; save on the way out too.
        .onDisappear { appChromeModel.validateAndSaveNickname() }
        #if os(macOS)
        .frame(minWidth: 380, idealWidth: 420, minHeight: 320)
        #endif
    }

    private func commitAndClose() {
        appChromeModel.validateAndSaveNickname()
        dismiss()
    }
}
