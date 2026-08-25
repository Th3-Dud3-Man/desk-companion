import Foundation

extension Calendar {
    /// The calendar the whole application reasons with.
    ///
    /// Gregorian, Monday-first, ISO week rules — and mutable so the test suite can
    /// pin a time zone instead of depending on the machine it runs on.
    public static var cadence: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "fr_FR")
        calendar.timeZone = TimeZone.current
        calendar.firstWeekday = 2      // Monday
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }()
}

/// A half-open interval `[start, end)` over which statistics are computed.
public struct DateRange: Hashable, Sendable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = max(start, end)
    }

    public func contains(_ date: Date) -> Bool { date >= start && date < end }
    public var duration: TimeInterval { end.timeIntervalSince(start) }

    // MARK: Named ranges

    public static func day(containing date: Date, calendar: Calendar = .cadence) -> DateRange {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateRange(start: start, end: end)
    }

    public static func week(containing date: Date, calendar: Calendar = .cadence) -> DateRange {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -offset, to: startOfDay) ?? startOfDay
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86_400)
        return DateRange(start: start, end: end)
    }

    public static func month(containing date: Date, calendar: Calendar = .cadence) -> DateRange {
        let components = calendar.dateComponents([.year, .month], from: date)
        let start = calendar.date(from: components) ?? calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start.addingTimeInterval(30 * 86_400)
        return DateRange(start: start, end: end)
    }

    public static func year(containing date: Date, calendar: Calendar = .cadence) -> DateRange {
        let components = calendar.dateComponents([.year], from: date)
        let start = calendar.date(from: components) ?? calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .year, value: 1, to: start) ?? start.addingTimeInterval(365 * 86_400)
        return DateRange(start: start, end: end)
    }

    /// The equivalent range immediately before this one, used for "évolution".
    public func previousPeriod(calendar: Calendar = .cadence) -> DateRange {
        let length = end.timeIntervalSince(start)
        return DateRange(start: start.addingTimeInterval(-length), end: start)
    }

    public var startEpoch: Int { Int(start.timeIntervalSince1970.rounded()) }
    public var endEpoch: Int { Int(end.timeIntervalSince1970.rounded()) }
}

/// French date and time formatting, centralised so nothing is formatted ad hoc.
public enum CadenceFormat {
    private static func formatter(_ configure: (DateFormatter) -> Void) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.calendar = .cadence
        formatter.timeZone = Calendar.cadence.timeZone
        configure(formatter)
        return formatter
    }

    /// `14:00`
    public static func time(_ date: Date) -> String {
        formatter { $0.dateFormat = "HH:mm" }.string(from: date)
    }

    /// `mardi 25 août`
    public static func dayLong(_ date: Date) -> String {
        formatter { $0.dateFormat = "EEEE d MMMM" }.string(from: date)
    }

    /// `mardi 25 août 2026`
    public static func dayFull(_ date: Date) -> String {
        formatter { $0.dateFormat = "EEEE d MMMM yyyy" }.string(from: date)
    }

    /// `25 août`
    public static func dayShort(_ date: Date) -> String {
        formatter { $0.dateFormat = "d MMM" }.string(from: date)
    }

    /// `mar. 25`
    public static func weekdayCompact(_ date: Date) -> String {
        formatter { $0.dateFormat = "EEE d" }.string(from: date)
    }

    /// `août 2026`
    public static func monthYear(_ date: Date) -> String {
        formatter { $0.dateFormat = "LLLL yyyy" }.string(from: date)
    }

    /// `25/08/2026`
    public static func numericDate(_ date: Date) -> String {
        formatter { $0.dateFormat = "dd/MM/yyyy" }.string(from: date)
    }

    /// `25/08/2026 14:00` — the form used in exports.
    public static func numericDateTime(_ date: Date) -> String {
        formatter { $0.dateFormat = "dd/MM/yyyy HH:mm" }.string(from: date)
    }

    /// `50 min`, `1 h`, `1 h 30`
    public static func duration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int((interval / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes) min" }
        if minutes == 0 { return "\(hours) h" }
        return "\(hours) h \(String(format: "%02d", minutes))"
    }

    /// `dans 12 min`, `il y a 3 min`, `maintenant`
    public static func relative(_ date: Date, from reference: Date = Date()) -> String {
        let delta = date.timeIntervalSince(reference)
        let minutes = Int((abs(delta) / 60).rounded())
        if minutes < 1 { return "maintenant" }
        let text: String
        if minutes < 60 {
            text = "\(minutes) min"
        } else {
            let hours = minutes / 60
            let remainder = minutes % 60
            text = remainder == 0 ? "\(hours) h" : "\(hours) h \(remainder)"
        }
        return delta >= 0 ? "dans \(text)" : "il y a \(text)"
    }

    /// `il y a 3 min`, `hier`, `le 12/08/2026` — for sync status lines.
    public static func since(_ date: Date, now: Date = Date(), calendar: Calendar = .cadence) -> String {
        let delta = now.timeIntervalSince(date)
        if delta < 60 { return "à l'instant" }
        if delta < 3_600 { return "il y a \(Int(delta / 60)) min" }
        if calendar.isDate(date, inSameDayAs: now) { return "il y a \(Int(delta / 3_600)) h" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "hier à \(time(date))"
        }
        return "le \(numericDate(date))"
    }
}
