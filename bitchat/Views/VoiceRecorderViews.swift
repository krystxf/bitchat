//
// VoiceRecorderViews.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// The live waveform in the voice recording bar: one bar per level sample,
/// growing from the leading edge as you speak and scrolling once the bar is
/// full. Unfilled slots show as faint dots so the track reads as a track.
struct VoiceRecordingWaveform: View {
    @ObservedObject var meter: VoiceLevelMeter
    let tint: Color

    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2
    private let minBarHeight: CGFloat = 3

    var body: some View {
        Canvas { context, size in
            let step = barWidth + barSpacing
            let slots = max(0, Int((size.width + barSpacing) / step))
            let levels = meter.history.recent(slots)
            let barColor = GraphicsContext.Shading.color(tint)
            let trackColor = GraphicsContext.Shading.color(tint.opacity(0.25))

            for slot in 0..<slots {
                let index = levels.startIndex + slot
                let isFilled = index < levels.endIndex
                let level = isFilled ? CGFloat(levels[index]) : 0
                let height = max(minBarHeight, level * size.height)
                let rect = CGRect(
                    x: CGFloat(slot) * step,
                    y: (size.height - height) / 2,
                    width: barWidth,
                    height: height
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: isFilled ? barColor : trackColor
                )
            }
        }
        .accessibilityHidden(true)
    }
}

/// The lock target above the mic while holding: an outlined pill with an
/// upward chevron that rises with the drag, and a filled accent circle
/// once releasing would lock the recording hands free.
struct VoiceRecorderLockPill: View {
    let isArmed: Bool
    /// 0...1 drag progress towards the lock threshold.
    let progress: CGFloat
    let tint: Color

    @ThemedPalette private var palette

    var body: some View {
        ZStack {
            if isArmed {
                Circle()
                    .fill(tint)
                    .frame(width: 36, height: 36)
                    .transition(.scale.combined(with: .opacity))
                Image(systemName: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
            } else {
                VStack(spacing: 3) {
                    Image(systemName: "lock")
                        .font(.subheadline.weight(.medium))
                    Image(systemName: "chevron.up")
                        .font(.caption2.weight(.bold))
                        .opacity(0.6 + 0.4 * progress)
                }
                .foregroundColor(palette.secondary)
                .frame(width: 32, height: 48)
                .glassSurface(in: Capsule())
                .transition(.opacity)
            }
        }
        .frame(width: 36, height: 48)
        .offset(y: isArmed ? -6 : -10 * progress)
        .accessibilityHidden(true)
    }
}

/// Tactile cues for the hold-to-record gesture. On a Mac only a Force
/// Touch trackpad plays them; other input ignores the call.
enum VoiceRecorderHaptics {
    /// The press started a recording.
    @MainActor
    static func recordingBegan() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    /// The drag crossed the lock or cancel threshold.
    @MainActor
    static func thresholdCrossed() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #endif
    }
}
