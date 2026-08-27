import Foundation

/// How regularly a patient comes. Derived from the gaps between past appointments.
public enum ConsultationRhythm: Hashable, Sendable {
    case weekly
    case fortnightly
    case monthly
    case irregular(medianDays: Int)
    case unknown

    public var label: String {
        switch self {
        case .weekly: return "Chaque semaine"
        case .fortnightly: return "Toutes les deux semaines"
        case .monthly: return "Une fois par mois"
        case .irregular(let days): return "Irrégulier · environ \(days) j d'écart"
        case .unknown: return "Pas encore de rythme"
        }
    }

    public var isRegular: Bool {
        switch self {
        case .weekly, .fortnightly, .monthly: return true
        case .irregular, .unknown: return false
        }
    }
}

/// The complete picture of one patient, assembled in a handful of queries so the
/// record opens instantly.
public struct PatientProfile: Sendable {
    public let patient: Patient

    public let consultations: [Consultation]
    public let payments: [Payment]

    public let attended: Int
    public let absent: Int
    public let cancelled: Int
    public let upcoming: Int

    public let firstSeen: Date?
    public let lastSeen: Date?
    public let nextAppointment: Consultation?

    public let totalCollectedCents: Int
    public let advice: PaymentAdvice
    public let amountDistribution: [DistributionSlice]
    public let methodDistribution: [DistributionSlice]

    public let rhythm: ConsultationRhythm
    /// 1 = Sunday … 7 = Saturday, matching `Calendar.component(.weekday:)`.
    public let usualWeekday: Int?
    public let usualHour: Int?
    public let measuredDurationAverage: TimeInterval?

    /// Attended consultations that carry no payment — the "reste à traiter" list.
    public let unpaidConsultations: [Consultation]
    /// Payments agreed with this patient that have not arrived yet.
    public let outstandingPayments: [Payment]

    public var totalConsultations: Int { attended + absent + cancelled + upcoming }
    public var paymentCount: Int { payments.count }
    public var outstandingCents: Int { outstandingPayments.reduce(0) { $0 + $1.amountCents } }

    public var attendanceRate: Double? {
        let denominator = attended + absent
        guard denominator > 0 else { return nil }
        return Double(attended) / Double(denominator)
    }

    public func totalCollected(currencyCode: String = "EUR") -> Money {
        Money(cents: totalCollectedCents, currencyCode: currencyCode)
    }

    public var usualWeekdayName: String? {
        guard let usualWeekday else { return nil }
        let symbols = Calendar.cadence.weekdaySymbols
        let index = usualWeekday - 1
        guard symbols.indices.contains(index) else { return nil }
        return symbols[index]
    }

    /// "Le mardi à 16 h" — the one-line summary shown at the top of the record.
    public var usualSlotDescription: String? {
        guard let name = usualWeekdayName, let hour = usualHour else { return nil }
        return "Le \(name) à \(hour) h"
    }
}

extension CadenceStore {

    public func profile(forPatient id: UUID, settings: PracticeSettings? = nil, now: Date = Date()) throws -> PatientProfile? {
        guard let patient = try patient(id: id) else { return nil }
        let settings = try settings ?? self.settings()

        let consultations = try consultations(forPatient: id, limit: 500)
        let payments = try payments(forPatient: id, limit: 500)

        let attended = consultations.filter { $0.status == .attended }.count
        let absent = consultations.filter { $0.status == .absent }.count
        let cancelled = consultations.filter { $0.status == .cancelled }.count
        let upcoming = consultations.filter { !$0.status.isResolved && $0.scheduledStart >= now }.count

        let past = consultations
            .filter { $0.status == .attended || $0.status == .inProgress }
            .sorted { $0.scheduledStart < $1.scheduledStart }

        let paidConsultationIDs = Set(payments.compactMap(\.consultationID))
        let unpaid = consultations
            .filter { $0.status == .attended && !paidConsultationIDs.contains($0.id) }
            .sorted { $0.scheduledStart > $1.scheduledStart }

        let measuredDurations = consultations.compactMap(\.actualDuration)
        let measuredAverage = measuredDurations.isEmpty
            ? nil
            : measuredDurations.reduce(0, +) / Double(measuredDurations.count)

        return PatientProfile(
            patient: patient,
            consultations: consultations,
            payments: payments,
            attended: attended,
            absent: absent,
            cancelled: cancelled,
            upcoming: upcoming,
            firstSeen: past.first?.scheduledStart,
            lastSeen: past.last?.scheduledStart,
            nextAppointment: try nextConsultation(forPatient: id, after: now),
            totalCollectedCents: payments.filter { !$0.isPending }.reduce(0) { $0 + $1.amountCents },
            advice: HabitEngine.advise(payments: payments, patient: patient, settings: settings, now: now),
            amountDistribution: HabitEngine.amountDistribution(payments: payments, currencyCode: settings.currencyCode),
            methodDistribution: HabitEngine.methodDistribution(payments: payments, settings: settings),
            rhythm: RhythmAnalyser.rhythm(of: past),
            usualWeekday: RhythmAnalyser.mode(of: past.map { Calendar.cadence.component(.weekday, from: $0.scheduledStart) }),
            usualHour: RhythmAnalyser.mode(of: past.map { Calendar.cadence.component(.hour, from: $0.scheduledStart) }),
            measuredDurationAverage: measuredAverage,
            unpaidConsultations: unpaid,
            outstandingPayments: payments.filter(\.isPending).sorted { $0.paidAt < $1.paidAt }
        )
    }
}

/// Small statistics helpers kept apart so they can be tested on their own.
public enum RhythmAnalyser {

    /// Classifies the gaps between consecutive appointments.
    ///
    /// A rhythm is only claimed when most gaps agree with the median: a patient seen
    /// weekly for a month and then once six months later is irregular, not weekly.
    public static func rhythm(of consultations: [Consultation], calendar: Calendar = .cadence) -> ConsultationRhythm {
        let dates = consultations.map(\.scheduledStart).sorted()
        guard dates.count >= 3 else { return .unknown }

        var gaps: [Double] = []
        for index in 1..<dates.count {
            let days = dates[index].timeIntervalSince(dates[index - 1]) / 86_400
            if days > 0.5 { gaps.append(days) }
        }
        guard gaps.count >= 2, let median = median(of: gaps), median > 0 else { return .unknown }

        let consistent = gaps.filter { abs($0 - median) <= max(2, median * 0.35) }.count
        let isConsistent = Double(consistent) / Double(gaps.count) >= 0.6
        guard isConsistent else { return .irregular(medianDays: Int(median.rounded())) }

        switch median {
        case ..<10: return .weekly
        case ..<18: return .fortnightly
        case ..<45: return .monthly
        default: return .irregular(medianDays: Int(median.rounded()))
        }
    }

    public static func median(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[middle] }
        return (sorted[middle - 1] + sorted[middle]) / 2
    }

    /// Most frequent value, resolving ties towards the smaller one for determinism.
    public static func mode<T: Hashable & Comparable>(of values: [T]) -> T? {
        guard !values.isEmpty else { return nil }
        var counts: [T: Int] = [:]
        for value in values { counts[value, default: 0] += 1 }
        return counts.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }.first?.key
    }
}
