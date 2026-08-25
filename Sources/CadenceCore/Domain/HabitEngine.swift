import Foundation

/// A concrete amount + method pair that can be applied in one click.
public struct PaymentSuggestion: Hashable, Identifiable, Sendable {
    public let amountCents: Int
    public let methodID: String
    public let currencyCode: String

    public init(amountCents: Int, methodID: String, currencyCode: String = "EUR") {
        self.amountCents = amountCents
        self.methodID = methodID
        self.currencyCode = currencyCode
    }

    public var id: String { "\(amountCents)|\(methodID)" }
    public var money: Money { Money(cents: amountCents, currencyCode: currencyCode) }
}

/// Why Cadence is proposing what it is proposing. Always surfaced in the interface:
/// the user should never wonder where a number came from.
public enum PaymentBasis: Hashable, Sendable {
    /// A stable pattern was found in the patient's history.
    case habit(occurrences: Int, outOf: Int)
    /// Not enough regularity yet — this is simply what they paid last time.
    case lastPayment(on: Date)
    /// A tariff set on the patient's record.
    case patientDefault
    /// The practice tariff, used for a brand new patient.
    case practiceDefault

    public var isHabit: Bool {
        if case .habit = self { return true }
        return false
    }

    public var label: String {
        switch self {
        case .habit(let occurrences, let outOf):
            return "Paiement habituel · \(occurrences) fois sur \(outOf)"
        case .lastPayment(let date):
            return "Dernier paiement · \(CadenceFormat.numericDate(date))"
        case .patientDefault:
            return "Tarif de ce patient"
        case .practiceDefault:
            return "Tarif du cabinet"
        }
    }

    /// Short form for a dense row.
    public var shortLabel: String {
        switch self {
        case .habit: return "Paiement habituel"
        case .lastPayment: return "Dernier paiement"
        case .patientDefault: return "Tarif du patient"
        case .practiceDefault: return "Tarif du cabinet"
        }
    }
}

/// Everything the payment strip needs to render itself.
public struct PaymentAdvice: Sendable {
    public let primary: PaymentSuggestion
    public let basis: PaymentBasis
    /// `0...1`. Only meaningful for `.habit`; zero otherwise.
    public let confidence: Double
    /// Number of payments the advice was computed from.
    public let sampleSize: Int
    /// Other combinations actually observed for this patient, best first.
    public let alternatives: [PaymentSuggestion]
    /// The configured methods other than the primary one, at the primary amount,
    /// so switching method for one session is a single click.
    public let quickMethodSwitches: [PaymentSuggestion]

    public var isHabit: Bool { basis.isHabit }
}

/// One line of the amount or method breakdown shown on a patient's record.
public struct DistributionSlice: Hashable, Sendable {
    public let key: String
    public let label: String
    public let count: Int
    public let share: Double
}

/// Learns each patient's usual payment from their own history.
///
/// Deliberately not machine learning. With five to twenty data points per patient a
/// weighted tally is more accurate than any model, runs in microseconds, needs no
/// network, and — most importantly — can be explained in one line on screen.
///
/// **Weighting.** Each past payment carries
/// `0.85^rank × 0.5^(ageInDays / 90)`, where `rank` is 0 for the most recent
/// payment. Two decays rather than one, on purpose:
///
/// - the *day* decay keeps a habit from a patient seen twice a year from going stale;
/// - the *rank* decay is what lets a genuine change of habit take over after four or
///   five sessions, which calendar time alone would take months to do.
///
/// **Confidence** is the weighted share of the leading combination, damped by how
/// many times it was actually seen: `share × (1 − e^(−n / 2.5))`. The damping is what
/// stops a single payment from being announced as a habit.
///
/// The resulting behaviour, verified by the test suite:
///
/// - five identical payments → habit, confidence ≈ 0.86;
/// - two identical payments → no habit claimed, offered as "dernier paiement";
/// - five identical payments then one exception → the habit holds;
/// - four consecutive payments of a new amount → the new one takes over.
public enum HabitEngine {

    /// Payments older than this are ignored entirely.
    public static let historyWindow = 24
    /// Calendar-time half-life, in days.
    public static let dayHalfLife: Double = 90
    /// Per-rank decay factor.
    public static let rankDecay: Double = 0.85
    /// Sample-size damping constant.
    public static let dampingScale: Double = 2.5
    /// Minimum confidence before Cadence calls something a habit.
    public static let habitConfidenceThreshold: Double = 0.55
    /// Minimum number of occurrences before Cadence calls something a habit.
    public static let habitMinimumOccurrences = 3

    // MARK: - Advice

    public static func advise(
        payments: [Payment],
        patient: Patient?,
        settings: PracticeSettings,
        now: Date = Date()
    ) -> PaymentAdvice {
        let currency = settings.currencyCode
        let history = Array(
            payments
                .sorted { $0.paidAt > $1.paidAt }
                .prefix(historyWindow)
        )

        let fallbackAmount = patient?.defaultAmountCents ?? settings.defaultAmountCents
        let fallbackMethod = patient?.defaultMethodID ?? settings.defaultMethodID
        let fallbackBasis: PaymentBasis = patient?.defaultAmountCents != nil ? .patientDefault : .practiceDefault

        guard !history.isEmpty else {
            let primary = PaymentSuggestion(amountCents: fallbackAmount, methodID: fallbackMethod, currencyCode: currency)
            return PaymentAdvice(
                primary: primary,
                basis: fallbackBasis,
                confidence: 0,
                sampleSize: 0,
                alternatives: [],
                quickMethodSwitches: methodSwitches(for: primary, settings: settings)
            )
        }

        // Weighted tally over (amount, method) pairs.
        var scores: [PaymentSuggestion: Double] = [:]
        var counts: [PaymentSuggestion: Int] = [:]
        var total: Double = 0

        for (rank, payment) in history.enumerated() {
            let key = PaymentSuggestion(
                amountCents: payment.amountCents,
                methodID: payment.methodID,
                currencyCode: payment.currencyCode
            )
            let weight = self.weight(rank: rank, paidAt: payment.paidAt, now: now)
            scores[key, default: 0] += weight
            counts[key, default: 0] += 1
            total += weight
        }

        let ranked = scores.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            // Deterministic tie-break so the interface never flickers.
            return lhs.key.id < rhs.key.id
        }

        guard let leader = ranked.first, total > 0 else {
            let primary = PaymentSuggestion(amountCents: fallbackAmount, methodID: fallbackMethod, currencyCode: currency)
            return PaymentAdvice(
                primary: primary,
                basis: fallbackBasis,
                confidence: 0,
                sampleSize: history.count,
                alternatives: [],
                quickMethodSwitches: methodSwitches(for: primary, settings: settings)
            )
        }

        let share = leader.value / total
        let occurrences = counts[leader.key] ?? 0
        let damping = 1 - exp(-Double(occurrences) / dampingScale)
        let confidence = share * damping

        let alternatives = ranked
            .dropFirst()
            .prefix(3)
            .map(\.key)

        let isHabit = confidence >= habitConfidenceThreshold && occurrences >= habitMinimumOccurrences

        if isHabit {
            return PaymentAdvice(
                primary: leader.key,
                basis: .habit(occurrences: occurrences, outOf: history.count),
                confidence: confidence,
                sampleSize: history.count,
                alternatives: Array(alternatives),
                quickMethodSwitches: methodSwitches(for: leader.key, settings: settings)
            )
        }

        // No settled habit: the most recent payment is the honest default.
        let latest = history[0]
        let primary = PaymentSuggestion(
            amountCents: latest.amountCents,
            methodID: latest.methodID,
            currencyCode: latest.currencyCode
        )
        let others = ranked
            .map(\.key)
            .filter { $0 != primary }
            .prefix(3)

        return PaymentAdvice(
            primary: primary,
            basis: .lastPayment(on: latest.paidAt),
            confidence: confidence,
            sampleSize: history.count,
            alternatives: Array(others),
            quickMethodSwitches: methodSwitches(for: primary, settings: settings)
        )
    }

    /// `0.85^rank × 0.5^(ageInDays / 90)`, clamped so a clock skew cannot amplify a payment.
    static func weight(rank: Int, paidAt: Date, now: Date) -> Double {
        let ageDays = max(0, now.timeIntervalSince(paidAt) / 86_400)
        return pow(rankDecay, Double(rank)) * pow(0.5, ageDays / dayHalfLife)
    }

    private static func methodSwitches(for suggestion: PaymentSuggestion, settings: PracticeSettings) -> [PaymentSuggestion] {
        settings.activeMethods
            .filter { $0.id != suggestion.methodID }
            .map {
                PaymentSuggestion(
                    amountCents: suggestion.amountCents,
                    methodID: $0.id,
                    currencyCode: suggestion.currencyCode
                )
            }
    }

    // MARK: - Breakdown shown on a patient's record

    public static func amountDistribution(payments: [Payment], currencyCode: String = "EUR") -> [DistributionSlice] {
        distribution(
            payments: payments,
            key: { String($0.amountCents) },
            label: { Money(cents: $0.amountCents, currencyCode: currencyCode).formatted() }
        )
    }

    public static func methodDistribution(payments: [Payment], settings: PracticeSettings) -> [DistributionSlice] {
        distribution(
            payments: payments,
            key: { $0.methodID },
            label: { settings.methodLabel($0.methodID) }
        )
    }

    private static func distribution(
        payments: [Payment],
        key: (Payment) -> String,
        label: (Payment) -> String
    ) -> [DistributionSlice] {
        guard !payments.isEmpty else { return [] }
        var counts: [String: (label: String, count: Int)] = [:]
        for payment in payments {
            let identifier = key(payment)
            counts[identifier, default: (label(payment), 0)].count += 1
        }
        let total = Double(payments.count)
        return counts
            .map { DistributionSlice(key: $0.key, label: $0.value.label, count: $0.value.count, share: Double($0.value.count) / total) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.key < rhs.key
            }
    }
}
