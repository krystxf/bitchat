import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import AVFoundation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Placeholder view to display the user's verification QR payload as text.
struct MyQRView: View {
    let qrString: String
    @State private var copied = false
    @State private var copyResetTask: Task<Void, Never>?
    @ThemedPalette private var palette

    private enum Strings {
        static let accessibilityLabel = String(localized: "verification.my_qr.accessibility_label", comment: "Accessibility label describing the verification QR code")
        static let copied: String = String(localized: "verification.copy.copied", comment: "Confirmation shown after copying a verification URL")
        static let copy: LocalizedStringKey = "common.copy"
        static let share: LocalizedStringKey = "verification.share.action"
        static let shareShort = String(localized: "conversation_info.action.share", defaultValue: "Share", comment: "Short label of the button on a location channel's details page that shares an invite to the channel")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                QRCodeImage(data: qrString, size: Self.codeSize)
                    .accessibilityLabel(Strings.accessibilityLabel)
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)

                HStack(spacing: 12) {
                    Button(action: copyURL) {
                        Label {
                            Text(copied ? Strings.copied : String(localized: "common.copy"))
                        } icon: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(Text(verbatim: qrString))

                    ShareLink(item: qrString) {
                        // The short label fits beside Copy; VoiceOver
                        // says what is shared.
                        Label(Strings.shareShort, systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel(Text(Strings.share))
                }
                .controlSize(.large)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .frame(maxWidth: Self.codeSize)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .onDisappear { copyResetTask?.cancel() }
    }

    /// The code's side: large enough to scan from a phone held at arm's
    /// length, small enough to leave the buttons in view.
    private static let codeSize: CGFloat = 264

    private func copyURL() {
        #if os(iOS)
        UIPasteboard.general.string = qrString
        UIAccessibility.post(notification: .announcement, argument: Strings.copied)
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(qrString, forType: .string)
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [.announcement: Strings.copied])
        #endif
        copied = true
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

// Render a QR code image for a given string using CoreImage
struct QRCodeImage: View {
    let data: String
    let size: CGFloat
    @ThemedPalette private var palette

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    private enum Strings {
        static let unavailable: LocalizedStringKey = "verification.my_qr.unavailable"
    }

    var body: some View {
        Group {
            if let image = generateImage() {
                ImageWrapper(image: image)
                    // A white quiet zone around the modules, in both modes.
                    .padding(16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .frame(width: size, height: size)
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(palette.divider, lineWidth: 1)
                    .frame(width: size, height: size)
                    .overlay(
                        Label(Strings.unavailable, systemImage: "qrcode")
                            .font(.footnote)
                            .foregroundStyle(.novaSecondaryText)
                    )
            }
        }
    }

    private func generateImage() -> CGImage? {
        let inputData = Data(data.utf8)
        filter.message = inputData
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let scale = max(1, Int(size / max(outputImage.extent.width, outputImage.extent.height)))
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
        return context.createCGImage(transformed, from: transformed.extent)
    }
}

// Platform-specific wrapper to display CGImage in SwiftUI
struct ImageWrapper: View {
    let image: CGImage
    var body: some View {
        #if os(iOS)
        let ui = UIImage(cgImage: image)
        return Image(uiImage: ui)
            .interpolation(.none)
            .resizable()
        #else
        let ns = NSImage(cgImage: image, size: .zero)
        return Image(nsImage: ns)
            .interpolation(.none)
            .resizable()
        #endif
    }
}

/// Peer verification QR scanner. Uses the camera on iOS and macOS; macOS also
/// keeps a paste/validate fallback for machines without a usable camera.
struct QRScanView: View {
    @EnvironmentObject private var verificationModel: VerificationModel
    @ThemedPalette private var palette
    var isActive: Bool = true
    var onSuccess: (() -> Void)? = nil  // Called when verification succeeds
    @State private var input = ""
    @State private var result: String = ""
    @State private var lastValid: String = ""

    @State private var cameraUnavailable = false

    private enum Strings {
        static let pastePrompt: LocalizedStringKey = "verification.scan.paste_prompt"
        static let validate: LocalizedStringKey = "verification.scan.validate"
        static let cameraUnavailableTitle = String(
            localized: "verification.scan.camera_unavailable.title",
            defaultValue: "Camera Unavailable",
            comment: "Title shown over the QR scanner preview when no camera is available or permission was denied"
        )
        #if os(macOS)
        static let cameraUnavailableMessage = String(
            localized: "verification.scan.camera_unavailable.message_macos",
            defaultValue: "Paste a friend's verification link below instead.",
            comment: "Shown on Mac under 'Camera Unavailable' over the QR scanner preview; a paste field follows below it"
        )
        #else
        static let cameraUnavailableMessage = String(
            localized: "verification.scan.camera_unavailable.message",
            defaultValue: "Allow camera access in Settings to scan a friend's code.",
            comment: "Shown on iPhone under 'Camera Unavailable' over the QR scanner preview, above a button that opens Settings"
        )
        #endif
        static func requested(_ nickname: String) -> String {
            String(
                format: String(localized: "verification.scan.status.requested", comment: "Status text when verification is requested for a nickname"),
                locale: .current,
                nickname
            )
        }
        static let notFound = String(localized: "verification.scan.status.no_peer", comment: "Status when no matching peer is found for a verification request")
        static let invalid = String(localized: "verification.scan.status.invalid", comment: "Status when a scanned QR payload is invalid")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                Color.black
                CameraScannerView(isActive: isActive, onUnavailable: { cameraUnavailable = true }) { code in
                    handleScannedCode(code, announceResult: false)
                }
                if cameraUnavailable {
                    cameraUnavailableView
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 360)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .frame(maxWidth: .infinity)

            #if os(macOS)
            VStack(alignment: .leading, spacing: 8) {
                Text(Strings.pastePrompt)
                    .font(.headline)
                TextEditor(text: $input)
                    .font(.body.monospaced())
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 96)
                    .background(Color.novaSurface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.novaHairline))
                HStack {
                    if !result.isEmpty {
                        Text(result)
                            .font(.callout)
                            .foregroundStyle(.novaSecondaryText)
                    }
                    Spacer()
                    Button(Strings.validate) {
                        handleScannedCode(input, announceResult: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            #endif
        }
        .padding(.horizontal, 24)
    }

    /// No camera, or no permission to use it: what to do instead, in the
    /// dark viewfinder.
    private var cameraUnavailableView: some View {
        VStack(spacing: 10) {
            Image(systemName: "video.slash.fill")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.7))
            Text(Strings.cameraUnavailableTitle)
                .font(.headline)
            Text(Strings.cameraUnavailableMessage)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            #if os(iOS)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("location_channels.action.open_settings")
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .padding(.top, 4)
            #endif
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(24)
        .environment(\.colorScheme, .dark)
    }

    private func handleScannedCode(_ code: String, announceResult: Bool) {
        guard code != lastValid else {
            if announceResult {
                result = Strings.requested("")
            }
            return
        }

        switch verificationModel.verifyScannedPayload(code) {
        case .requested(let nickname):
            lastValid = code
            if announceResult {
                result = Strings.requested(nickname)
            }
            onSuccess?()
        case .notFound:
            if announceResult {
                result = Strings.notFound
            }
        case .invalid:
            if announceResult {
                result = Strings.invalid
            }
        }
    }
}

#if os(iOS)
struct CameraScannerView: UIViewRepresentable {
    typealias UIViewType = PreviewView
    var isActive: Bool
    var onUnavailable: (() -> Void)? = nil
    var onCode: (String) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        context.coordinator.setup(
            previewLayer: view.videoPreviewLayer,
            onCode: onCode,
            onUnavailable: onUnavailable
        )
        context.coordinator.setActive(isActive)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.setActive(isActive)
    }

    static func dismantleUIView(_ uiView: PreviewView, coordinator: CameraScannerCoordinator) {
        coordinator.setActive(false)
    }

    func makeCoordinator() -> CameraScannerCoordinator { CameraScannerCoordinator() }

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        override init(frame: CGRect) {
            super.init(frame: frame)
            videoPreviewLayer.videoGravity = .resizeAspectFill
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }
}
#elseif os(macOS)
struct CameraScannerView: NSViewRepresentable {
    typealias NSViewType = PreviewView
    var isActive: Bool
    var onUnavailable: (() -> Void)? = nil
    var onCode: (String) -> Void

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        context.coordinator.setup(
            previewLayer: view.videoPreviewLayer,
            onCode: onCode,
            onUnavailable: onUnavailable
        )
        context.coordinator.setActive(isActive)
        return view
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {
        context.coordinator.setActive(isActive)
    }

    static func dismantleNSView(_ nsView: PreviewView, coordinator: CameraScannerCoordinator) {
        coordinator.setActive(false)
    }

    func makeCoordinator() -> CameraScannerCoordinator { CameraScannerCoordinator() }

    final class PreviewView: NSView {
        let videoPreviewLayer = AVCaptureVideoPreviewLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            videoPreviewLayer.videoGravity = .resizeAspectFill
            layer = CALayer()
            layer?.addSublayer(videoPreviewLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            super.layout()
            videoPreviewLayer.frame = bounds
        }
    }
}
#endif

final class CameraScannerCoordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    private var onCode: ((String) -> Void)?
    private var onUnavailable: (() -> Void)?
    private let session = AVCaptureSession()
    private var isRunning = false
    private var permissionGranted = false
    private var desiredActive = false
    private var didConfigureSession = false
    private weak var previewLayer: AVCaptureVideoPreviewLayer?

    func setup(
        previewLayer: AVCaptureVideoPreviewLayer,
        onCode: @escaping (String) -> Void,
        onUnavailable: (() -> Void)? = nil
    ) {
        self.onCode = onCode
        self.onUnavailable = onUnavailable
        self.previewLayer = previewLayer
        previewLayer.session = session

        // Check authorization before creating AVCaptureDeviceInput so tests and
        // cold launches do not trigger a TCC prompt just by constructing input.
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
            if !configureSessionIfNeeded() {
                reportUnavailable()
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.permissionGranted = granted
                    if granted {
                        if !self.configureSessionIfNeeded() {
                            self.reportUnavailable()
                            return
                        }
                        if self.desiredActive && !self.isRunning {
                            self.setActive(true)
                        }
                    } else {
                        self.reportUnavailable()
                    }
                }
            }
        default:
            permissionGranted = false
            reportUnavailable()
        }
    }

    @discardableResult
    private func configureSessionIfNeeded() -> Bool {
        guard !didConfigureSession else { return true }
        session.beginConfiguration()
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return false
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        if output.availableMetadataObjectTypes.contains(.qr) {
            output.metadataObjectTypes = [.qr]
        }
        session.commitConfiguration()
        previewLayer?.session = session
        didConfigureSession = true
        return true
    }

    private func reportUnavailable() {
        DispatchQueue.main.async {
            self.onUnavailable?()
        }
    }

    func setActive(_ active: Bool) {
        desiredActive = active
        guard permissionGranted, didConfigureSession else { return }
        if active && !isRunning {
            isRunning = true
            DispatchQueue.global(qos: .userInitiated).async {
                if !self.session.isRunning { self.session.startRunning() }
            }
        } else if !active && isRunning {
            isRunning = false
            DispatchQueue.global(qos: .userInitiated).async {
                if self.session.isRunning { self.session.stopRunning() }
            }
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        for obj in metadataObjects {
            guard let m = obj as? AVMetadataMachineReadableCodeObject,
                  m.type == .qr,
                  let str = m.stringValue else { continue }
            onCode?(str)
        }
    }
}

// Combined sheet: switch inline between the personal QR code and scanner.
struct VerificationSheetView: View {
    @EnvironmentObject private var verificationModel: VerificationModel
    @Binding var isPresented: Bool
    @State private var showingScanner = false
    private enum Page: Hashable { case myCode, scan }

    var body: some View {
        sheetContent
            .sheetChrome(
                title: Text(verbatim: title),
                onClose: {
                    // Stop the camera before the sheet animates away.
                    showingScanner = false
                    isPresented = false
                },
                // A segmented control in the title slot, as in the system
                // apps; it replaces the title on screen.
                principal: { pagePicker }
            )
            .onDisappear { showingScanner = false }
            #if os(macOS)
            .frame(minWidth: 460, idealWidth: 480, minHeight: 600, idealHeight: 640)
            #endif
    }

    /// Sheet title supplied with standard capitalization by the catalog.
    private var title: String {
        String(localized: "verification.sheet.title")
    }

    private var pagePicker: some View {
        Picker("verification.sheet.title", selection: Binding(
            get: { showingScanner ? Page.scan : Page.myCode },
            set: { showingScanner = $0 == .scan }
        )) {
            Text("verification.sheet.my_code").tag(Page.myCode)
            Text("verification.sheet.scan").tag(Page.scan)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel(Text("verification.sheet.title"))
    }

    private var sheetContent: some View {
        VStack(spacing: 16) {
            Group {
                if showingScanner {
                    VStack(spacing: 12) {
                        QRScanView(isActive: showingScanner, onSuccess: {
                            showingScanner = false
                        })
                        .environmentObject(verificationModel)
                        Text("verification.scan.prompt_friend")
                            .font(.subheadline)
                            .foregroundStyle(.novaSecondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 16)
                } else {
                    MyQRView(qrString: verificationModel.myQRString())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if let peerID = verificationModel.selectedPeerID,
               verificationModel.isVerified(peerID: peerID) {
                Button(role: .destructive) {
                    verificationModel.unverifyFingerprint(for: peerID)
                } label: {
                    Label("fingerprint.action.remove_verification", systemImage: "xmark.seal")
                }
                .buttonStyle(.bordered)
                .padding(.bottom, 16)
            }
        }
    }
}
