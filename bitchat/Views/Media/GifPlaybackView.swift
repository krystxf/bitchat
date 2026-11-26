//
// GifPlaybackView.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import AVFoundation
import QuartzCore
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Plays a cached GIF, muted and looping: MP4 through AVPlayer, GIF and
/// WebP as frames decoded by `GifFrameDecoder`. With `isPlaying` false it
/// holds the first frame. It fills its frame (aspect fill), so the caller
/// sizes it to the GIF's aspect ratio.
struct GifPlaybackView: View {
    let asset: GifAsset
    let isPlaying: Bool
    /// How large GIF and WebP frames decode; MP4 plays as it is.
    let profile: GifDecodeProfile

    @State private var frames: GifFrames?
    @State private var decodeFailed = false

    init(asset: GifAsset, isPlaying: Bool, profile: GifDecodeProfile = .message) {
        self.asset = asset
        self.isPlaying = isPlaying
        self.profile = profile
        _frames = State(initialValue: asset.format.isVideo ? nil : GifFrameCache.cachedFrames(for: asset.fileURL, profile: profile))
    }

    var body: some View {
        if asset.format.isVideo {
            GifVideoLayerView(url: asset.fileURL, isPlaying: isPlaying)
                .allowsHitTesting(false)
        } else if let frames {
            GifFramesLayerView(frames: frames, isPlaying: isPlaying)
                .allowsHitTesting(false)
        } else {
            Color.clear
                .overlay {
                    if decodeFailed {
                        Image(systemName: "photo")
                            .font(.title2.weight(.semibold))
                            .foregroundColor(.secondary)
                    } else {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                }
                .task(id: asset.fileURL) {
                    let url = asset.fileURL
                    let profile = profile
                    // Decoding every frame takes a moment: keep it off the
                    // main thread.
                    let decoded = await Task.detached(priority: .userInitiated) {
                        GifFrameCache.loadFrames(for: url, profile: profile)
                    }.value
                    guard !Task.isCancelled else { return }
                    frames = decoded
                    decodeFailed = decoded == nil
                }
        }
    }
}

// MARK: - MP4

/// One muted, looping player per row. It never keeps the display awake.
private final class GifVideoLooper {
    let player: AVQueuePlayer = {
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.automaticallyWaitsToMinimizeStalling = false
        return player
    }()
    private var looper: AVPlayerLooper?
    private var url: URL?

    func load(_ url: URL) {
        guard url != self.url else { return }
        self.url = url
        looper?.disableLooping()
        player.removeAllItems()
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
    }

    func setPlaying(_ playing: Bool) {
        if playing {
            if player.rate == 0 { player.play() }
        } else if player.rate != 0 {
            player.pause()
        }
    }

    func stop() {
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        url = nil
    }
}

#if os(iOS)
private struct GifVideoLayerView: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool

    func makeUIView(context: Context) -> GifVideoUIView {
        GifVideoUIView()
    }

    func updateUIView(_ view: GifVideoUIView, context: Context) {
        view.looper.load(url)
        view.looper.setPlaying(isPlaying)
    }

    static func dismantleUIView(_ view: GifVideoUIView, coordinator: ()) {
        view.looper.stop()
    }
}

private final class GifVideoUIView: UIView {
    let looper = GifVideoLooper()

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        if let playerLayer = layer as? AVPlayerLayer {
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.player = looper.player
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#else
private struct GifVideoLayerView: NSViewRepresentable {
    let url: URL
    let isPlaying: Bool

    func makeNSView(context: Context) -> GifVideoNSView {
        GifVideoNSView()
    }

    func updateNSView(_ view: GifVideoNSView, context: Context) {
        view.looper.load(url)
        view.looper.setPlaying(isPlaying)
    }

    static func dismantleNSView(_ view: GifVideoNSView, coordinator: ()) {
        view.looper.stop()
    }
}

private final class GifVideoNSView: NSView {
    let looper = GifVideoLooper()

    init() {
        super.init(frame: .zero)
        // A layer-hosting view: AppKit leaves the player layer alone.
        let playerLayer = AVPlayerLayer(player: looper.player)
        playerLayer.videoGravity = .resizeAspectFill
        layer = playerLayer
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
#endif

// MARK: - GIF and WebP frames

/// Shows decoded frames on a layer, animated by Core Animation with each
/// frame's own delay, so playback costs no main-thread work per frame.
private final class GifFramesAnimator {
    private static let animationKey = "gif-frames"
    let layer: CALayer
    private var frames: GifFrames?
    private var isPlaying = false

    init(layer: CALayer) {
        self.layer = layer
        layer.contentsGravity = .resizeAspectFill
        layer.masksToBounds = true
    }

    func update(frames: GifFrames, isPlaying: Bool) {
        if frames !== self.frames {
            self.frames = frames
            self.isPlaying = false
            layer.removeAnimation(forKey: Self.animationKey)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.contents = frames.images.first
            CATransaction.commit()
        }
        guard isPlaying != self.isPlaying else { return }
        self.isPlaying = isPlaying
        if isPlaying, frames.images.count > 1, frames.duration > 0 {
            layer.add(Self.animation(for: frames), forKey: Self.animationKey)
        } else {
            layer.removeAnimation(forKey: Self.animationKey)
        }
    }

    private static func animation(for frames: GifFrames) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames.images
        // Discrete mode takes one more key time than values: each frame
        // starts at its time and holds until the next.
        let total = frames.duration
        var start = 0.0
        var keyTimes: [NSNumber] = []
        for delay in frames.delays {
            keyTimes.append(NSNumber(value: start / total))
            start += delay
        }
        keyTimes.append(1)
        animation.keyTimes = keyTimes
        animation.calculationMode = .discrete
        animation.duration = total
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        return animation
    }
}

#if os(iOS)
private struct GifFramesLayerView: UIViewRepresentable {
    let frames: GifFrames
    let isPlaying: Bool

    func makeUIView(context: Context) -> GifFramesUIView {
        GifFramesUIView()
    }

    func updateUIView(_ view: GifFramesUIView, context: Context) {
        view.animator.update(frames: frames, isPlaying: isPlaying)
    }
}

private final class GifFramesUIView: UIView {
    private(set) lazy var animator = GifFramesAnimator(layer: layer)

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        // UIKit sets the layer's gravity from the content mode; keep them
        // in agreement.
        contentMode = .scaleAspectFill
        clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#else
private struct GifFramesLayerView: NSViewRepresentable {
    let frames: GifFrames
    let isPlaying: Bool

    func makeNSView(context: Context) -> GifFramesNSView {
        GifFramesNSView()
    }

    func updateNSView(_ view: GifFramesNSView, context: Context) {
        view.animator.update(frames: frames, isPlaying: isPlaying)
    }
}

private final class GifFramesNSView: NSView {
    let animator: GifFramesAnimator

    init() {
        let hosted = CALayer()
        animator = GifFramesAnimator(layer: hosted)
        super.init(frame: .zero)
        // A layer-hosting view: AppKit never redraws over the frames.
        layer = hosted
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
#endif
