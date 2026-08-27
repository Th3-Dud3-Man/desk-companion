import XCTest
@testable import CadenceCore

// MARK: - Matching calendar titles to patients

final class PatientMatcherTests: CadenceTestCase {

    private lazy var roster: [Patient] = [
            Patient(displayName: "Jean Dupont", firstName: "Jean", lastName: "Dupont"),
            Patient(displayName: "Chloé Müller", firstName: "Chloé", lastName: "Müller"),
            Patient(displayName: "Marc Lefèvre", firstName: "Marc", lastName: "Lefèvre"),
            Patient(displayName: "Marie Lefebvre", firstName: "Marie", lastName: "Lefebvre"),
    ]

    func testNoiseWordsAreStrippedFromTitles() {
        XCTAssertEqual(TextNormaliser.candidateName(fromEventTitle: "RDV Séance - Jean Dupont (visio)"), "jean dupont")
        XCTAssertEqual(TextNormaliser.candidateName(fromEventTitle: "Consultation Chloé Müller"), "chloe muller")
        XCTAssertEqual(TextNormaliser.candidateName(fromEventTitle: "14h00 Jean Dupont"), "jean dupont")
    }

    func testExactNameMatchesAutomatically() {
        let match = PatientMatcher.match(title: "Jean Dupont", patients: roster, rememberedPatientID: nil)
        XCTAssertTrue(match.confidence.linksAutomatically)
        XCTAssertNotNil(match.patientID)
    }

    func testAccentsAndCaseAreIgnored() {
        let match = PatientMatcher.match(title: "CHLOE MULLER", patients: roster, rememberedPatientID: nil)
        XCTAssertTrue(match.confidence.linksAutomatically)
        XCTAssertEqual(match.patientID, roster[1].id)
    }

    func testReversedNameOrderStillMatches() {
        let match = PatientMatcher.match(title: "Dupont Jean", patients: roster, rememberedPatientID: nil)
        XCTAssertTrue(match.confidence.linksAutomatically)
    }

    func testAmbiguousNamesAreNeverLinkedSilently() {
        // Lefèvre and Lefebvre are close enough that guessing would be reckless.
        let match = PatientMatcher.match(title: "Lefebre", patients: roster, rememberedPatientID: nil)
        XCTAssertFalse(match.confidence.linksAutomatically,
                       "when two patients are similarly close, Cadence must ask rather than guess")
        XCTAssertNil(match.patientID)
        XCTAssertGreaterThanOrEqual(match.candidates.count, 1, "but it should still offer the candidates")
    }

    func testUnrelatedTitleMatchesNobody() {
        let match = PatientMatcher.match(title: "Réunion d'équipe", patients: roster, rememberedPatientID: nil)
        XCTAssertNil(match.patientID)
        XCTAssertEqual(match.confidence, .none)
    }

    func testARememberedSpellingAlwaysWins() {
        let target = roster[0]
        let match = PatientMatcher.match(title: "JD - suivi", patients: roster, rememberedPatientID: target.id)
        XCTAssertEqual(match.patientID, target.id)
        XCTAssertEqual(match.confidence, .remembered)
    }
}

// MARK: - Rhythm

final class RhythmAnalyserTests: CadenceTestCase {

    private func consultations(everyDays gap: Int, count: Int) -> [Consultation] {
        (0..<count).map { index in
            let start = Calendar.cadence.date(byAdding: .day, value: -gap * index, to: date(2026, 8, 25, 14, 0))!
            return Consultation(title: "x", scheduledStart: start, scheduledEnd: start.addingTimeInterval(3_000))
        }
    }

    func testWeeklyRhythmIsDetected() {
        XCTAssertEqual(RhythmAnalyser.rhythm(of: consultations(everyDays: 7, count: 6)), .weekly)
    }

    func testFortnightlyRhythmIsDetected() {
        XCTAssertEqual(RhythmAnalyser.rhythm(of: consultations(everyDays: 14, count: 5)), .fortnightly)
    }

    func testMonthlyRhythmIsDetected() {
        XCTAssertEqual(RhythmAnalyser.rhythm(of: consultations(everyDays: 28, count: 5)), .monthly)
    }

    func testTooFewAppointmentsClaimNothing() {
        XCTAssertEqual(RhythmAnalyser.rhythm(of: consultations(everyDays: 7, count: 2)), .unknown)
    }

    func testScatteredAppointmentsAreCalledIrregular() {
        var list = consultations(everyDays: 7, count: 3)
        let far = Calendar.cadence.date(byAdding: .day, value: -200, to: date(2026, 8, 25))!
        list.append(Consultation(title: "x", scheduledStart: far, scheduledEnd: far.addingTimeInterval(3_000)))
        let another = Calendar.cadence.date(byAdding: .day, value: -400, to: date(2026, 8, 25))!
        list.append(Consultation(title: "x", scheduledStart: another, scheduledEnd: another.addingTimeInterval(3_000)))

        guard case .irregular = RhythmAnalyser.rhythm(of: list) else {
            return XCTFail("expected an irregular rhythm, got \(RhythmAnalyser.rhythm(of: list))")
        }
    }

    func testModeIsDeterministicOnTies() {
        XCTAssertEqual(RhythmAnalyser.mode(of: [3, 3, 5, 5]), 3)
        XCTAssertNil(RhythmAnalyser.mode(of: [Int]()))
    }
}

// MARK: - Patient profile

final class PatientProfileTests: CadenceTestCase {

    func testProfileSummarisesEverythingTheRecordShows() throws {
        let store = try makeMemoryStore()
        let now = date(2026, 8, 25, 20, 0)
        let patient = try store.createPatient(displayName: "Jean Dupont")

        // Six weekly Tuesday sessions at 14:00, one of them missed, all paid 70 € card.
        for week in 1...6 {
            let start = Calendar.cadence.date(byAdding: .day, value: -7 * week, to: date(2026, 8, 25, 14, 0))!
            let consultation = try store.createConsultation(
                patientID: patient.id, title: "Jean Dupont",
                start: start, end: start.addingTimeInterval(3_000)
            )
            if week == 3 {
                try store.setStatus(.absent, forConsultation: consultation.id)
            } else {
                try store.setStatus(.attended, forConsultation: consultation.id)
                _ = try store.recordPayment(consultationID: consultation.id, patientID: patient.id,
                                            amountCents: 7_000, methodID: "card", paidAt: start)
            }
        }
        _ = try store.createConsultation(patientID: patient.id, title: "Jean Dupont",
                                         start: date(2026, 8, 26, 14, 0), end: date(2026, 8, 26, 14, 50))

        let profile = try XCTUnwrap(try store.profile(forPatient: patient.id, now: now))

        XCTAssertEqual(profile.attended, 5)
        XCTAssertEqual(profile.absent, 1)
        XCTAssertEqual(profile.upcoming, 1)
        XCTAssertEqual(profile.paymentCount, 5)
        XCTAssertEqual(profile.totalCollectedCents, 35_000)
        XCTAssertEqual(profile.attendanceRate ?? 0, 5.0 / 6.0, accuracy: 0.0001)
        XCTAssertEqual(profile.rhythm, .weekly)
        XCTAssertEqual(profile.usualHour, 14)
        XCTAssertEqual(profile.usualWeekday, 3, "Tuesday")
        XCTAssertTrue(profile.advice.isHabit)
        XCTAssertEqual(profile.advice.primary.amountCents, 7_000)
        XCTAssertNotNil(profile.nextAppointment)
        XCTAssertTrue(profile.unpaidConsultations.isEmpty)
    }

    func testAttendedButUnpaidSessionsAppearOnTheRecord() throws {
        let store = try makeMemoryStore()
        let patient = try store.createPatient(displayName: "Jean Dupont")
        let consultation = try store.createConsultation(
            patientID: patient.id, title: "Jean Dupont",
            start: date(2026, 8, 20, 14, 0), end: date(2026, 8, 20, 14, 50)
        )
        try store.setStatus(.attended, forConsultation: consultation.id)

        let profile = try XCTUnwrap(try store.profile(forPatient: patient.id, now: date(2026, 8, 25)))
        XCTAssertEqual(profile.unpaidConsultations.map(\.id), [consultation.id])
    }
}

// MARK: - Undo

final class UndoStackTests: CadenceTestCase {

    func testUndoAndRedoRestoreAPayment() throws {
        let store = try makeMemoryStore()
        let stack = UndoStack()
        let patient = try store.createPatient(displayName: "Jean Dupont")

        let payment = try store.recordPayment(consultationID: nil, patientID: patient.id,
                                              amountCents: 7_000, methodID: "card")
        stack.register(
            label: "Paiement de 70 €",
            undo: { try store.deletePaymentSilently(payment.id) },
            redo: { try store.restorePayment(payment) }
        )

        XCTAssertTrue(stack.canUndo)
        XCTAssertEqual(stack.nextUndoLabel, "Paiement de 70 €")

        XCTAssertEqual(try stack.undo(), "Paiement de 70 €")
        XCTAssertEqual(try store.payments(forPatient: patient.id).count, 0)
        XCTAssertTrue(stack.canRedo)

        XCTAssertEqual(try stack.redo(), "Paiement de 70 €")
        XCTAssertEqual(try store.payments(forPatient: patient.id).count, 1)
    }

    func testStackIsBoundedAndNewWorkClearsRedo() throws {
        let stack = UndoStack()
        for index in 0..<(UndoStack.depth + 20) {
            stack.register(label: "action \(index)", undo: {}, redo: {})
        }
        XCTAssertEqual(stack.nextUndoLabel, "action \(UndoStack.depth + 19)")

        _ = try stack.undo()
        XCTAssertTrue(stack.canRedo)
        stack.register(label: "nouvelle action", undo: {}, redo: {})
        XCTAssertFalse(stack.canRedo, "doing something new must discard the redo branch")
    }

    func testAFailedUndoLeavesTheStackIntact() throws {
        struct Boom: Error {}
        let stack = UndoStack()
        stack.register(label: "action", undo: { throw Boom() }, redo: {})

        XCTAssertThrowsError(try stack.undo())
        XCTAssertTrue(stack.canUndo, "an undo that failed has not happened")
        XCTAssertFalse(stack.canRedo)
    }
}

// MARK: - Demo data

final class DemoDataTests: CadenceTestCase {

    func testDemoDataIsBelievableAndSelfContained() throws {
        let store = try makeMemoryStore()
        let now = date(2026, 8, 25, 12, 30)

        let created = try DemoData.install(into: store, now: now)
        XCTAssertEqual(created, 8)
        XCTAssertTrue(try DemoData.isInstalled(in: store))

        let patients = try store.allPatients(includeArchived: true)
        XCTAssertEqual(patients.count, 8)
        XCTAssertTrue(patients.allSatisfy(\.isDemo), "every demo row must be flagged as such")

        // Today is populated and looks like a real working day.
        let today = try store.consultations(onDay: now)
        XCTAssertEqual(today.count, 7)
        XCTAssertTrue(today.contains { $0.status == .attended })
        XCTAssertTrue(today.contains { $0.status == .absent })
        XCTAssertTrue(today.contains { !$0.status.isResolved })

        // At least one patient has a settled habit, which is the point of the demo.
        let settings = try store.settings()
        let withHabit = try patients.filter { patient in
            HabitEngine.advise(payments: try store.payments(forPatient: patient.id),
                               patient: patient, settings: settings, now: now).isHabit
        }
        XCTAssertGreaterThanOrEqual(withHabit.count, 3)

        // And something is left to do, so the "reste à traiter" affordance is visible.
        XCTAssertGreaterThan(try store.statistics(for: .day(containing: now)).unpaidAttended, 0)
    }

    func testDemoDataIsDeterministic() throws {
        let now = date(2026, 8, 25, 12, 30)
        let first = try makeMemoryStore()
        let second = try makeMemoryStore()
        try DemoData.install(into: first, now: now)
        try DemoData.install(into: second, now: now)

        XCTAssertEqual(
            try first.allPatients(includeArchived: true).map(\.displayName),
            try second.allPatients(includeArchived: true).map(\.displayName)
        )
        XCTAssertEqual(
            try first.statistics(for: .day(containing: now)).revenueCents,
            try second.statistics(for: .day(containing: now)).revenueCents
        )
    }

    func testRemovingDemoDataLeavesRealDataAlone() throws {
        let store = try makeMemoryStore()
        let now = date(2026, 8, 25, 12, 30)
        try DemoData.install(into: store, now: now)

        let real = try store.createPatient(displayName: "Vraie Patiente")
        let consultation = try store.createConsultation(patientID: real.id, title: "Vraie Patiente",
                                                        start: now, end: now.addingTimeInterval(3_000))
        _ = try store.recordPayment(consultationID: consultation.id, patientID: real.id,
                                    amountCents: 7_000, methodID: "card", paidAt: now)

        let inventory = try DemoData.inventory(in: store)
        XCTAssertEqual(inventory.patients, 8)

        try DemoData.remove(from: store)

        XCTAssertFalse(try DemoData.isInstalled(in: store))
        XCTAssertEqual(try store.allPatients(includeArchived: true).map(\.displayName), ["Vraie Patiente"])
        XCTAssertEqual(try store.payments(forPatient: real.id).count, 1)
        XCTAssertNotNil(try store.consultation(id: consultation.id))
    }
}

// MARK: - Payments that have not arrived yet

/// A transfer is agreed in the room and lands days later. Cadence records it at
/// once so it cannot be forgotten, keeps it out of the takings until it arrives,
/// and lets the user tick it off in one gesture.
final class PendingPaymentTests: CadenceTestCase {

    private func makePatient(_ store: CadenceStore) throws -> Patient {
        try store.createPatient(displayName: "Nadia Haddad")
    }

    func testTransfersAndChequesDoNotSettleImmediatelyByDefault() {
        XCTAssertFalse(PaymentMethod.transfer.settlesImmediately)
        XCTAssertFalse(PaymentMethod.cheque.settlesImmediately)
        XCTAssertTrue(PaymentMethod.cash.settlesImmediately)
        XCTAssertTrue(PaymentMethod.card.settlesImmediately)
    }

    func testAnOutstandingPaymentIsRecordedButNotCounted() throws {
        let store = try makeMemoryStore()
        let patient = try makePatient(store)
        let day = date(2026, 8, 25, 14, 0)

        let payment = try store.recordPayment(
            consultationID: nil, patientID: patient.id, amountCents: 4_000,
            methodID: "transfer", paidAt: day, isSettled: false
        )

        XCTAssertTrue(payment.isPending)
        XCTAssertEqual(try store.outstandingTotal(), 4_000)
        XCTAssertEqual(try store.outstandingCount(), 1)

        let statistics = try store.statistics(for: .day(containing: day))
        XCTAssertEqual(statistics.revenueCents, 0, "money that has not arrived is not takings")
        XCTAssertEqual(statistics.pendingCents, 4_000)
        XCTAssertEqual(statistics.announcedCents, 4_000)
    }

    func testTickingItOffMovesItIntoTheTakings() throws {
        let store = try makeMemoryStore()
        let patient = try makePatient(store)
        let agreed = date(2026, 8, 25, 14, 0)
        let received = date(2026, 8, 28, 9, 0)

        let payment = try store.recordPayment(
            consultationID: nil, patientID: patient.id, amountCents: 4_000,
            methodID: "transfer", paidAt: agreed, isSettled: false
        )
        try store.settlePayment(payment.id, at: received)

        let settled = try XCTUnwrap(try store.payment(id: payment.id))
        XCTAssertFalse(settled.isPending)
        XCTAssertEqual(settled.settledAt, received)
        XCTAssertEqual(try store.outstandingTotal(), 0)

        // It counts on the day it arrived, not the day it was agreed.
        XCTAssertEqual(try store.statistics(for: .day(containing: agreed)).revenueCents, 0)
        XCTAssertEqual(try store.statistics(for: .day(containing: received)).revenueCents, 4_000)
        // But the consultation it belongs to is still that first day's work.
        XCTAssertEqual(try store.statistics(for: .day(containing: agreed)).announcedCents, 4_000)
    }

    func testATickCanBeTakenBack() throws {
        let store = try makeMemoryStore()
        let patient = try makePatient(store)
        let payment = try store.recordPayment(
            consultationID: nil, patientID: patient.id, amountCents: 4_000,
            methodID: "transfer", paidAt: date(2026, 8, 25), isSettled: false
        )
        try store.settlePayment(payment.id)
        XCTAssertEqual(try store.outstandingCount(), 0)

        try store.unsettlePayment(payment.id)
        XCTAssertEqual(try store.outstandingCount(), 1, "a mistaken tick, or a cheque returned")
        XCTAssertTrue(try XCTUnwrap(try store.payment(id: payment.id)).isPending)
    }

    func testTheOutstandingListIsOldestFirst() throws {
        let store = try makeMemoryStore()
        let patient = try makePatient(store)
        for day in [25, 12, 19] {
            _ = try store.recordPayment(
                consultationID: nil, patientID: patient.id, amountCents: day * 100,
                methodID: "transfer", paidAt: date(2026, 8, day), isSettled: false
            )
        }
        let pending = try store.pendingPayments()
        XCTAssertEqual(pending.map(\.amountCents), [1_200, 1_900, 2_500],
                       "the one that has been waiting longest comes first")
        XCTAssertEqual(pending.first?.daysOutstanding(now: date(2026, 8, 26)), 14)
    }

    func testAnOutstandingPaymentStillCountsAsSettlingTheConsultation() throws {
        // The point is not to nag twice: a session with an announced transfer is not
        // in the "à traiter" list, it is in the "en attente de règlement" one.
        let store = try makeMemoryStore()
        let patient = try makePatient(store)
        let start = date(2026, 8, 25, 14, 0)
        let consultation = try store.createConsultation(
            patientID: patient.id, title: "Nadia Haddad", start: start, end: start.addingTimeInterval(3_000)
        )
        try store.setStatus(.attended, forConsultation: consultation.id)
        _ = try store.recordPayment(
            consultationID: consultation.id, patientID: patient.id, amountCents: 4_000,
            methodID: "transfer", paidAt: start, isSettled: false
        )

        let statistics = try store.statistics(for: .day(containing: start))
        XCTAssertEqual(statistics.unpaidAttended, 0)
        XCTAssertEqual(statistics.pendingCount, 1)

        let profile = try XCTUnwrap(try store.profile(forPatient: patient.id, now: start))
        XCTAssertTrue(profile.unpaidConsultations.isEmpty)
        XCTAssertEqual(profile.outstandingCents, 4_000)
        XCTAssertEqual(profile.totalCollectedCents, 0, "not collected until it arrives")
    }

    func testTheHabitEngineLearnsFromAgreedPaymentsNotOnlyReceivedOnes() throws {
        // What a patient habitually pays does not depend on the bank's timing.
        let store = try makeMemoryStore()
        let patient = try makePatient(store)
        for week in 1...4 {
            _ = try store.recordPayment(
                consultationID: nil, patientID: patient.id, amountCents: 9_000,
                methodID: "transfer",
                paidAt: Calendar.cadence.date(byAdding: .day, value: -7 * week, to: date(2026, 8, 25))!,
                isSettled: week > 1
            )
        }
        let advice = HabitEngine.advise(
            payments: try store.payments(forPatient: patient.id),
            patient: patient, settings: try store.settings(), now: date(2026, 8, 25)
        )
        XCTAssertTrue(advice.isHabit)
        XCTAssertEqual(advice.primary.amountCents, 9_000)
        XCTAssertEqual(advice.primary.methodID, "transfer")
    }

    func testExistingPaymentsAreConsideredReceivedAfterTheMigration() throws {
        // Anything recorded before settlement existed meant "received" at the time.
        let store = try makeFileStore()
        let patient = try makePatient(store)
        _ = try store.recordPayment(
            consultationID: nil, patientID: patient.id, amountCents: 7_000,
            methodID: "card", paidAt: date(2026, 8, 25)
        )
        store.close()

        let reopened = try makeFileStore()
        XCTAssertEqual(try reopened.outstandingCount(), 0)
        XCTAssertEqual(try reopened.statistics(for: .day(containing: date(2026, 8, 25))).revenueCents, 7_000)
    }
}

// MARK: - The end-of-month ledger

/// Going through the month's transactions, one payment method at a time, and
/// correcting what is wrong. Deleting an entry recorded in error must take exactly
/// that entry and nothing else.
final class LedgerTests: CadenceTestCase {

    private func populated() throws -> (CadenceStore, DateRange, [Payment]) {
        let store = try makeMemoryStore()
        let alice = try store.createPatient(displayName: "Alice Martin")
        let bruno = try store.createPatient(displayName: "Bruno Petit")

        var payments: [Payment] = []
        payments.append(try store.recordPayment(consultationID: nil, patientID: alice.id,
                                                amountCents: 7_000, methodID: "card",
                                                paidAt: date(2026, 8, 4, 10, 0)))
        payments.append(try store.recordPayment(consultationID: nil, patientID: bruno.id,
                                                amountCents: 4_000, methodID: "transfer",
                                                paidAt: date(2026, 8, 11, 10, 0), isSettled: false))
        payments.append(try store.recordPayment(consultationID: nil, patientID: alice.id,
                                                amountCents: 9_000, methodID: "transfer",
                                                paidAt: date(2026, 8, 18, 10, 0)))
        payments.append(try store.recordPayment(consultationID: nil, patientID: bruno.id,
                                                amountCents: 6_000, methodID: "cash",
                                                paidAt: date(2026, 8, 25, 10, 0)))
        // Outside the month, so it must never appear.
        _ = try store.recordPayment(consultationID: nil, patientID: alice.id,
                                    amountCents: 5_000, methodID: "cash",
                                    paidAt: date(2026, 7, 20, 10, 0))
        return (store, .month(containing: date(2026, 8, 15)), payments)
    }

    func testTheLedgerCoversExactlyThePeriod() throws {
        let (store, month, _) = try populated()
        XCTAssertEqual(try store.ledger(in: month).count, 4)
    }

    func testFilteringByPaymentMethod() throws {
        let (store, month, _) = try populated()
        let transfers = try store.ledger(in: month, methodID: "transfer")
        XCTAssertEqual(transfers.count, 2)
        XCTAssertEqual(transfers.reduce(0) { $0 + $1.amountCents }, 13_000)

        XCTAssertEqual(try store.ledger(in: month, methodID: "cash").count, 1)
        XCTAssertEqual(try store.ledger(in: month, methodID: "cheque").count, 0)
    }

    func testFilteringBySettlementState() throws {
        let (store, month, _) = try populated()
        XCTAssertEqual(try store.ledger(in: month, settlement: .pending).count, 1)
        XCTAssertEqual(try store.ledger(in: month, settlement: .settled).count, 3)

        // The combination the user actually asks for: "the transfers I am still owed".
        let owed = try store.ledger(in: month, methodID: "transfer", settlement: .pending)
        XCTAssertEqual(owed.count, 1)
        XCTAssertEqual(owed.first?.amountCents, 4_000)
    }

    func testOrdering() throws {
        let (store, month, _) = try populated()
        XCTAssertEqual(try store.ledger(in: month, order: .amountDescending).map(\.amountCents),
                       [9_000, 7_000, 6_000, 4_000])
        XCTAssertEqual(try store.ledger(in: month, order: .dateAscending).first?.amountCents, 7_000)
        XCTAssertEqual(try store.ledger(in: month, order: .dateDescending).first?.amountCents, 6_000)
    }

    func testOnlyTheMethodsActuallyUsedAreOffered() throws {
        let (store, month, _) = try populated()
        XCTAssertEqual(Set(try store.methodsUsed(in: month)), ["card", "transfer", "cash"])
    }

    func testDeletingAnEntryRecordedInErrorTakesNothingElse() throws {
        let (store, month, payments) = try populated()
        let mistake = payments[1]

        try store.deletePayment(mistake.id)

        let remaining = try store.ledger(in: month)
        XCTAssertEqual(remaining.count, 3)
        XCTAssertFalse(remaining.contains { $0.id == mistake.id })
        XCTAssertEqual(try store.outstandingCount(), 0, "it was the only outstanding one")
        // The other transfer is untouched.
        XCTAssertEqual(try store.ledger(in: month, methodID: "transfer").count, 1)
        // And the takings drop by exactly nothing, because it had never arrived.
        XCTAssertEqual(try store.statistics(for: month).revenueCents, 22_000)
    }

    func testDeletingASettledEntryRemovesItFromTheTakings() throws {
        let (store, month, payments) = try populated()
        let before = try store.statistics(for: month).revenueCents
        try store.deletePayment(payments[0].id)
        XCTAssertEqual(try store.statistics(for: month).revenueCents, before - 7_000)
    }

    func testTheFilteredTotalIsWhatTheScreenShows() throws {
        let (store, month, _) = try populated()
        for method in try store.methodsUsed(in: month) {
            let rows = try store.ledger(in: month, methodID: method)
            let total = rows.reduce(0) { $0 + $1.amountCents }
            let settled = rows.filter { !$0.isPending }.reduce(0) { $0 + $1.amountCents }
            let pending = rows.filter(\.isPending).reduce(0) { $0 + $1.amountCents }
            XCTAssertEqual(settled + pending, total, "\(method): the split must account for everything")
        }
    }
}
