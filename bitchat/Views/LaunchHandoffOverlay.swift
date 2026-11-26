//
// LaunchHandoffOverlay.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// Hands the launch screen over to the app. The first window opens with the
/// launch mark exactly where the launch screen drew it, on the same color;
/// the mark then grows slightly and fades out, revealing the UI that loaded
/// underneath. Under Reduce Motion it only fades, and faster.
///
/// The overlay never delays the app: the UI builds and runs behind it, and it
/// does not take input, even while it fades.
struct LaunchHandoffOverlay: View {
    static let duration: TimeInterval = 0.5
    static let reducedMotionDuration: TimeInterval = 0.25
    static let finalScale: CGFloat = 1.2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Read, not claimed, here: SwiftUI can create and discard view values,
    /// so the claim waits until the overlay is on screen. A window created
    /// after the hand-off never draws a frame of it.
    @State private var isPresented = !LaunchHandoffGate.shared.isClaimed
    @State private var isRevealed = false

    var body: some View {
        if isPresented {
            ZStack {
                Color("LaunchBackground")
                // Natural size, centered on the whole screen: the frame the
                // UILaunchScreen image gets.
                Image("LaunchMark")
                    .scaleEffect(isRevealed && !reduceMotion ? Self.finalScale : 1)
            }
            .ignoresSafeArea()
            .opacity(isRevealed ? 0 : 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task { await reveal() }
        }
    }

    private func reveal() async {
        // Two Mac windows restored together both start covered; only the
        // first to appear keeps the hand-off.
        guard LaunchHandoffGate.shared.claim() else {
            isPresented = false
            return
        }
        let duration = reduceMotion ? Self.reducedMotionDuration : Self.duration
        withAnimation(.easeInOut(duration: duration)) {
            isRevealed = true
        }
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        isPresented = false
    }
}

/// Lets only the first window of the process show the launch hand-off: not a
/// second Mac window, not a scene iOS reconnects, and never again after the
/// app returns from the background.
@MainActor
final class LaunchHandoffGate {
    static let shared = LaunchHandoffGate()

    private(set) var isClaimed = false

    /// True for the first caller only.
    func claim() -> Bool {
        guard !isClaimed else { return false }
        isClaimed = true
        return true
    }
}
