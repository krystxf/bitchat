//
// ExtremeSecurityExitPolicy.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// App lifecycle moments that could count as "leaving the app".
enum AppExitEvent: Equatable, CaseIterable {
    /// iOS: every scene went to the background (home, another app, lock).
    case enteredBackground
    /// iOS: the app switcher, Notification Center, Control Center or a call
    /// alert covers the app, which is still on screen and running.
    case becameInactive
    /// The process is about to end: quit on macOS, or a swipe away in the
    /// iOS app switcher while the app still runs.
    case willTerminate
    /// macOS: the last window closed.
    case lastWindowClosed
    /// macOS: the app was hidden (⌘H).
    case hidden
    /// macOS: another app became frontmost.
    case resignedActive
}

/// Decides which lifecycle moments run extreme security mode's message wipe.
///
/// iOS: leaving the app means the background. `.inactive` also fires for
/// the app switcher, Notification Center, Control Center and call alerts,
/// while the person is still using the app, so wiping there would delete a
/// conversation for pulling down a notification.
///
/// macOS: leaving the app means quitting it or closing its last window.
/// Hiding the app or switching to another one is everyday desktop
/// multitasking; wiping then would delete conversations every time someone
/// looks at another window. The app quits when its last window closes, so
/// the two events usually arrive together; wiping twice is harmless.
enum ExtremeSecurityExitPolicy {
    enum Platform {
        case iOS
        case macOS

        static var current: Platform {
            #if os(iOS)
            return .iOS
            #else
            return .macOS
            #endif
        }
    }

    static func shouldWipeMessages(
        on event: AppExitEvent,
        isEnabled: Bool,
        platform: Platform = .current
    ) -> Bool {
        guard isEnabled else { return false }
        switch platform {
        case .iOS:
            return event == .enteredBackground || event == .willTerminate
        case .macOS:
            return event == .willTerminate || event == .lastWindowClosed
        }
    }

    /// The exit event a scene phase change stands for, if any.
    static func event(for phase: ScenePhase) -> AppExitEvent? {
        switch phase {
        case .background:
            return .enteredBackground
        case .inactive:
            return .becameInactive
        case .active:
            return nil
        @unknown default:
            return nil
        }
    }
}
