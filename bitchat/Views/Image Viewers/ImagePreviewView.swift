//
// ImagePreviewView.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI
#if os(macOS)
import AppKit
import BitLogger
#else
import UIKit
#endif

/// Full-size image viewer: the image fills the sheet and zooms with pinch,
/// double-tap/double-click and (on macOS) the trackpad. Close sits top right
/// and save floats at the bottom as a tinted glass button.
///
/// A file from the GIF cache plays instead, looping and muted, without zoom.
struct ImagePreviewView: View {
    let url: URL
    /// Set when the file is a cached Giphy or Tenor GIF.
    private let gifAsset: GifAsset?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playsDespiteReduceMotion = false
    #if os(iOS)
    @State private var showExporter = false
    @State private var platformImage: UIImage?
    #else
    @State private var platformImage: NSImage?
    #endif

    init(url: URL) {
        self.url = url
        self.gifAsset = GifMediaStore.shared.asset(forFileURL: url)
    }

    var body: some View {
        ZStack {
            if let gifAsset {
                gifPlayer(gifAsset)
            } else if let image = platformImage {
                ZoomableImage(image: image)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            closeButton
                .padding(16)
        }
        .overlay(alignment: .bottom) {
            saveButton
                .padding(.bottom, 20)
        }
        #if os(macOS)
        .frame(minWidth: 640, idealWidth: 900, minHeight: 480, idealHeight: 680)
        #endif
        .onAppear(perform: loadImage)
        #if os(iOS)
        .sheet(isPresented: $showExporter) {
            FileExportWrapper(url: url)
        }
        #endif
    }

    private var closeButton: some View {
        Button(action: { dismiss() }) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 24, height: 24)
        }
        .glassButtonStyle()
        .circularButtonShape()
        .controlSize(.large)
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel(Text("close", comment: "Button to dismiss fullscreen media viewer"))
    }

    private var saveButton: some View {
        Button(action: saveCopy) {
            Label {
                Text("save", comment: "Button to save media to device")
            } icon: {
                Image(systemName: "square.and.arrow.down")
            }
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 6)
        }
        .glassButtonStyle(prominent: true)
        .controlSize(.large)
        .tint(.blue)
        .disabled(platformImage == nil && gifAsset == nil)
    }

    /// The GIF at its own shape, fitted to the sheet. Under Reduce Motion it
    /// holds the first frame until the play button is pressed.
    private func gifPlayer(_ asset: GifAsset) -> some View {
        GifPlaybackView(asset: asset, isPlaying: !reduceMotion || playsDespiteReduceMotion)
            .aspectRatio(GifMessageView.displayAspectRatio(asset.aspectRatio), contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 64)
            .overlay {
                if reduceMotion && !playsDespiteReduceMotion {
                    Button {
                        playsDespiteReduceMotion = true
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .frame(width: 32, height: 32)
                    }
                    .glassButtonStyle()
                    .circularButtonShape()
                    .controlSize(.large)
                    .accessibilityLabel(Text(verbatim: String(localized: "media.gif.accessibility.play", comment: "Button that plays a GIF held still by Reduce Motion")))
                }
            }
    }

    private func loadImage() {
        guard gifAsset == nil else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            #if os(iOS)
            guard let image = UIImage(contentsOfFile: url.path) else { return }
            #else
            guard let image = NSImage(contentsOf: url) else { return }
            #endif
            DispatchQueue.main.async {
                self.platformImage = image
            }
        }
    }

    private func saveCopy() {
        #if os(iOS)
        showExporter = true
        #else
        Task { @MainActor in
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            // Cached GIFs are named by a hash; offer a readable name.
            panel.nameFieldStringValue = gifAsset.map { "GIF.\($0.format.fileExtension)" } ?? url.lastPathComponent
            panel.prompt = "save"
            if panel.runModal() == .OK, let destination = panel.url {
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: url, to: destination)
                } catch {
                    SecureLogger.error("Failed to save image preview copy: \(error)", category: .session)
                }
            }
        }
        #endif
    }

    #if os(iOS)
    private struct FileExportWrapper: UIViewControllerRepresentable {
        let url: URL

        func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
            let controller = UIDocumentPickerViewController(forExporting: [url])
            controller.shouldShowFileExtensions = true
            return controller
        }

        func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    }
    #endif
}

// MARK: - Zoomable image

#if os(iOS)
/// A UIScrollView-backed image view: pinch to zoom, pan while zoomed,
/// double-tap to toggle zoom, with the system's bounce and deceleration.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ZoomableImageScrollView {
        ZoomableImageScrollView(image: image)
    }

    func updateUIView(_ view: ZoomableImageScrollView, context: Context) {
        view.setImage(image)
    }
}

private final class ZoomableImageScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var laidOutSize: CGSize = .zero

    init(image: UIImage) {
        super.init(frame: .zero)
        delegate = self
        backgroundColor = .clear
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        bouncesZoom = true

        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setImage(_ image: UIImage) {
        guard imageView.image !== image else { return }
        imageView.image = image
        laidOutSize = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Refit only when the viewport changes (rotation, sheet resize);
        // layout passes during a zoom must not reset it.
        guard bounds.size != laidOutSize else { return }
        laidOutSize = bounds.size
        fitImage()
    }

    /// Sizes the image view to aspect-fit the viewport at zoom scale 1.
    private func fitImage() {
        guard let image = imageView.image,
              image.size.width > 0, image.size.height > 0,
              bounds.width > 0, bounds.height > 0 else { return }
        zoomScale = 1
        let fitScale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let fitted = CGSize(width: image.size.width * fitScale, height: image.size.height * fitScale)
        imageView.frame = CGRect(origin: .zero, size: fitted)
        contentSize = fitted
        minimumZoomScale = 1
        // At least 4x, and far enough to reach the image's own pixels.
        maximumZoomScale = min(max(4, 1 / fitScale), 12)
        centerImage()
    }

    /// Keeps the image centered while it is smaller than the viewport.
    private func centerImage() {
        let insetX = max(0, (bounds.width - contentSize.width) / 2)
        let insetY = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
            return
        }
        let target = min(maximumZoomScale, 2.5)
        let point = gesture.location(in: imageView)
        let size = CGSize(width: bounds.width / target, height: bounds.height / target)
        let rect = CGRect(
            x: point.x - size.width / 2,
            y: point.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        zoom(to: rect, animated: true)
    }
}
#else
/// An NSScrollView with magnification: pinch on the trackpad, scroll to pan
/// while zoomed, double-click to toggle zoom.
private struct ZoomableImage: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> ZoomableImageScrollView {
        ZoomableImageScrollView(image: image)
    }

    func updateNSView(_ view: ZoomableImageScrollView, context: Context) {
        view.setImage(image)
    }
}

private final class ZoomableImageScrollView: NSScrollView {
    private let imageView = NSImageView()

    init(image: NSImage) {
        super.init(frame: .zero)
        drawsBackground = false
        contentView.drawsBackground = false
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        allowsMagnification = true
        minMagnification = 1
        maxMagnification = 8

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.isEditable = false
        documentView = imageView

        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
        doubleClick.numberOfClicksRequired = 2
        addGestureRecognizer(doubleClick)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setImage(_ image: NSImage) {
        guard imageView.image !== image else { return }
        imageView.image = image
    }

    override func layout() {
        super.layout()
        // At magnification 1 the document is exactly the viewport, so the
        // image aspect-fits; zooming scales that whole document.
        let viewport = contentSize
        if imageView.frame.size != viewport, magnification <= minMagnification {
            imageView.frame = CGRect(origin: .zero, size: viewport)
        }
    }

    @objc private func handleDoubleClick(_ gesture: NSClickGestureRecognizer) {
        if magnification > minMagnification {
            animator().magnification = minMagnification
        } else {
            let point = gesture.location(in: imageView)
            animator().setMagnification(2.5, centeredAt: point)
        }
    }
}
#endif

#Preview {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("dummy.jpg")
    if !FileManager.default.fileExists(atPath: tempURL.path(percentEncoded: false)) {
        #if os(iOS)
        let image = UIImage(named: "dummy")
        let data = image?.jpegData(compressionQuality: 0.8)
        let _ = try? data?.write(to: tempURL)
        #elseif os(macOS)
        let image = NSImage(named: "dummy")
        var rect = NSRect(origin: .zero, size: image?.size ?? .zero)
        if let cgImage = image?.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            let rep = NSBitmapImageRep(cgImage: cgImage)
            let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
            let _ = try? jpegData?.write(to: tempURL)
        }
        #endif
    }
    ImagePreviewView(url: tempURL)
}
