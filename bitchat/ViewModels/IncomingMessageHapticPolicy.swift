import Foundation

/// Eligibility and burst coalescing for the ordinary incoming-message tap.
struct IncomingMessageHapticPolicy {
    let interval: TimeInterval
    private(set) var lastTapAt: Date?

    init(interval: TimeInterval = 0.12) {
        self.interval = interval
    }

    mutating func shouldTap(
        isIncoming: Bool,
        isSystem: Bool,
        isBackfill: Bool = false,
        isForeground: Bool,
        isReaction: Bool = false,
        reactionTargetsOwnMessage: Bool? = nil,
        now: Date
    ) -> Bool {
        let shouldNotify = isReaction ? reactionTargetsOwnMessage == true : isIncoming
        guard shouldNotify, !isSystem, !isBackfill, isForeground else { return false }
        if let lastTapAt, now.timeIntervalSince(lastTapAt) < interval { return false }
        lastTapAt = now
        return true
    }
}
