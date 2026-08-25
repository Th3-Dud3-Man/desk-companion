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
