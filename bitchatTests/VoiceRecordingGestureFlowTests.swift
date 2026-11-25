//
// VoiceRecordingGestureFlowTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import CoreGraphics
import Foundation
import Testing
@testable import bitchat

@MainActor
private final class InstantVoiceCaptureSession: VoiceCaptureSession {
    let isLive = false
    var permissionGranted = true
    var pendingLevels: [Float] = []
    private(set) var finishCount = 0
    private(set) var cancelCount = 0

    func requestPermission() async -> Bool { permissionGranted }
    func start() async throws {}

    func finish() async -> URL? {
        finishCount += 1
        return nil
    }

    func cancel() async {
        cancelCount += 1
    }

    func panicCancelSynchronously() {}

    func drainInputLevels() async -> [Float] {
        defer { pendingLevels.removeAll() }
        return pendingLevels
    }
}

/// The composer's mic gesture as the view model sees it: press, drag and
/// release events in, recorder calls and published phases out.
@MainActor
struct VoiceRecordingGestureFlowTests {
    private let session = InstantVoiceCaptureSession()
    private let viewModel = VoiceRecordingViewModel()

    init() {
        let session = session
        viewModel.sessionProvider = { session }
    }

    private func waitUntil(
        _ condition: () -> Bool,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(TestConstants.settleTimeout))
        while !condition(), ContinuousClock.now < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(condition(), sourceLocation: sourceLocation)
    }

    private var isRecording: Bool {
        if case .recording = viewModel.state { return true }
        return false
    }

    private func beginHold() async {
        viewModel.pressChanged(translation: .zero, canRecord: true)
        await waitUntil { isRecording }
    }

    @Test func holdThenReleaseSends() async {
        await beginHold()
        #expect(viewModel.gesturePhase == .holding)

        viewModel.pressEnded(completion: { _ in })

        #expect(viewModel.gesturePhase == .idle)
        #expect(viewModel.state == .idle || viewModel.showAlert)
        await waitUntil { session.finishCount == 1 }
        #expect(session.cancelCount == 0)
        #expect(!viewModel.showsHoldHint)
    }

    @Test func dragUpThenReleaseKeepsRecordingHandsFree() async {
        await beginHold()

        #expect(viewModel.pressChanged(translation: CGSize(width: 0, height: -400), canRecord: true))
        #expect(viewModel.gesturePhase == .lockArmed)
        viewModel.pressEnded(completion: { _ in })

        #expect(viewModel.gesturePhase == .locked)
        #expect(isRecording)
        #expect(session.finishCount == 0)

        viewModel.sendHandsFree(completion: { _ in })
        #expect(viewModel.gesturePhase == .idle)
        await waitUntil { session.finishCount == 1 }
    }

    @Test func dragLeftThenReleaseDiscards() async {
        await beginHold()

        #expect(viewModel.pressChanged(translation: CGSize(width: -400, height: 0), canRecord: true))
        #expect(viewModel.gesturePhase == .cancelArmed)
        viewModel.pressEnded(completion: { _ in })

        #expect(viewModel.gesturePhase == .idle)
        #expect(viewModel.state == .idle)
        #expect(viewModel.isDiscarding)
        await waitUntil { session.cancelCount == 1 }
        #expect(session.finishCount == 0)
        // The trash animation ends on its own.
        await waitUntil { !viewModel.isDiscarding }
    }

    @Test func quickTapExplainsHowToRecord() async {
        viewModel.pressChanged(translation: .zero, canRecord: true)
        // Released before the permission check and recorder start resolve.
        viewModel.pressEnded(completion: { _ in })

        #expect(viewModel.showsHoldHint)
        #expect(viewModel.gesturePhase == .idle)
        await waitUntil { !viewModel.showsHoldHint }
    }

    @Test func cancelledTouchKeepsRecordingHandsFree() async {
        await beginHold()

        viewModel.pressInterrupted()
        #expect(viewModel.gesturePhase == .locked)
        #expect(isRecording)

        // The late onEnded of the same touch must not send.
        viewModel.pressEnded(completion: { _ in })
        #expect(viewModel.gesturePhase == .locked)
        #expect(session.finishCount == 0)
    }

    @Test func releaseAfterAnInterruptionIsANoOp() async {
        await beginHold()
        viewModel.pressEnded(completion: { _ in })
        await waitUntil { session.finishCount == 1 }

        viewModel.pressInterrupted()
        #expect(viewModel.gesturePhase == .idle)
    }

    @Test func deniedPermissionDropsTheGesture() async {
        session.permissionGranted = false

        viewModel.pressChanged(translation: .zero, canRecord: true)
        #expect(viewModel.gesturePhase == .holding)
        await waitUntil { viewModel.state == .permissionDenied }

        #expect(viewModel.gesturePhase == .idle)
        viewModel.pressEnded(completion: { _ in })
        #expect(session.finishCount == 0)
        #expect(!viewModel.showsHoldHint)
    }

    @Test func pressIsIgnoredWhereMediaCannotBeSent() {
        viewModel.pressChanged(translation: .zero, canRecord: false)
        viewModel.pressChanged(translation: CGSize(width: 0, height: -400), canRecord: false)

        #expect(viewModel.gesturePhase == .idle)
        #expect(viewModel.state == .idle)
        viewModel.pressEnded(completion: { _ in })
        #expect(!viewModel.showsHoldHint)
    }

    @Test func voiceOverStartsHandsFreeAndCanDiscard() async {
        viewModel.startHandsFree(canRecord: true)
        #expect(viewModel.gesturePhase == .locked)
        await waitUntil { isRecording }

        viewModel.discardRecording()

        #expect(viewModel.gesturePhase == .idle)
        #expect(viewModel.isDiscarding)
        await waitUntil { session.cancelCount == 1 }
    }

    @Test func panicDropsAHandsFreeRecording() async {
        viewModel.startHandsFree(canRecord: true)
        await waitUntil { isRecording }

        viewModel.panicWipe()

        #expect(viewModel.gesturePhase == .idle)
        #expect(!viewModel.isDiscarding)
    }

    @Test func recordingFeedsTheLevelMeter() async {
        session.pendingLevels = [-25]
        await beginHold()

        await waitUntil { viewModel.levelMeter.history.levels == [0.5] }

        // A new press starts a fresh waveform.
        viewModel.pressEnded(completion: { _ in })
        viewModel.pressChanged(translation: .zero, canRecord: true)
        #expect(viewModel.levelMeter.history.levels.isEmpty)
    }

    @Test func elapsedTimeReadsAsMinutesAndSeconds() async {
        #expect(viewModel.formattedElapsed(for: Date()) == "0:00")

        await beginHold()
        #expect(viewModel.formattedElapsed(for: Date().addingTimeInterval(75)) == "1:15")
    }
}
