//
// ExtremeSecurityExitPolicyTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI
import Testing
@testable import bitchat

@Suite("ExtremeSecurityExitPolicy")
struct ExtremeSecurityExitPolicyTests {
    @Test func nothingWipesWhileTheModeIsOff() {
        for platform in [ExtremeSecurityExitPolicy.Platform.iOS, .macOS] {
            for event in AppExitEvent.allCases {
                #expect(!ExtremeSecurityExitPolicy.shouldWipeMessages(
                    on: event,
                    isEnabled: false,
                    platform: platform
                ))
            }
        }
    }

    @Test func iOSWipesWhenTheAppLeavesTheScreen() {
        let wiping = AppExitEvent.allCases.filter {
            ExtremeSecurityExitPolicy.shouldWipeMessages(on: $0, isEnabled: true, platform: .iOS)
        }
        // Not on `.becameInactive`: the app switcher or a pulled-down
        // notification is not leaving the app.
        #expect(Set(wiping) == [.enteredBackground, .willTerminate])
    }

    @Test func macOSWipesOnQuitAndWhenTheLastWindowCloses() {
        let wiping = AppExitEvent.allCases.filter {
            ExtremeSecurityExitPolicy.shouldWipeMessages(on: $0, isEnabled: true, platform: .macOS)
        }
        // Not on hiding or switching apps: everyday desktop multitasking.
        #expect(Set(wiping) == [.willTerminate, .lastWindowClosed])
    }

    @Test func scenePhasesMapToExitEvents() {
        #expect(ExtremeSecurityExitPolicy.event(for: .background) == .enteredBackground)
        #expect(ExtremeSecurityExitPolicy.event(for: .inactive) == .becameInactive)
        #expect(ExtremeSecurityExitPolicy.event(for: .active) == nil)
    }
}
