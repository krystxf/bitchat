//
// VoiceRecordingViewModel.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitLogger
import CoreGraphics
import Foundation

@MainActor
final class VoiceRecordingViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case requestingPermission
        case permissionDenied
        case preparing
        case recording(startDate: Date)
        case error(message: String)

        var isActive: Bool {
            switch self {
            case .preparing, .recording: true
            case .idle, .requestingPermission, .permissionDenied, .error: false
            }
        }

        var alertMessage: String {
            switch self {
            case .error(let message): message
            case .permissionDenied: String(localized: "voice.error.mic_permission", defaultValue: "Microphone access is required to record voice notes.", comment: "Alert message when the microphone permission is denied")
            case .idle, .requestingPermission, .preparing, .recording: ""
            }
        }

        fileprivate func duration(for date: Date) -> TimeInterval {
            switch self {
            case .idle, .requestingPermission, .preparing, .permissionDenied, .error: 0
            case .recording(let startDate): date.timeIntervalSince(startDate)
            }
        }
    }

    var showAlert: Bool {
        get {
            switch state {
            case .permissionDenied, .error:   true
            case .idle, .requestingPermission, .preparing, .recording: false
            }
        }
        set {
            if !newValue { state = .idle }
        }
    }

    @Published private(set) var state = State.idle {
        didSet {
            // Permission denied, an error, panic or a deferred start ended
            // the recording underneath the finger: drop the gesture too.
            if !state.isActive, state != .requestingPermission {
                gesture.reset()
                syncGesturePhase()
            }
        }
    }
    /// True while the active session streams audio live (push-to-talk); the
    /// composer switches its recording HUD to the LIVE treatment.
    @Published private(set) var isLiveStreaming = false

    /// Input levels for the recording bar's live waveform. A separate
    /// object so its display-rate updates reach only the waveform view, not
    /// every view observing this model.
    let levelMeter = VoiceLevelMeter()
    /// How often the waveform polls the capture backend.
    static let levelSampleInterval: Duration = .milliseconds(40)
    private var levelSampling: Task<Void, Never>?

    /// The longest recording. Both capture backends stop here, so the
    /// recording sends itself instead of counting time it does not record.
    var timeLimit: TimeInterval = VoiceRecorder.maxRecordingDuration
    /// Sends a recording that reached `timeLimit`. The chat screen sets it.
    /// Without it, a recording at the limit is discarded.
    var sendAtTimeLimit: ((URL) -> Void)?
    private var timeLimitTask: Task<Void, Never>?

    /// Supplies the capture backend per press. `ChatViewModel` swaps in a
    /// live push-to-talk session when the current DM peer can hear it now.
    var sessionProvider: () -> VoiceCaptureSession = { VoiceNoteCaptureSession() }
    private var activeSession: VoiceCaptureSession?
    /// Monotonic press identity. A slow permission/start/finalize task from an
    /// older hold may still deliver its file, but it must never mutate the UI
    /// state of a newer hold.
    private var holdGeneration: UInt64 = 0

    // MARK: - Hold-to-record gesture

    /// Phase of the mic gesture. Published only when the phase changes; the
    /// drag translation itself stays in the composer so the chat screen
    /// does not re-render on every finger move.
    @Published private(set) var gesturePhase: VoiceRecordGesture.Phase = .idle
    /// True for a moment after a recording is discarded, while the
    /// recording bar plays its trash animation.
    @Published private(set) var isDiscarding = false
    /// A press released before recording began: the composer briefly
    /// explains how the mic works.
    @Published private(set) var showsHoldHint = false

    static let discardAnimationDuration: Duration = .milliseconds(550)
    static let holdHintDuration: Duration = .seconds(2)

    private var gesture = VoiceRecordGesture()
    /// One touch sequence on the mic, from the first drag event to release.
    private var touchActive = false
    private var discardTask: Task<Void, Never>?
    private var holdHintTask: Task<Void, Never>?

    var gestureThresholds: VoiceRecordGesture.Thresholds { gesture.thresholds }

    /// Elapsed recording time as "m:ss", for the recording bar.
    func formattedElapsed(for date: Date) -> String {
        let totalSeconds = Int(max(0, state.duration(for: date)))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    /// Finger down or moved on the mic. The first event of a touch starts
    /// recording; later ones update the lock and cancel thresholds.
    /// Returns true when the drag crossed into or out of an armed phase.
    @discardableResult
    func pressChanged(translation: CGSize, canRecord: Bool) -> Bool {
        guard touchActive else {
            touchActive = true
            guard canRecord, state == .idle, gesture.press() == .start else { return false }
            clearTransientFeedback()
            syncGesturePhase()
            start(shouldShow: true)
            return false
        }
        let crossed = gesture.drag(to: translation)
        if crossed {
            syncGesturePhase()
        }
        return crossed
    }

    /// Finger lifted from the mic: send, lock hands free, or discard.
    func pressEnded(completion: @escaping (URL) -> Void) {
        guard touchActive else { return }
        touchActive = false
        let action = gesture.release()
        syncGesturePhase()
        switch action {
        case .send:
            if case .recording = state {} else {
                // Released before the recorder spun up: a tap, not a hold.
                flashHoldHint()
            }
            finish(completion: completion)
        case .cancel:
            discardRecording()
        case .lock, .start, .none:
            break
        }
    }

    /// The touch ended without a release (the system cancelled the
    /// gesture). Safe to call after `pressEnded`; it then does nothing.
    func pressInterrupted() {
        guard touchActive else { return }
        touchActive = false
        _ = gesture.interrupt()
        syncGesturePhase()
    }

    /// Starts a hands-free recording without holding, for VoiceOver and
    /// other assistive input that cannot press and drag.
    func startHandsFree(canRecord: Bool) {
        guard canRecord, state == .idle, gesture.startHandsFree() == .start else { return }
        clearTransientFeedback()
        syncGesturePhase()
        start(shouldShow: true)
    }

    /// The send button of a hands-free recording.
    func sendHandsFree(completion: @escaping (URL) -> Void) {
        guard gesture.send() == .send else { return }
        syncGesturePhase()
        finish(completion: completion)
    }

    /// The trash button, or a release past the cancel threshold: discards
    /// the recording and plays the trash animation.
    func discardRecording() {
        _ = gesture.cancel()
        syncGesturePhase()
        let hadRecording = state.isActive || state == .requestingPermission
        cancel()
        guard hadRecording else { return }
        isDiscarding = true
        discardTask?.cancel()
        discardTask = Task { [weak self] in
            try? await Task.sleep(for: Self.discardAnimationDuration)
            guard !Task.isCancelled else { return }
            self?.isDiscarding = false
        }
    }

    private func flashHoldHint() {
        showsHoldHint = true
        holdHintTask?.cancel()
        holdHintTask = Task { [weak self] in
            try? await Task.sleep(for: Self.holdHintDuration)
            guard !Task.isCancelled else { return }
            self?.showsHoldHint = false
        }
    }

    private func clearTransientFeedback() {
        discardTask?.cancel()
        holdHintTask?.cancel()
        if isDiscarding { isDiscarding = false }
        if showsHoldHint { showsHoldHint = false }
    }

    private func syncGesturePhase() {
        if gesturePhase != gesture.phase {
            gesturePhase = gesture.phase
        }
    }

    func start(shouldShow: Bool) {
        guard shouldShow, state == .idle else { return }
        holdGeneration &+= 1
        let generation = holdGeneration
        let session = sessionProvider()
        SecureLogger.info("PTT: mic hold began (backend: \(session.isLive ? "live" : "classic"))", category: .session)
        activeSession = session
        levelMeter.reset()
        state = .requestingPermission
        Task {
            let granted = await session.requestPermission()
            guard generation == holdGeneration,
                  state == .requestingPermission,
                  activeSession === session
            else { return }
            guard granted else {
                state = .permissionDenied
                activeSession = nil
                return
            }
            state = .preparing
            do {
                try await session.start()
                guard generation == holdGeneration,
                      state == .preparing,
                      activeSession === session
                else {
                    await session.cancel()
                    return
                }
                state = .recording(startDate: Date())
                isLiveStreaming = session.isLive
                startLevelSampling(from: session)
                startTimeLimit(for: generation)
            } catch VoiceRecorder.RecorderError.recordingInProgress {
                // The previous classic hold may still be in its intentional
                // finalize-padding window. This press owns no recorder, so
                // its owner-scoped cancel is harmless; return to idle instead
                // of surfacing a false capture failure while the prior note
                // finishes and delivers normally.
                SecureLogger.info("Voice recording start deferred while the previous hold finalizes", category: .session)
                await session.cancel()
                guard generation == holdGeneration,
                      state == .preparing,
                      activeSession === session
                else { return }
                activeSession = nil
                state = .idle
            } catch {
                SecureLogger.error("Voice recording failed to start: \(error)", category: .session)
                await session.cancel()
                guard generation == holdGeneration,
                      state == .preparing,
                      activeSession === session
                else { return }
                // The live engine and the classic recorder are separate
                // capture stacks: when the live one hits an audio-route
                // glitch, fall back within the same hold so the user still
                // gets a voice note instead of an error.
                if session.isLive {
                    let fallback = VoiceNoteCaptureSession()
                    activeSession = fallback
                    do {
                        try await fallback.start()
                        guard generation == holdGeneration,
                              state == .preparing,
                              activeSession === fallback
                        else {
                            await fallback.cancel()
                            return
                        }
                        SecureLogger.warning("PTT: live capture failed — fell back to classic voice note", category: .session)
                        state = .recording(startDate: Date())
                        isLiveStreaming = false
                        startLevelSampling(from: fallback)
                        startTimeLimit(for: generation)
                        return
                    } catch {
                        SecureLogger.error("Voice recording fallback failed to start: \(error)", category: .session)
                        await fallback.cancel()
                        guard generation == holdGeneration, state == .preparing else { return }
                    }
                }
                activeSession = nil
                state = .error(message: String(localized: "voice.error.start_failed", defaultValue: "Could not start recording.", comment: "Alert message when the recorder fails to start"))
            }
        }
    }

    func finish(completion: ((URL) -> Void)?) {
        let previousState = state

        switch previousState {
        case .permissionDenied, .error:
            return
        case .idle, .requestingPermission, .preparing, .recording:
            break
        }

        state = .idle
        isLiveStreaming = false
        stopLevelSampling()
        stopTimeLimit()
        let session = activeSession
        let generation = holdGeneration
        activeSession = nil

        guard case .recording(let startDate) = previousState, let completion, let session else {
            // A quick press releases before the recorder spins up; that has
            // always been a silent no-op for voice notes — log it so field
            // tests can tell "tapped" apart from "capture broke".
            SecureLogger.info("PTT: mic released before recording started (state was \(previousState)) — hold longer to record", category: .session)
            Task { await session?.cancel() }
            return
        }

        Task {
            let finalDuration = Date().timeIntervalSince(startDate)
            if let url = await session.finish() {
                // Panic and a newer hold both invalidate this completion.
                // Never route an old recording using a post-panic target.
                guard generation == holdGeneration else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                guard isValidRecording(
                    at: url,
                    duration: finalDuration
                ) else {
                    guard state == .idle else { return }
                    state = .error(
                        message: finalDuration < VoiceRecorder.minRecordingDuration
                        ? String(localized: "voice.error.too_short", defaultValue: "Recording is too short.", comment: "Alert message when a voice note is released too quickly to save")
                        : String(localized: "voice.error.save_failed", defaultValue: "Recording failed to save.", comment: "Alert message when a finished voice note cannot be saved")
                    )
                    return
                }
                completion(url)
            } else {
                guard generation == holdGeneration, state == .idle else { return }
                state = .error(
                    message: finalDuration < VoiceRecorder.minRecordingDuration
                    ? String(localized: "voice.error.too_short", defaultValue: "Recording is too short.", comment: "Alert message when a voice note is released too quickly to save")
                    : String(localized: "voice.error.save_failed", defaultValue: "Recording failed to save.", comment: "Alert message when a finished voice note cannot be saved")
                )
            }
        }
    }

    func cancel() {
        finish(completion: nil)
    }

    /// Invalidates in-flight permission/start/finalize callbacks and tears
    /// down an active microphone before the panic transaction continues.
    func panicWipe() {
        holdGeneration &+= 1
        stopLevelSampling()
        stopTimeLimit()
        touchActive = false
        clearTransientFeedback()
        let session = activeSession
        activeSession = nil
        state = .idle
        isLiveStreaming = false
        session?.panicCancelSynchronously()
    }

    /// Polls the session's input level for the waveform until the hold
    /// ends. The last levels stay in the meter so the bar can animate them
    /// away; the next press clears them.
    private func startLevelSampling(from session: VoiceCaptureSession) {
        levelSampling?.cancel()
        levelSampling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.activeSession === session else { return }
                let levels = await session.drainInputLevels()
                guard !Task.isCancelled, self.activeSession === session else { return }
                self.levelMeter.ingest(decibels: levels)
                try? await Task.sleep(for: Self.levelSampleInterval)
            }
        }
    }

    private func stopLevelSampling() {
        levelSampling?.cancel()
        levelSampling = nil
    }

    /// Sends the recording when it reaches `timeLimit`, held or hands free.
    /// A finger still on the mic then lifts onto an idle gesture, which
    /// does nothing.
    private func startTimeLimit(for generation: UInt64) {
        timeLimitTask?.cancel()
        let limit = timeLimit
        timeLimitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(limit))
            guard !Task.isCancelled,
                  let self,
                  generation == self.holdGeneration,
                  case .recording = self.state
            else { return }
            SecureLogger.info("Voice recording reached its time limit; sending it", category: .session)
            self.finish(completion: self.sendAtTimeLimit)
        }
    }

    private func stopTimeLimit() {
        timeLimitTask?.cancel()
        timeLimitTask = nil
    }

    private func isValidRecording(at url: URL, duration: TimeInterval) -> Bool {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileSize = attributes[.size] as? NSNumber,
           fileSize.intValue > 0,
           duration >= VoiceRecorder.minRecordingDuration {
            return true
        }
        try? FileManager.default.removeItem(at: url)
        return false
    }
}
