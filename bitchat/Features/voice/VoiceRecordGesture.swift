//
// VoiceRecordGesture.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import CoreGraphics

/// The hold-to-record gesture on the composer's mic button, as a pure state
/// machine so its thresholds are testable without SwiftUI.
///
/// Press and hold records. While the finger stays down:
/// - releasing in place sends the voice message,
/// - dragging up past `lockDistance` arms the hands-free lock, and
///   releasing there keeps recording without the finger,
/// - dragging left past `cancelDistance` arms cancel, and releasing there
///   discards the recording.
///
/// An armed phase only disarms once the finger comes back below
/// `disarmFraction` of its threshold, so a finger resting on the line does
/// not flicker between phases (and buzz the haptic engine).
struct VoiceRecordGesture: Equatable {
    enum Phase: Equatable {
        /// No recording gesture in progress.
        case idle
        /// Finger down and recording; release sends.
        case holding
        /// Dragged up past the lock threshold; release goes hands free.
        case lockArmed
        /// Dragged left past the cancel threshold; release discards.
        case cancelArmed
        /// Hands free: recording continues without the finger and needs
        /// an explicit send or cancel.
        case locked

        /// The finger (or mouse button) is still down on the mic.
        var isHolding: Bool {
            switch self {
            case .holding, .lockArmed, .cancelArmed: true
            case .idle, .locked: false
            }
        }

        /// Whether a crossing into this phase deserves a haptic cue.
        var isArmed: Bool {
            self == .lockArmed || self == .cancelArmed
        }
    }

    /// What the recorder must do in response to a gesture event.
    enum Action: Equatable {
        case none
        /// Begin recording.
        case start
        /// Stop recording and send it.
        case send
        /// Stop recording and discard it.
        case cancel
        /// Keep recording hands free.
        case lock
    }

    struct Thresholds: Equatable {
        /// Upward drag, in points, that arms the hands-free lock.
        var lockDistance: CGFloat
        /// Leftward drag, in points, that arms cancel.
        var cancelDistance: CGFloat
        /// An armed phase stays armed until the drag falls below this
        /// fraction of its threshold.
        var disarmFraction: CGFloat

        /// A mouse travels further per gesture than a thumb feels it, so
        /// macOS uses shorter distances than a phone.
        static let standard: Thresholds = {
            #if os(macOS)
            Thresholds(lockDistance: 56, cancelDistance: 80, disarmFraction: 0.75)
            #else
            Thresholds(lockDistance: 70, cancelDistance: 100, disarmFraction: 0.75)
            #endif
        }()

        /// 0...1 progress towards the lock threshold for a drag translation.
        func lockProgress(for translation: CGSize) -> CGFloat {
            guard lockDistance > 0 else { return 0 }
            return min(1, max(0, -translation.height) / lockDistance)
        }

        /// 0...1 progress towards the cancel threshold for a drag translation.
        func cancelProgress(for translation: CGSize) -> CGFloat {
            guard cancelDistance > 0 else { return 0 }
            return min(1, max(0, -translation.width) / cancelDistance)
        }
    }

    let thresholds: Thresholds
    private(set) var phase: Phase = .idle
    /// The drag translation of the current hold, from where it began.
    private(set) var translation: CGSize = .zero

    init(thresholds: Thresholds = .standard) {
        self.thresholds = thresholds
    }

    /// Finger down on the mic. Only an idle press starts a recording; a
    /// repeated call during the same hold changes nothing.
    mutating func press() -> Action {
        guard phase == .idle else { return .none }
        phase = .holding
        translation = .zero
        return .start
    }

    /// Finger moved during a hold. Returns true when the phase changed, so
    /// the caller can play a haptic cue on the crossing.
    @discardableResult
    mutating func drag(to translation: CGSize) -> Bool {
        guard phase.isHolding else { return false }
        self.translation = translation

        let lockProgress = Self.rawProgress(-translation.height, over: thresholds.lockDistance)
        let cancelProgress = Self.rawProgress(-translation.width, over: thresholds.cancelDistance)
        let lockArmed = lockProgress >= (phase == .lockArmed ? thresholds.disarmFraction : 1)
        let cancelArmed = cancelProgress >= (phase == .cancelArmed ? thresholds.disarmFraction : 1)

        let next: Phase
        switch (lockArmed, cancelArmed) {
        case (true, true):
            // A diagonal drag goes with whichever direction it committed
            // to more, relative to that direction's own threshold.
            next = lockProgress >= cancelProgress ? .lockArmed : .cancelArmed
        case (true, false):
            next = .lockArmed
        case (false, true):
            next = .cancelArmed
        case (false, false):
            next = .holding
        }

        guard next != phase else { return false }
        phase = next
        return true
    }

    /// Finger lifted. Resolves the hold into send, lock or cancel.
    mutating func release() -> Action {
        translation = .zero
        switch phase {
        case .holding:
            phase = .idle
            return .send
        case .lockArmed:
            phase = .locked
            return .lock
        case .cancelArmed:
            phase = .idle
            return .cancel
        case .idle, .locked:
            return .none
        }
    }

    /// The system cancelled the touch without a release (an alert, a call,
    /// the view going away). Keep the recording hands free rather than
    /// guess between send and cancel; the bar then offers both.
    mutating func interrupt() -> Action {
        guard phase.isHolding else { return .none }
        phase = .locked
        translation = .zero
        return .lock
    }

    /// Starts straight into hands free, for VoiceOver and other assistive
    /// input that cannot hold and drag.
    mutating func startHandsFree() -> Action {
        guard phase == .idle else { return .none }
        phase = .locked
        translation = .zero
        return .start
    }

    /// The send button of a hands-free recording.
    mutating func send() -> Action {
        guard phase == .locked else { return .none }
        phase = .idle
        return .send
    }

    /// The trash button (or an accessibility cancel) at any point.
    mutating func cancel() -> Action {
        guard phase != .idle else { return .none }
        phase = .idle
        translation = .zero
        return .cancel
    }

    /// The recorder ended on its own (permission denied, error, panic):
    /// drop the gesture without any action.
    mutating func reset() {
        phase = .idle
        translation = .zero
    }

    private static func rawProgress(_ distance: CGFloat, over threshold: CGFloat) -> CGFloat {
        guard threshold > 0 else { return 0 }
        return max(0, distance) / threshold
    }
}
