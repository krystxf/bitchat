import Foundation
import Testing
@testable import bitchat

struct IncomingMessageHapticPolicyTests {
    @Test func tapsOnlyEligibleMessages() {
        var policy = IncomingMessageHapticPolicy()
        let now = Date()
        let initialTap = policy.shouldTap(isIncoming: true, isSystem: false, isForeground: true, hasStrongerFeedback: false, now: now)
        let ownMessage = policy.shouldTap(isIncoming: false, isSystem: false, isForeground: true, hasStrongerFeedback: false, now: now.addingTimeInterval(1))
        let systemMessage = policy.shouldTap(isIncoming: true, isSystem: true, isForeground: true, hasStrongerFeedback: false, now: now.addingTimeInterval(1))
        let backfill = policy.shouldTap(isIncoming: true, isSystem: false, isBackfill: true, isForeground: true, hasStrongerFeedback: false, now: now.addingTimeInterval(1))
        let background = policy.shouldTap(isIncoming: true, isSystem: false, isForeground: false, hasStrongerFeedback: false, now: now.addingTimeInterval(1))
        let strongerFeedback = policy.shouldTap(isIncoming: true, isSystem: false, isForeground: true, hasStrongerFeedback: true, now: now.addingTimeInterval(1))
        #expect(initialTap)
        #expect(!ownMessage)
        #expect(!systemMessage)
        #expect(!backfill)
        #expect(!background)
        #expect(!strongerFeedback)
        let reactionToMine = policy.shouldTap(isIncoming: false, isSystem: false, isForeground: true, hasStrongerFeedback: false, isReaction: true, reactionTargetsOwnMessage: true, now: now.addingTimeInterval(1))
        let reactionToOther = policy.shouldTap(isIncoming: true, isSystem: false, isForeground: true, hasStrongerFeedback: false, isReaction: true, reactionTargetsOwnMessage: false, now: now.addingTimeInterval(1))
        #expect(reactionToMine)
        #expect(!reactionToOther)
    }

    @Test func coalescesBurstsButAllowsLaterMessages() {
        var policy = IncomingMessageHapticPolicy(interval: 0.12)
        let now = Date()
        let firstTap = policy.shouldTap(isIncoming: true, isSystem: false, isForeground: true, hasStrongerFeedback: false, now: now)
        let coalesced = policy.shouldTap(isIncoming: true, isSystem: false, isForeground: true, hasStrongerFeedback: false, now: now.addingTimeInterval(0.08))
        let laterTap = policy.shouldTap(isIncoming: true, isSystem: false, isForeground: true, hasStrongerFeedback: false, now: now.addingTimeInterval(0.13))
        #expect(firstTap)
        #expect(!coalesced)
        #expect(laterTap)
    }
}
