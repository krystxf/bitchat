//
// VoiceRecordGestureTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import CoreGraphics
import Testing
@testable import bitchat

struct VoiceRecordGestureTests {
    private let thresholds = VoiceRecordGesture.Thresholds(
        lockDistance: 70,
        cancelDistance: 100,
        disarmFraction: 0.75
    )

    private func holding() -> VoiceRecordGesture {
        var gesture = VoiceRecordGesture(thresholds: thresholds)
        _ = gesture.press()
        return gesture
    }

    @Test func pressStartsRecordingOnce() {
        var gesture = VoiceRecordGesture(thresholds: thresholds)

        #expect(gesture.press() == .start)
        #expect(gesture.phase == .holding)
        // DragGesture.onChanged fires for every move; only the first starts.
        #expect(gesture.press() == .none)
        #expect(gesture.phase == .holding)
    }

    @Test func releaseInPlaceSends() {
        var gesture = holding()
        gesture.drag(to: CGSize(width: -20, height: -10))

        #expect(gesture.release() == .send)
        #expect(gesture.phase == .idle)
        #expect(gesture.translation == .zero)
    }

    @Test func dragUpPastThresholdArmsLockAndReleaseLocks() {
        var gesture = holding()

        let crossed1 = gesture.drag(to: CGSize(width: 0, height: -69))
        #expect(!crossed1)
        #expect(gesture.phase == .holding)
        let crossed2 = gesture.drag(to: CGSize(width: 0, height: -70))
        #expect(crossed2)
        #expect(gesture.phase == .lockArmed)

        #expect(gesture.release() == .lock)
        #expect(gesture.phase == .locked)
    }

    @Test func dragLeftPastThresholdArmsCancelAndReleaseCancels() {
        var gesture = holding()

        let crossed3 = gesture.drag(to: CGSize(width: -99, height: 0))
        #expect(!crossed3)
        let crossed4 = gesture.drag(to: CGSize(width: -100, height: 0))
        #expect(crossed4)
        #expect(gesture.phase == .cancelArmed)

        #expect(gesture.release() == .cancel)
        #expect(gesture.phase == .idle)
    }

    @Test func dragRightOrDownNeverArms() {
        var gesture = holding()

        let crossed5 = gesture.drag(to: CGSize(width: 300, height: 300))
        #expect(!crossed5)
        #expect(gesture.phase == .holding)
        #expect(gesture.release() == .send)
    }

    @Test func armedPhaseHoldsUntilFingerComesBackPastHysteresis() {
        var gesture = holding()
        gesture.drag(to: CGSize(width: 0, height: -80))
        #expect(gesture.phase == .lockArmed)

        // Still above 75 % of the threshold: stays armed, no new crossing.
        let crossed6 = gesture.drag(to: CGSize(width: 0, height: -53))
        #expect(!crossed6)
        #expect(gesture.phase == .lockArmed)

        // Below it: disarms, and that is a crossing worth a cue.
        let crossed7 = gesture.drag(to: CGSize(width: 0, height: -52))
        #expect(crossed7)
        #expect(gesture.phase == .holding)
        #expect(gesture.release() == .send)
    }

    @Test func cancelHysteresisMirrorsLock() {
        var gesture = holding()
        gesture.drag(to: CGSize(width: -120, height: 0))
        #expect(gesture.phase == .cancelArmed)

        gesture.drag(to: CGSize(width: -75, height: 0))
        #expect(gesture.phase == .cancelArmed)
        gesture.drag(to: CGSize(width: -74, height: 0))
        #expect(gesture.phase == .holding)
    }

    @Test func diagonalDragFollowsTheStrongerDirection() {
        var gesture = holding()

        // 140/70 = 2.0 up vs 150/100 = 1.5 left: lock wins.
        gesture.drag(to: CGSize(width: -150, height: -140))
        #expect(gesture.phase == .lockArmed)

        // 70/70 = 1.0 up vs 200/100 = 2.0 left: cancel takes over.
        gesture.drag(to: CGSize(width: -200, height: -70))
        #expect(gesture.phase == .cancelArmed)
        #expect(gesture.release() == .cancel)
    }

    @Test func movingFromLockToCancelSwitchesPhase() {
        var gesture = holding()
        gesture.drag(to: CGSize(width: 0, height: -90))
        #expect(gesture.phase == .lockArmed)

        let crossed8 = gesture.drag(to: CGSize(width: -110, height: 0))
        #expect(crossed8)
        #expect(gesture.phase == .cancelArmed)
    }

    @Test func lockedRecordingIgnoresStrayGestureEvents() {
        var gesture = holding()
        gesture.drag(to: CGSize(width: 0, height: -90))
        _ = gesture.release()
        #expect(gesture.phase == .locked)

        #expect(gesture.press() == .none)
        let crossed9 = gesture.drag(to: CGSize(width: -200, height: 0))
        #expect(!crossed9)
        #expect(gesture.release() == .none)
        #expect(gesture.phase == .locked)
    }

    @Test func lockedRecordingSendsOrCancelsExplicitly() {
        var sending = holding()
        sending.drag(to: CGSize(width: 0, height: -90))
        _ = sending.release()
        #expect(sending.send() == .send)
        #expect(sending.phase == .idle)

        var cancelling = holding()
        cancelling.drag(to: CGSize(width: 0, height: -90))
        _ = cancelling.release()
        #expect(cancelling.cancel() == .cancel)
        #expect(cancelling.phase == .idle)
    }

    @Test func sendOnlyAppliesToHandsFree() {
        var gesture = holding()
        #expect(gesture.send() == .none)
        #expect(gesture.phase == .holding)

        var idle = VoiceRecordGesture(thresholds: thresholds)
        #expect(idle.send() == .none)
        #expect(idle.cancel() == .none)
    }

    @Test func cancelWhileHoldingDiscardsAndIgnoresTheLaterRelease() {
        var gesture = holding()

        #expect(gesture.cancel() == .cancel)
        #expect(gesture.phase == .idle)
        #expect(gesture.release() == .none)
    }

    @Test func handsFreeStartIsForAssistiveInput() {
        var gesture = VoiceRecordGesture(thresholds: thresholds)

        #expect(gesture.startHandsFree() == .start)
        #expect(gesture.phase == .locked)
        #expect(gesture.startHandsFree() == .none)
        #expect(gesture.send() == .send)
    }

    @Test func resetDropsTheGestureWithoutAnAction() {
        var gesture = holding()
        gesture.drag(to: CGSize(width: -120, height: 0))

        gesture.reset()

        #expect(gesture.phase == .idle)
        #expect(gesture.translation == .zero)
        #expect(gesture.release() == .none)
    }

    @Test func progressIsClampedPerDirection() {
        #expect(thresholds.lockProgress(for: CGSize(width: 0, height: -35)) == 0.5)
        #expect(thresholds.lockProgress(for: CGSize(width: 0, height: -700)) == 1)
        #expect(thresholds.lockProgress(for: CGSize(width: 0, height: 40)) == 0)
        #expect(thresholds.cancelProgress(for: CGSize(width: -25, height: 0)) == 0.25)
        #expect(thresholds.cancelProgress(for: CGSize(width: 50, height: 0)) == 0)
    }

    @Test func onlyArmedPhasesCountAsCrossings() {
        #expect(VoiceRecordGesture.Phase.lockArmed.isArmed)
        #expect(VoiceRecordGesture.Phase.cancelArmed.isArmed)
        #expect(!VoiceRecordGesture.Phase.holding.isArmed)
        #expect(!VoiceRecordGesture.Phase.locked.isArmed)
        #expect(VoiceRecordGesture.Phase.holding.isHolding)
        #expect(!VoiceRecordGesture.Phase.locked.isHolding)
    }
}
