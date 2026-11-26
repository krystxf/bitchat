import SwiftUI

struct WaveformView: View {
    let samples: [Float]
    let playbackProgress: Double
    let sendProgress: Double?
    let tint: Color?
    let onSeek: ((Double) -> Void)?
    let isInteractive: Bool
    @ThemedPalette private var palette

    init(
        samples: [Float],
        playbackProgress: Double,
        sendProgress: Double?,
        tint: Color? = nil,
        onSeek: ((Double) -> Void)?,
        isInteractive: Bool
    ) {
        self.samples = samples
        self.playbackProgress = playbackProgress
        self.sendProgress = sendProgress
        self.tint = tint
        self.onSeek = onSeek
        self.isInteractive = isInteractive
    }

    private var clampedPlayback: Double {
        max(0, min(1, playbackProgress))
    }

    private var clampedSend: Double? {
        guard let sendProgress = sendProgress else { return nil }
        return max(0, min(1, sendProgress))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Canvas { context, size in
                    guard !samples.isEmpty else { return }
                    let width = max(size.width, 1)
                    let height = max(size.height, 1)
                    let barWidth = width / CGFloat(samples.count)
                    for (index, sample) in samples.enumerated() {
                        let normalized = max(0, min(sample, 1))
                        let barHeight = max(3, CGFloat(normalized) * height)
                        let originX = CGFloat(index) * barWidth
                        let rect = CGRect(
                            x: originX,
                            y: (height - barHeight) / 2,
                            width: max(barWidth * 0.58, 1),
                            height: barHeight
                        )
                        let binPosition = Double(index) / Double(samples.count)
                        let color: Color
                        if binPosition <= clampedPlayback {
                            color = tint ?? palette.accent
                        } else if let send = clampedSend, binPosition <= send {
                            color = tint ?? palette.accentBlue
                        } else {
                            color = (tint ?? palette.secondary).opacity(0.35)
                        }
                        context.fill(Path(roundedRect: rect, cornerRadius: rect.width / 2), with: .color(color))
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)

                if isInteractive, let onSeek = onSeek {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard geometry.size.width > 0 else { return }
                                    let fraction = max(0, min(1, value.location.x / geometry.size.width))
                                    onSeek(fraction)
                                }
                        )
                }
            }
        }
        .frame(height: 36)
    }
}
