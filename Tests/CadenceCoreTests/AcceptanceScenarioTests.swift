import XCTest
@testable import CadenceCore

/// The ten scenarios the brief asks to be genuinely exercised (§ 39), written as
/// tests rather than as a checklist, and run on every commit.
final class AcceptanceScenarioTests: CadenceTestCase {

    // MARK: Scenario 1 — create a patient

    func testScenario01_CreateAPatient() throws {
        let store = try makeFileStore()
        let patient = try store.createPatient(displayName: "Jean Dupont", phone: "06 12 34 56 78")

        XCTAssertEqual(try store.allPatients().count, 1)
        let reloaded = try XCTUnwrap(try store.patient(id: patient.id))
        XCTAssertEqual(reloaded.displayName, "Jean Dupont")
        XCTAssertEqual(reloaded.monogram, "JD")
        XCTAssertFalse(reloaded.isDemo)

        // The creation is in the audit trail.
        let actions = try store.actions(forEntity: patient.id)
        XCTAssertEqual(actions.first?.kind, .patientCreated)
    }

    // MARK: Scenario 2 — create or import an appointment

    func testScenario02_CreateAnAppointment() throws {
        let store = try makeFileStore()
        let patient = try store.createPatient(displayName: "Jean Dupont")
        let start = date(2026, 8, 25, 14, 0)

        let consultation = try store.createConsultation(
            patientID: patient.id, title: "Jean Dupont",
            start: start, end: start.addingTimeInterval(50 * 60)
        )

        let today = try store.consultations(onDay: start)
        XCTAssertEqual(today.count, 1)
        XCTAssertEqual(today.first?.id, consultation.id)
        XCTAssertEqual(today.first?.status, .scheduled)
        XCTAssertEqual(CadenceFormat.time(try XCTUnwrap(today.first).scheduledStart), "14:00")
    }

    /// The import path: the same event arriving twice must not duplicate.
    func testScenario02b_ImportingTheSameEventTwiceDoesNotDuplicate() throws {
        let store = try makeFileStore()
        let patient = try store.createPatient(displayName: "Jean Dupont")
        let start = date(2026, 8, 25, 14, 0)

        for _ in 0..<2 {
            let existing = try store.consultation(occurrenceKey: "event-1|\(Int(start.timeIntervalSince1970))")
            let consultation = Consultation(
                id: existing?.id ?? UUID(),
                patientID: patient.id,
                title: "Jean Dupont",
                source: .calendar,
                externalEventID: "event-1",
                externalCalendarID: "cal-1",
                occurrenceKey: "event-1|\(Int(start.timeIntervalSince1970))",
                scheduledStart: start,
                scheduledEnd: start.addingTimeInterval(3_000),
                status: existing?.status ?? .scheduled,
                syncState: .synced
            )
            try store.upsertConsultationSilently(consultation)
        }

        XCTAssertEqual(try store.consultations(onDay: start).count, 1)
    }

    // MARK: Scenario 3 — mark the patient present

    func testScenario03_MarkPresent() throws {
        let store = try makeFileStore()
        let (_, consultation) = try makeAppointment(in: store)

        try store.setStatus(.attended, forConsultation: consultation.id)

        let updated = try XCTUnwrap(try store.consultation(id: consultation.id))
        XCTAssertEqual(updated.status, .attended)
        XCTAssertTrue(updated.status.invitesPayment)
        XCTAssertNil(updated.actualStart, "marking presence must not invent an arrival time")
    }

    // MARK: Scenario 4 — record 70 € by card

    func testScenario04_RecordSeventyEurosByCard() throws {
        let store = try makeFileStore()
        let (patient, consultation) = try makeAppointment(in: store)
        try store.setStatus(.attended, forConsultation: consultation.id)

        let payment = try store.recordPayment(
            consultationID: consultation.id, patientID: patient.id,
            amountCents: 7_000, methodID: "card"
        )

        XCTAssertEqual(plainSpaces(payment.money.formatted()), "70 €")
        XCTAssertEqual(try store.payments(forConsultation: consultation.id).count, 1)
        XCTAssertEqual(try store.totalCollected(forPatient: patient.id), 7_000)
    }

    // MARK: Scenarios 5 and 6 — quit and reopen; the data is still there

    func testScenario05And06_DataSurvivesClosingAndReopening() throws {
        let patientID: UUID
        let consultationID: UUID

        do {
            let store = try makeFileStore()
            let patient = try store.createPatient(displayName: "Jean Dupont", phone: "06 12 34 56 78")
            let start = date(2026, 8, 25, 14, 0)
            let consultation = try store.createConsultation(
                patientID: patient.id, title: "Jean Dupont",
                start: start, end: start.addingTimeInterval(3_000)
            )
            try store.setStatus(.attended, forConsultation: consultation.id)
            _ = try store.recordPayment(
                consultationID: consultation.id, patientID: patient.id,
                amountCents: 7_000, methodID: "card", paidAt: start.addingTimeInterval(3_000)
            )
            patientID = patient.id
            consultationID = consultation.id
            store.close()                       // as if the application had quit
        }

        // A brand new process would do exactly this.
        let reopened = try makeFileStore()
        let patient = try XCTUnwrap(try reopened.patient(id: patientID))
        XCTAssertEqual(patient.displayName, "Jean Dupont")
        XCTAssertEqual(patient.phone, "06 12 34 56 78")

        let consultation = try XCTUnwrap(try reopened.consultation(id: consultationID))
        XCTAssertEqual(consultation.status, .attended)

        let payments = try reopened.payments(forPatient: patientID)
        XCTAssertEqual(payments.count, 1)
        XCTAssertEqual(payments.first?.amountCents, 7_000)
        XCTAssertEqual(payments.first?.methodID, "card")

        // Settings survive too.
        XCTAssertEqual(try reopened.settings().currencyCode, "EUR")
    }

    // MARK: Scenario 7 — repeat the payment; the habit emerges

    func testScenario07_TheHabitEmergesFromRepeatedPayments() throws {
        let store = try makeFileStore()
        let patient = try store.createPatient(displayName: "Jean Dupont")
        let settings = try store.settings()
        let now = date(2026, 8, 25, 18, 0)

        var habitAppearedAfter: Int?

        for week in 1...5 {
            let sessionDate = Calendar.cadence.date(byAdding: .day, value: -7 * (6 - week), to: now)!
            let consultation = try store.createConsultation(
                patientID: patient.id, title: "Jean Dupont",
                start: sessionDate, end: sessionDate.addingTimeInterval(3_000)
            )
            try store.setStatus(.attended, forConsultation: consultation.id)
            _ = try store.recordPayment(
                consultationID: consultation.id, patientID: patient.id,
                amountCents: 7_000, methodID: "card", paidAt: sessionDate
            )

            let advice = HabitEngine.advise(
                payments: try store.payments(forPatient: patient.id),
                patient: patient, settings: settings, now: now
            )
            if advice.isHabit && habitAppearedAfter == nil { habitAppearedAfter = week }
        }

        XCTAssertEqual(habitAppearedAfter, 3, "the habit should be recognised from the third identical payment")

        let advice = HabitEngine.advise(
            payments: try store.payments(forPatient: patient.id),
            patient: patient, settings: settings, now: now
        )
        XCTAssertTrue(advice.isHabit)
        XCTAssertEqual(plainSpaces(advice.primary.money.formatted()), "70 €")
        XCTAssertEqual(settings.methodLabel(advice.primary.methodID), "Carte")
        XCTAssertEqual(advice.basis.shortLabel, "Paiement habituel")
        XCTAssertGreaterThan(advice.confidence, 0.8)
    }

    // MARK: Scenario 8 — an absence asks for nothing

    func testScenario08_AnAbsenceNeverAsksForAPayment() throws {
        let store = try makeFileStore()
        let (_, consultation) = try makeAppointment(in: store)

        try store.setStatus(.absent, forConsultation: consultation.id)

        let updated = try XCTUnwrap(try store.consultation(id: consultation.id))
        XCTAssertEqual(updated.status, .absent)
        XCTAssertFalse(updated.status.invitesPayment, "an absence must not invite a payment")
        XCTAssertTrue(updated.status.isResolved, "and it must count as dealt with, not as pending work")
        XCTAssertEqual(try store.payments(forConsultation: consultation.id).count, 0)

        // It must not show up in the "attended but unpaid" list either.
        let statistics = try store.statistics(for: .day(containing: updated.scheduledStart))
        XCTAssertEqual(statistics.unpaidAttended, 0)
        XCTAssertEqual(statistics.absent, 1)
    }

    // MARK: Scenario 9 — the statistics match what was recorded

    func testScenario09_StatisticsMatchTheRecordedData() throws {
        let store = try makeFileStore()
        let day = date(2026, 8, 25)

        let alice = try store.createPatient(displayName: "Alice Martin")
        let bruno = try store.createPatient(displayName: "Bruno Petit")
        let chloe = try store.createPatient(displayName: "Chloé Nguyen")

        // Two paid consultations, one absence, one still to come.
        let first = try store.createConsultation(patientID: alice.id, title: "Alice Martin",
                                                 start: date(2026, 8, 25, 9, 0),
                                                 end: date(2026, 8, 25, 9, 50))
        try store.setStatus(.attended, forConsultation: first.id)
        _ = try store.recordPayment(consultationID: first.id, patientID: alice.id,
                                    amountCents: 7_000, methodID: "card",
                                    paidAt: date(2026, 8, 25, 9, 50))

        let second = try store.createConsultation(patientID: bruno.id, title: "Bruno Petit",
                                                  start: date(2026, 8, 25, 10, 0),
                                                  end: date(2026, 8, 25, 10, 50))
        try store.setStatus(.attended, forConsultation: second.id)
        _ = try store.recordPayment(consultationID: second.id, patientID: bruno.id,
                                    amountCents: 6_000, methodID: "cash",
                                    paidAt: date(2026, 8, 25, 10, 50))

        let third = try store.createConsultation(patientID: chloe.id, title: "Chloé Nguyen",
                                                 start: date(2026, 8, 25, 11, 0),
                                                 end: date(2026, 8, 25, 11, 50))
        try store.setStatus(.absent, forConsultation: third.id)

        _ = try store.createConsultation(patientID: alice.id, title: "Alice Martin",
                                         start: date(2026, 8, 25, 16, 0),
                                         end: date(2026, 8, 25, 16, 50))

        let statistics = try store.statistics(for: .day(containing: day))

        XCTAssertEqual(statistics.planned, 4)
        XCTAssertEqual(statistics.attended, 2)
        XCTAssertEqual(statistics.absent, 1)
        XCTAssertEqual(statistics.pending, 1)
        XCTAssertEqual(statistics.revenueCents, 13_000, "70 € + 60 € must be exactly 130 €")
        XCTAssertEqual(plainSpaces(statistics.revenue().formatted()), "130 €")
        XCTAssertEqual(statistics.paymentCount, 2)
        XCTAssertEqual(statistics.unpaidAttended, 0)
        XCTAssertEqual(statistics.attendanceRate ?? 0, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(statistics.averagePerAttendedCents, 6_500)

        let methods = Dictionary(uniqueKeysWithValues: statistics.byMethod.map { ($0.methodID, $0) })
        XCTAssertEqual(methods["card"]?.totalCents, 7_000)
        XCTAssertEqual(methods["cash"]?.totalCents, 6_000)
        XCTAssertEqual(methods.values.reduce(0) { $0 + $1.totalCents }, statistics.revenueCents,
                       "the breakdown must add up to the total")

        // And the same figures reached a different way.
        let payments = try store.payments(in: .day(containing: day))
        XCTAssertEqual(payments.reduce(0) { $0 + $1.amountCents }, statistics.revenueCents)
    }

    func testScenario09b_UnpaidAttendedConsultationsAreCounted() throws {
        let store = try makeFileStore()
        let patient = try store.createPatient(displayName: "Alice Martin")
        let consultation = try store.createConsultation(
            patientID: patient.id, title: "Alice Martin",
            start: date(2026, 8, 25, 9, 0), end: date(2026, 8, 25, 9, 50)
        )
        try store.setStatus(.attended, forConsultation: consultation.id)

        let statistics = try store.statistics(for: .day(containing: date(2026, 8, 25)))
        XCTAssertEqual(statistics.attended, 1)
        XCTAssertEqual(statistics.unpaidAttended, 1, "an attended session with no payment is work still to do")
        XCTAssertEqual(statistics.revenueCents, 0)
    }

    // MARK: Scenario 10 — everything works with no network

    func testScenario10_EverythingWorksWithoutANetwork() throws {
        // There is nothing to disable: CadenceCore contains no networking whatsoever.
        // This test asserts the shape of that claim — every operation the user needs
        // during a day runs against the local file and nothing else.
        let store = try makeFileStore()
        let patient = try store.createPatient(displayName: "Jean Dupont")
        let start = date(2026, 8, 25, 14, 0)
        let consultation = try store.createConsultation(
            patientID: patient.id, title: "Jean Dupont", start: start, end: start.addingTimeInterval(3_000)
        )

        XCTAssertNoThrow(try store.consultations(onDay: start))
        XCTAssertNoThrow(try store.allPatients())
        XCTAssertNoThrow(try store.setStatus(.attended, forConsultation: consultation.id))
        XCTAssertNoThrow(try store.recordPayment(consultationID: consultation.id, patientID: patient.id,
                                                 amountCents: 7_000, methodID: "card", paidAt: start))
        XCTAssertNoThrow(try store.profile(forPatient: patient.id))
        XCTAssertNoThrow(try store.statistics(for: .day(containing: start)))
        XCTAssertNoThrow(try store.exportPaymentsCSV(range: .month(containing: start)))
        XCTAssertNoThrow(try store.recentActions())

        // The database file is the only thing that had to exist.
        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    // MARK: - Helpers

    private func makeAppointment(in store: CadenceStore) throws -> (Patient, Consultation) {
        let patient = try store.createPatient(displayName: "Jean Dupont")
        let start = date(2026, 8, 25, 14, 0)
        let consultation = try store.createConsultation(
            patientID: patient.id, title: "Jean Dupont",
            start: start, end: start.addingTimeInterval(50 * 60)
        )
        return (patient, consultation)
    }
}
