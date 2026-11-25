//
// LocationPoWMiningBar.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// A small strip above the composer while a location-channel message is
/// still doing its proof of work: a spinner, the time spent so far, and a
/// "send now" button that sends it with the work done so far (sending
/// another message does the same).
///
/// It waits `revealDelay` before showing, so the default 8 bits — about a
/// millisecond — never flashes it.
struct LocationPoWMiningBar: View {
    @ObservedObject private var status = LocationPoWMiningStatus.shared
    let onSendNow: () -> Void

    @State private var isRevealed = false

    private static let revealDelay: UInt64 = 500_000_000

    var body: some View {
        Group {
            if isRevealed, let miningSince = status.miningSince {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(verbatim: Strings.mining)
                        .lineLimit(1)
                    Text(miningSince, style: .timer)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button(action: onSendNow) {
                        Text(verbatim: Strings.sendNow)
                    }
                    .buttonStyle(.borderless)
                }
                .font(.footnote)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassSurface(in: Capsule())
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        // Keyed on whether anything is mining, so a queue of sends keeps the
        // strip up instead of hiding and re-revealing it between them.
        .task(id: status.isMining) {
            guard status.isMining else {
                withAnimation(.easeOut(duration: 0.2)) { isRevealed = false }
                return
            }
            try? await Task.sleep(nanoseconds: Self.revealDelay)
            guard !Task.isCancelled, status.isMining else { return }
            withAnimation(.easeOut(duration: 0.2)) { isRevealed = true }
        }
    }
}

extension LocationPoWMiningBar {
    enum Strings {
        static let mining = String(localized: "content.pow.mining", defaultValue: "Mining proof of work…", comment: "Shown above the composer while a location channel message is still doing its proof of work before it is sent")
        static let sendNow = String(localized: "content.pow.send_now", defaultValue: "Send now", comment: "Button above the composer that sends a location channel message right away with the proof of work done so far")
    }
}
