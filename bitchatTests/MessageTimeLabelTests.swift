//
// MessageTimeLabelTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Testing
import Foundation
import BitFoundation
@testable import bitchat

struct MessageTimeLabelTests {
    private func row(at date: Date) -> BitchatMessage {
        BitchatMessage(
            sender: "alice",
            content: "hi",
            timestamp: date,
            isRelay: false,
            senderPeerID: PeerID(str: "00000000000000a1")
        )
    }

    /// Noon on the day `daysAgo` days before today, so no case straddles
    /// midnight.
    private func noon(daysAgo: Int) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
        return calendar.date(byAdding: .hour, value: 12, to: day)!
    }

    @Test func theFirstMessageOpensATimeGroup() {
        #expect(MessageTimeLabel.startsTimeGroup(row(at: Date()), after: nil))
    }

    @Test func aLongPauseOpensATimeGroupAndAShortOneDoesNot() {
        let first = row(at: Date(timeIntervalSince1970: 1_700_000_000))
        let soon = row(at: first.timestamp.addingTimeInterval(60))
        let late = row(at: first.timestamp.addingTimeInterval(MessageTimeLabel.groupGap + 1))

        #expect(!MessageTimeLabel.startsTimeGroup(soon, after: first))
        #expect(MessageTimeLabel.startsTimeGroup(late, after: first))
        // A late arrival stamped before its predecessor joins its group.
        #expect(!MessageTimeLabel.startsTimeGroup(first, after: late))
    }

    @Test func aTimeGroupAlwaysOpensARunToo() {
        // The sender's name must show again under every time label.
        #expect(MessageTimeLabel.groupGap >= MessageRunPolicy.maxGap)
    }

    @Test func todayAndYesterdayReadAsDifferentDays() {
        let today = MessageTimeLabel.label(for: noon(daysAgo: 0))
        let yesterday = MessageTimeLabel.label(for: noon(daysAgo: 1))

        // Same clock time, so only the day part tells them apart.
        #expect(today != yesterday)
        #expect(today == MessageTimeLabel.label(for: noon(daysAgo: 0)))
    }

    @Test func theLastWeekReadsAsAWeekday() {
        let date = noon(daysAgo: 3)
        let weekday = DateFormatter()
        weekday.setLocalizedDateFormatFromTemplate("EEEE")

        #expect(MessageTimeLabel.label(for: date).lowercased().contains(weekday.string(from: date).lowercased()))
    }

    @Test func anOlderYearReadsWithItsYear() {
        let date = noon(daysAgo: 800)
        let year = Calendar.current.component(.year, from: date)

        #expect(MessageTimeLabel.label(for: date).contains(String(year)))
    }

    @Test func theExactLabelKeepsTheSeconds() {
        let date = Calendar.current.date(bySetting: .second, value: 37, of: noon(daysAgo: 0))!

        #expect(MessageTimeLabel.exactLabel(for: date).contains("37"))
        #expect(!MessageTimeLabel.label(for: date).contains("37"))
    }
}
