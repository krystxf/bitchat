//
// MessageTimeLabel.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import BitFoundation
import SwiftUI

/// The timeline's time labels, as Messages shows them: a centered label
/// above the message that opens a time group ("Today 18:07"), and the exact
/// time on request (context menu, macOS tooltip).
///
/// The day comes from the system's own formatters, so "Today", "Yesterday",
/// weekdays and dates follow the user's language, and the time follows
/// their 12/24-hour setting.
enum MessageTimeLabel {
    /// A pause longer than this opens a new time group.
    static let groupGap: TimeInterval = 15 * 60

    /// Whether `message` opens a time group: the first message, or one that
    /// arrives more than `groupGap` after the previous one. A plain
    /// timestamp comparison, cheap enough to run for every row.
    static func startsTimeGroup(_ message: BitchatMessage, after previous: BitchatMessage?) -> Bool {
        guard let previous else { return true }
        return message.timestamp.timeIntervalSince(previous.timestamp) > groupGap
    }

    /// "Today 18:07", "Yesterday 18:07", the weekday within the past week
    /// ("Tuesday 18:07"), and the date before that.
    static func label(for date: Date) -> String {
        join(day: dayText(for: date), time: Formatters.time.string(from: date))
    }

    /// The same label, to the second.
    static func exactLabel(for date: Date) -> String {
        join(day: dayText(for: date), time: Formatters.timeWithSeconds.string(from: date))
    }

    private static func join(day: String, time: String) -> String {
        String(
            format: String(localized: "content.timeline.day_time", defaultValue: "%1$@ %2$@", comment: "Time label above a group of messages: a day (Today, Yesterday, a weekday or a date) followed by a time of day"),
            locale: .current,
            day,
            time
        )
    }

    private static func dayText(for date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfWeek = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfYesterday

        if date >= startOfYesterday && date < startOfTomorrow {
            return Formatters.relativeDay.string(from: date)
        }
        if date >= startOfWeek && date < startOfYesterday {
            return Formatters.weekday.string(from: date)
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return Formatters.monthDay.string(from: date)
        }
        return Formatters.yearMonthDay.string(from: date)
    }

    private enum Formatters {
        /// "Today" or "Yesterday".
        static let relativeDay: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = .autoupdatingCurrent
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            formatter.doesRelativeDateFormatting = true
            formatter.formattingContext = .beginningOfSentence
            return formatter
        }()
        static let weekday = template("EEEE")
        static let monthDay = template("EEEMMMd")
        static let yearMonthDay = template("yMMMd")
        // "j" is the locale's hour cycle, overridden by the user's
        // 12/24-hour setting.
        static let time = template("jmm")
        static let timeWithSeconds = template("jmmss")

        private static func template(_ template: String) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.locale = .autoupdatingCurrent
            formatter.setLocalizedDateFormatFromTemplate(template)
            formatter.formattingContext = .beginningOfSentence
            return formatter
        }
    }
}

/// The centered time label above a message that opens a time group.
struct MessageTimeHeader: View {
    @ThemedPalette private var palette

    let date: Date

    var body: some View {
        Text(verbatim: MessageTimeLabel.label(for: date))
            .font(.caption2.weight(.medium))
            .foregroundColor(palette.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// Puts the time label above the row when it opens a time group.
    func messageTimeHeader(_ date: Date?) -> some View {
        VStack(spacing: 0) {
            if let date {
                MessageTimeHeader(date: date)
            }
            self
        }
    }

    /// The exact time as a hover tooltip on macOS. iOS has no hover, and
    /// the time stays in the context menu there.
    @ViewBuilder
    func messageExactTimeHelp(_ date: Date) -> some View {
        #if os(macOS)
        help(MessageTimeLabel.exactLabel(for: date))
        #else
        self
        #endif
    }
}
