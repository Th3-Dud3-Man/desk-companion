import Foundation

public struct MethodTotal: Hashable, Identifiable, Sendable {
    public let methodID: String
    public let label: String
    public let totalCents: Int
    public let count: Int
    public let share: Double

    public var id: String { methodID }
    public func money(currencyCode: String = "EUR") -> Money { Money(cents: totalCents, currencyCode: currencyCode) }
}

public struct DailyTotal: Hashable, Identifiable, Sendable {
    public let day: Date
    public let totalCents: Int
    public let consultationCount: Int
    public var id: Date { day }
}

/// Everything the statistics screen shows for one period.
///
/// Two different clocks are used on purpose, because they answer two different
/// questions: consultation counts are keyed on **when the appointment was
/// scheduled**, revenue on **when the money was actually received**. A patient who
/// pays next week for today's session appears in today's attendance and next week's
/// takings — which is what a ledger should say.
public struct PeriodStatistics: Sendable {
    public let range: DateRange

    public let planned: Int
    public let attended: Int
    public let absent: Int
    public let cancelled: Int
    public let pending: Int

    /// Money actually received in the period, keyed on when it arrived.
    public let revenueCents: Int
    public let paymentCount: Int
    public let byMethod: [MethodTotal]
    /// Agreed during the period, whatever became of it afterwards.
    public let announcedCents: Int
    public let announcedCount: Int
    /// Agreed during the period and still owed.
    public let pendingCents: Int
    public let pendingCount: Int
    public let uniquePatients: Int
    /// Attended consultations with nothing recorded against them yet.
    public let unpaidAttended: Int
    /// Mean of the real session durations that were actually measured.
    public let measuredDurationAverage: TimeInterval?
    public let measuredDurationCount: Int

    public var total: Int { planned }
    public var resolved: Int { attended + absent + cancelled }

    /// Share of resolved appointments where the patient came. `nil` when nothing is resolved.
    public var attendanceRate: Double? {
        let denominator = attended + absent
        guard denominator > 0 else { return nil }
        return Double(attended) / Double(denominator)
    }

    public var averagePerAttendedCents: Int? {
        guard attended > 0, revenueCents > 0 else { return nil }
        return revenueCents / attended
    }

    public var averagePerPaymentCents: Int? {
        guard paymentCount > 0 else { return nil }
        return revenueCents / paymentCount
    }

    public func revenue(currencyCode: String = "EUR") -> Money {
        Money(cents: revenueCents, currencyCode: currencyCode)
    }

    public func pending(currencyCode: String = "EUR") -> Money {
        Money(cents: pendingCents, currencyCode: currencyCode)
    }

    public var hasPending: Bool { pendingCount > 0 }

    public static func empty(range: DateRange) -> PeriodStatistics {
        PeriodStatistics(
            range: range, planned: 0, attended: 0, absent: 0, cancelled: 0, pending: 0,
            revenueCents: 0, paymentCount: 0, byMethod: [],
            announcedCents: 0, announcedCount: 0, pendingCents: 0, pendingCount: 0,
            uniquePatients: 0,
            unpaidAttended: 0, measuredDurationAverage: nil, measuredDurationCount: 0
        )
    }
}

/// A period alongside the one before it, for the "évolution" figures.
public struct PeriodComparison: Sendable {
    public let current: PeriodStatistics
    public let previous: PeriodStatistics

    /// Relative change in revenue, `nil` when the previous period had none
    /// (a jump from zero is not a percentage anyone should be shown).
    public var revenueChange: Double? {
        guard previous.revenueCents > 0 else { return nil }
        return (Double(current.revenueCents) - Double(previous.revenueCents)) / Double(previous.revenueCents)
    }

    public var attendedChange: Int { current.attended - previous.attended }
    public var revenueDeltaCents: Int { current.revenueCents - previous.revenueCents }
}

extension CadenceStore {

    public func statistics(for range: DateRange, settings: PracticeSettings? = nil) throws -> PeriodStatistics {
        let settings = try settings ?? self.settings()
        let bounds: [SQLValue] = [.int(range.startEpoch), .int(range.endEpoch)]

        // Consultation counts, keyed on the scheduled slot.
        var counts: [ConsultationStatus: Int] = [:]
        for row in try database.query(
            """
            SELECT status, COUNT(*) AS n FROM consultation
            WHERE scheduled_start >= ? AND scheduled_start < ?
            GROUP BY status;
            """, bounds
        ) {
            if let status = ConsultationStatus(rawValue: row.stringValue("status")) {
                counts[status] = row.intValue("n")
            }
        }

        let attended = counts[.attended] ?? 0
        let absent = counts[.absent] ?? 0
        let cancelled = counts[.cancelled] ?? 0
        let pending = (counts[.scheduled] ?? 0) + (counts[.confirmed] ?? 0) + (counts[.inProgress] ?? 0)
        let planned = attended + absent + pending          // cancelled slots are not "planned work"

        // Takings, keyed on when the money actually arrived.
        let totalsRow = try database.query(
            """
            SELECT COALESCE(SUM(amount_cents), 0) AS total, COUNT(*) AS n
            FROM payment WHERE settled_at >= ? AND settled_at < ?;
            """, bounds
        ).first
        let revenueCents = totalsRow?.intValue("total") ?? 0
        let paymentCount = totalsRow?.intValue("n") ?? 0

        // Agreed during the period, and what of it is still owed.
        let announcedRow = try database.query(
            """
            SELECT COALESCE(SUM(amount_cents), 0) AS total, COUNT(*) AS n
            FROM payment WHERE paid_at >= ? AND paid_at < ?;
            """, bounds
        ).first
        let pendingRow = try database.query(
            """
            SELECT COALESCE(SUM(amount_cents), 0) AS total, COUNT(*) AS n
            FROM payment WHERE paid_at >= ? AND paid_at < ? AND settled_at IS NULL;
            """, bounds
        ).first

        var byMethod: [MethodTotal] = []
        for row in try database.query(
            """
            SELECT method, COALESCE(SUM(amount_cents), 0) AS total, COUNT(*) AS n
            FROM payment WHERE settled_at >= ? AND settled_at < ?
            GROUP BY method ORDER BY total DESC;
            """, bounds
        ) {
            let methodID = row.stringValue("method", default: "other")
            let total = row.intValue("total")
            byMethod.append(
                MethodTotal(
                    methodID: methodID,
                    label: settings.methodLabel(methodID),
                    totalCents: total,
                    count: row.intValue("n"),
                    share: revenueCents > 0 ? Double(total) / Double(revenueCents) : 0
                )
            )
        }

        let uniquePatients = try database.scalarInt(
            """
            SELECT COUNT(DISTINCT patient_id) AS value FROM consultation
            WHERE scheduled_start >= ? AND scheduled_start < ? AND patient_id IS NOT NULL
              AND status IN ('attended', 'inProgress');
            """, bounds
        )

        let unpaidAttended = try database.scalarInt(
            """
            SELECT COUNT(*) AS value FROM consultation c
            WHERE c.scheduled_start >= ? AND c.scheduled_start < ? AND c.status = 'attended'
              AND NOT EXISTS (SELECT 1 FROM payment p WHERE p.consultation_id = c.id);
            """, bounds
        )

        let durationRow = try database.query(
            """
            SELECT AVG(actual_end - actual_start) AS average, COUNT(*) AS n FROM consultation
            WHERE scheduled_start >= ? AND scheduled_start < ?
              AND actual_start IS NOT NULL AND actual_end IS NOT NULL AND actual_end > actual_start;
            """, bounds
        ).first
        let measuredCount = durationRow?.intValue("n") ?? 0
        let measuredAverage = measuredCount > 0 ? durationRow?.double("average") : nil

        return PeriodStatistics(
            range: range,
            planned: planned,
            attended: attended,
            absent: absent,
            cancelled: cancelled,
            pending: pending,
            revenueCents: revenueCents,
            paymentCount: paymentCount,
            byMethod: byMethod,
            announcedCents: announcedRow?.intValue("total") ?? 0,
            announcedCount: announcedRow?.intValue("n") ?? 0,
            pendingCents: pendingRow?.intValue("total") ?? 0,
            pendingCount: pendingRow?.intValue("n") ?? 0,
            uniquePatients: uniquePatients,
            unpaidAttended: unpaidAttended,
            measuredDurationAverage: measuredAverage,
            measuredDurationCount: measuredCount
        )
    }

    public func comparison(for range: DateRange, settings: PracticeSettings? = nil) throws -> PeriodComparison {
        let settings = try settings ?? self.settings()
        return PeriodComparison(
            current: try statistics(for: range, settings: settings),
            previous: try statistics(for: range.previousPeriod(), settings: settings)
        )
    }

    /// Day-by-day takings and attendance, for the small chart on the statistics screen.
    public func dailyTotals(in range: DateRange, calendar: Calendar = .cadence) throws -> [DailyTotal] {
        var revenueByDay: [Date: Int] = [:]
        for payment in try settledPayments(in: range) {
            guard let settledAt = payment.settledAt else { continue }
            let day = calendar.startOfDay(for: settledAt)
            revenueByDay[day, default: 0] += payment.amountCents
        }

        var countByDay: [Date: Int] = [:]
        for consultation in try consultations(in: range, includeCancelled: false) where consultation.status == .attended {
            let day = calendar.startOfDay(for: consultation.scheduledStart)
            countByDay[day, default: 0] += 1
        }

        var results: [DailyTotal] = []
        var cursor = calendar.startOfDay(for: range.start)
        while cursor < range.end {
            results.append(
                DailyTotal(
                    day: cursor,
                    totalCents: revenueByDay[cursor] ?? 0,
                    consultationCount: countByDay[cursor] ?? 0
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return results
    }
}
