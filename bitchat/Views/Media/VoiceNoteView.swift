import SwiftUI

struct VoiceNoteView: View {
    private let url: URL
    private let isSending: Bool
    private let sendProgress: Double?
    private let isLive: Bool
    private let foregroundColor: Color
    private let onCancel: (() -> Void)?

    @StateObject private var playback: VoiceNotePlaybackController
    @State private var waveform: [Float] = []

    init(
        url: URL,
        isSending: Bool,
        sendProgress: Double?,
        isLive: Bool = false,
        foregroundColor: Color = .primary,
        onCancel: (() -> Void)?
    ) {
        self.url = url
        self.isSending = isSending
        self.sendProgress = sendProgress
        self.isLive = isLive
        self.foregroundColor = foregroundColor
        self.onCancel = onCancel
        _playback = StateObject(wrappedValue: VoiceNotePlaybackController(url: url))
    }

    private var samples: [Float] {
        waveform.isEmpty ? Array(repeating: 0.25, count: 64) : waveform
    }

    private var speedLabel: String {
        switch playback.playbackRate {
        case 1.5:
            String(localized: "media.voice.speed.one_and_half", defaultValue: "1.5x", comment: "Voice note playback speed button label")
        case 2:
            String(localized: "media.voice.speed.double", defaultValue: "2x", comment: "Voice note playback speed button label")
        default:
            String(localized: "media.voice.speed.normal", defaultValue: "1x", comment: "Voice note playback speed button label")
        }
    }

    private var timeLabel: String {
        guard playback.duration.isFinite, playback.duration > 0 else { return "--:--" }
        let seconds: Int
        if playback.isPlaying {
            seconds = playback.remainingSeconds
        } else if playback.currentTime > 0 {
            seconds = Int(playback.currentTime.rounded())
        } else {
            seconds = playback.roundedDuration
        }
        let time = String(format: "%02d:%02d", seconds / 60, seconds % 60)
        return playback.isPlaying ? "−\(time)" : time
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: playback.togglePlayback) {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.bitchatSystem(size: 15, weight: .semibold))
                    .foregroundColor(foregroundColor)
                    .frame(width: 38, height: 38)
                    .background(foregroundColor.opacity(0.16), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                playback.isPlaying
                ? String(localized: "media.voice.accessibility.pause", comment: "Accessibility label for pausing voice note playback")
                : String(localized: "media.voice.accessibility.play", comment: "Accessibility label for playing a voice note")
            )
            .accessibilityValue(timeLabel)

            WaveformView(
                samples: samples,
                playbackProgress: playback.progress,
                sendProgress: sendProgress,
                tint: foregroundColor,
                onSeek: { playback.seek(to: $0) },
                isInteractive: true
            )
            .frame(maxWidth: .infinity)
            .accessibilityElement()
            .accessibilityLabel(String(localized: "media.voice.accessibility.waveform", defaultValue: "Voice message waveform", comment: "Accessibility label for the seekable voice message waveform"))
            .accessibilityValue(timeLabel)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: playback.seek(to: playback.progress + 0.05)
                case .decrement: playback.seek(to: playback.progress - 0.05)
                @unknown default: break
                }
            }

            if isLive {
                LiveVoiceBadge()
            } else {
                Button(action: playback.cyclePlaybackRate) {
                    Text(speedLabel)
                        .bitchatFont(size: 12, weight: .semibold)
                        .foregroundColor(foregroundColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(foregroundColor.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "media.voice.accessibility.speed", defaultValue: "Playback speed", comment: "Accessibility label for the voice note playback speed button"))
                .accessibilityValue(speedLabel)
                .accessibilityHint(String(localized: "media.voice.accessibility.change_speed", defaultValue: "Changes playback speed", comment: "Accessibility hint for cycling voice note playback speeds"))
            }

            if !isLive {
                Text(timeLabel)
                    .bitchatFont(size: 12, weight: .medium)
                    .monospacedDigit()
                    .foregroundColor(foregroundColor.opacity(0.78))
                    .frame(minWidth: 42, alignment: .trailing)
                    .accessibilityHidden(true)
            }

            if let onCancel = onCancel, isSending {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.bitchatSystem(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.red.opacity(0.9)))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "media.accessibility.cancel_send", comment: "Accessibility label for the cancel button on an in-flight media send"))
            }
        }
        .padding(.vertical, 4)
        .task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            playback.loadDuration()
            await withCheckedContinuation { continuation in
                WaveformCache.shared.waveform(for: url, completion: { bins in
                    waveform = bins
                    continuation.resume()
                })
            }
        }
        .onChange(of: url) { newValue in
            WaveformCache.shared.waveform(for: newValue, completion: { bins in
                self.waveform = bins
            })
            playback.replaceURL(newValue)
        }
        .onDisappear {
            playback.stop()
        }
    }
}
