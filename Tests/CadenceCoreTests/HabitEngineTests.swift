import XCTest
@testable import CadenceCore

/// The habit engine is the one piece of "intelligence" in Cadence, so its behaviour
/// is pinned down precisely: it must be confident when the evidence is there,
/// silent when it is not, unmoved by a one-off exception, and quick to follow a
/// genuine change.
final class HabitEngineTests: XCTestCase {

    private let settings = PracticeSettings.default
    private let now = Date(timeIntervalSince1970: 1_800_000_000)   // fixed clock
    private lazy var patientID = UUID()

    private func payment(_ euros: Int, _ method: String, daysAgo: Double) -> Payment {
        Payment(
            patientID: patientID,
            amountCents: euros * 100,
            methodID: method,
            paidAt: now.addingTimeInterval(-daysAgo * 86_400)
        )
    }

    /// Weekly sessions, `count` of them, all identical.
    private func weeklyHistory(_ euros: Int, _ method: String, count: Int, startingDaysAgo: Double = 0) -> [Payment] {
        (0..<count).map { payment(euros, method, daysAgo: startingDaysAgo + Double($0) * 7) }
    }

    // MARK: - No history

    func testNoHistoryFallsBackToPracticeTariff() {
        let advice = HabitEngine.advise(payments: [], patient: nil, settings: settings, now: now)
        XCTAssertEqual(advice.primary.amountCents, settings.defaultAmountCents)
        XCTAssertEqual(advice.primary.methodID, settings.defaultMethodID)
        XCTAssertEqual(advice.basis, .practiceDefault)
        XCTAssertFalse(advice.isHabit)
        XCTAssertEqual(advice.sampleSize, 0)
        XCTAssertFalse(advice.quickMethodSwitches.isEmpty, "the user must always have alternatives to click")
    }

    func testPatientTariffBeatsPracticeTariffWhenThereIsNoHistory() {
        let patient = Patient(displayName: "Nouvelle patiente", defaultAmountCents: 8_000, defaultMethodID: "cash")
        let advice = HabitEngine.advise(payments: [], patient: patient, settings: settings, now: now)
        XCTAssertEqual(advice.primary.amountCents, 8_000)
        XCTAssertEqual(advice.primary.methodID, "cash")
        XCTAssertEqual(advice.basis, .patientDefault)
    }

    // MARK: - The brief's worked example

    func testFiveIdenticalPaymentsBecomeAHabit() {
        let advice = HabitEngine.advise(
            payments: weeklyHistory(70, "card", count: 5),
            patient: nil, settings: settings, now: now
        )
        XCTAssertTrue(advice.isHabit)
        XCTAssertEqual(advice.primary.amountCents, 7_000)
        XCTAssertEqual(advice.primary.methodID, "card")
        XCTAssertEqual(advice.basis, .habit(occurrences: 5, outOf: 5))
        XCTAssertGreaterThan(advice.confidence, 0.85)
    }

    func testThreeIdenticalPaymentsAreTheEarliestAHabitIsClaimed() {
        let two = HabitEngine.advise(payments: weeklyHistory(70, "card", count: 2),
                                     patient: nil, settings: settings, now: now)
        XCTAssertFalse(two.isHabit, "two payments is not yet a habit")
        if case .lastPayment = two.basis {} else { XCTFail("expected the last payment as the honest fallback") }
        XCTAssertEqual(two.primary.amountCents, 7_000, "…but it should still propose what they last paid")

        let three = HabitEngine.advise(payments: weeklyHistory(70, "card", count: 3),
                                       patient: nil, settings: settings, now: now)
        XCTAssertTrue(three.isHabit)
        XCTAssertEqual(three.basis, .habit(occurrences: 3, outOf: 3))
    }

    // MARK: - Stability

    func testASingleExceptionDoesNotDestroyTheHabit() {
        // Five weeks of 70 € by card, then one cash payment of 60 € this week.
        var history = weeklyHistory(70, "card", count: 5, startingDaysAgo: 7)
        history.insert(payment(60, "cash", daysAgo: 0), at: 0)

        let advice = HabitEngine.advise(payments: history, patient: nil, settings: settings, now: now)
        XCTAssertTrue(advice.isHabit, "one exception must not redefine the patient's habit")
        XCTAssertEqual(advice.primary.amountCents, 7_000)
        XCTAssertEqual(advice.primary.methodID, "card")
        XCTAssertTrue(
            advice.alternatives.contains(PaymentSuggestion(amountCents: 6_000, methodID: "cash")),
            "the exception should still be offered as a one-click alternative"
        )
    }

    func testTwoExceptionsAmongManyStillDoNotDestroyTheHabit() {
        var history = weeklyHistory(70, "card", count: 8, startingDaysAgo: 14)
        history.insert(payment(70, "cash", daysAgo: 0), at: 0)
        history.insert(payment(60, "card", daysAgo: 7), at: 1)

        let advice = HabitEngine.advise(payments: history, patient: nil, settings: settings, now: now)
        XCTAssertTrue(advice.isHabit)
        XCTAssertEqual(advice.primary, PaymentSuggestion(amountCents: 7_000, methodID: "card"))
    }

    // MARK: - Adaptation

    func testARealChangeOfHabitTakesOver() {
        // Five old sessions at 70 € card, then five recent ones at 80 € card.
        var history = weeklyHistory(70, "card", count: 5, startingDaysAgo: 35)
        history.insert(contentsOf: weeklyHistory(80, "card", count: 5), at: 0)

        let advice = HabitEngine.advise(payments: history, patient: nil, settings: settings, now: now)
        XCTAssertEqual(advice.primary.amountCents, 8_000, "the new amount must win once it is established")
        XCTAssertTrue(advice.isHabit)
    }

    func testDuringAChangeTheEngineStopsClaimingAHabitRatherThanGuessing() {
        // Five old at 70, only two recent at 80: genuinely ambiguous.
        var history = weeklyHistory(70, "card", count: 5, startingDaysAgo: 14)
        history.insert(contentsOf: weeklyHistory(80, "card", count: 2), at: 0)

        let advice = HabitEngine.advise(payments: history, patient: nil, settings: settings, now: now)
        XCTAssertFalse(advice.isHabit, "while the pattern is ambiguous, Cadence must not assert a habit")
        XCTAssertEqual(advice.primary.amountCents, 8_000, "it proposes the most recent payment instead")
        if case .lastPayment = advice.basis {} else { XCTFail("expected .lastPayment") }
    }

    // MARK: - Method vs amount

    func testMethodIsPartOfTheHabitNotJustTheAmount() {
        let history = weeklyHistory(70, "cheque", count: 6)
        let advice = HabitEngine.advise(payments: history, patient: nil, settings: settings, now: now)
        XCTAssertEqual(advice.primary.methodID, "cheque")
        XCTAssertTrue(advice.quickMethodSwitches.allSatisfy { $0.amountCents == 7_000 })
        XCTAssertFalse(advice.quickMethodSwitches.contains { $0.methodID == "cheque" },
                       "the suggested method must not be repeated in the alternatives")
    }

    // MARK: - Determinism and robustness

    func testAdviceIsDeterministicForATie() {
        let history = [
            payment(70, "card", daysAgo: 7),
            payment(70, "cash", daysAgo: 7),
        ]
        let first = HabitEngine.advise(payments: history, patient: nil, settings: settings, now: now)
        for _ in 0..<20 {
            let again = HabitEngine.advise(payments: history, patient: nil, settings: settings, now: now)
            XCTAssertEqual(first.primary, again.primary, "a tie must always resolve the same way")
        }
    }

    func testFutureDatedPaymentIsNotAmplified() {
        // A payment dated in the future (clock skew, manual entry) must not outweigh history.
        var history = weeklyHistory(70, "card", count: 5)
        history.insert(payment(200, "cash", daysAgo: -30), at: 0)
        let advice = HabitEngine.advise(payments: history, patient: nil, settings: settings, now: now)
        XCTAssertEqual(HabitEngine.weight(rank: 0, paidAt: now.addingTimeInterval(86_400 * 30), now: now), 1.0,
                       accuracy: 0.0001)
        XCTAssertEqual(advice.primary.amountCents, 7_000)
    }

    func testHistoryIsCappedSoAncientPaymentsCannotOutvoteRecentOnes() {
        // Thirty ancient sessions at 50 €, five recent at 70 €.
        var history = weeklyHistory(50, "cash", count: 30, startingDaysAgo: 35)
        history.insert(contentsOf: weeklyHistory(70, "card", count: 5), at: 0)
        let advice = HabitEngine.advise(payments: history, patient: nil, settings: settings, now: now)
        XCTAssertEqual(advice.sampleSize, HabitEngine.historyWindow)
        XCTAssertEqual(advice.primary.amountCents, 7_000)
    }

    // MARK: - Distributions

    func testDistributionsSummariseTheHistory() {
        var history = weeklyHistory(70, "card", count: 6)
        history.append(payment(70, "cash", daysAgo: 60))
        history.append(payment(80, "card", daysAgo: 67))

        let amounts = HabitEngine.amountDistribution(payments: history)
        XCTAssertEqual(amounts.first?.count, 7)
        XCTAssertEqual(amounts.first?.share ?? 0, 7.0 / 8.0, accuracy: 0.0001)

        let methods = HabitEngine.methodDistribution(payments: history, settings: settings)
        XCTAssertEqual(methods.first?.label, "Carte")
        XCTAssertEqual(methods.first?.count, 7)
    }
}
