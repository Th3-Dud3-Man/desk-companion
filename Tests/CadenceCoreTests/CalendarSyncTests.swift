import XCTest
@testable import CadenceCore

/// Synchronisation is where this kind of application usually goes wrong: duplicated
/// weekly appointments, and recorded work quietly destroyed when an event moves.
/// Both are tested for directly.
final class CalendarSyncTests: CadenceTestCase {

    private let calendarID = "cal-cabinet"
    private lazy var window = DateRange(start: date(2026, 8, 1), end: date(2026, 10, 1))

    private func event(
        _ identifier: String,
        title: String,
        _ start: Date,
        minutes: Int = 50,
        occurrence: Date? = nil,
        calendar: String? = nil
    ) -> CalendarImportEvent {
        CalendarImportEvent(
            eventIdentifier: identifier,
            calendarIdentifier: calendar ?? calendarID,
            title: title,
            start: start,
            end: start.addingTimeInterval(Double(minutes) * 60),
            occurrenceDate: occurrence
        )
    }

    @discardableResult
    private func sync(_ store: CadenceStore, _ events: [CalendarImportEvent]) throws -> CalendarSyncOutcome {
        try store.applyCalendarSync(events: events, calendarIDs: [calendarID], window: window)
    }

    // MARK: Import and de-duplication

    func testEventsAreImportedAndMatchedToPatients() throws {
        let store = try makeMemoryStore()
        let patient = try store.createPatient(displayName: "Jean Dupont")

        let outcome = try sync(store, [
            event("e1", title: "Séance - Jean Dupont", date(2026, 8, 25, 14, 0)),
            event("e2", title: "Réunion d'équipe", date(2026, 8, 25, 17, 0)),
        ])

        XCTAssertEqual(outcome.inserted, 2)
        XCTAssertEqual(outcome.linked, 1)
        XCTAssertEqual(outcome.unmatched, 1)

        let consultations = try store.consultations(onDay: date(2026, 8, 25))
        XCTAssertEqual(consultations.count, 2)
        XCTAssertEqual(consultations.first?.patientID, patient.id)
        XCTAssertEqual(consultations.first?.syncState, .synced)
        XCTAssertEqual(try store.unassignedConsultations(in: window).count, 1)
    }

    func testSynchronisingTwiceChangesNothing() throws {
        let store = try makeMemoryStore()
        _ = try store.createPatient(displayName: "Jean Dupont")
        let events = [event("e1", title: "Jean Dupont", date(2026, 8, 25, 14, 0))]

        XCTAssertEqual(try sync(store, events).inserted, 1)
        let second = try sync(store, events)
        XCTAssertEqual(second.inserted, 0)
        XCTAssertEqual(second.updated, 0)
        XCTAssertEqual(second.removed, 0)
        XCTAssertEqual(try store.consultations(in: window).count, 1)
    }

    func testRecurringOccurrencesAreDistinctRowsNotDuplicates() throws {
        let store = try makeMemoryStore()
        _ = try store.createPatient(displayName: "Jean Dupont")

        // One recurring event: the same identifier every week.
        let weekly = (0..<4).map { week -> CalendarImportEvent in
            let start = Calendar.cadence.date(byAdding: .day, value: 7 * week, to: date(2026, 8, 4, 14, 0))!
            return event("recurring", title: "Jean Dupont", start)
        }

        XCTAssertEqual(try sync(store, weekly).inserted, 4, "each occurrence is its own appointment")
        XCTAssertEqual(try sync(store, weekly).changeCount, 0, "and re-importing them changes nothing")
        XCTAssertEqual(try store.consultations(in: window).count, 4)
    }

    // MARK: Changes

    func testMovingAnUntouchedAppointmentUpdatesItInPlace() throws {
        let store = try makeMemoryStore()
        _ = try store.createPatient(displayName: "Jean Dupont")
        let original = date(2026, 8, 25, 14, 0)
        try sync(store, [event("e1", title: "Jean Dupont", original)])

        // Rescheduled to 16:00. The occurrence date does not move, so it is the same slot.
        let outcome = try sync(store, [
            event("e1", title: "Jean Dupont", date(2026, 8, 25, 16, 0), occurrence: original)
        ])

        XCTAssertEqual(outcome.updated, 1)
        XCTAssertEqual(outcome.inserted, 0)
        let consultations = try store.consultations(in: window)
        XCTAssertEqual(consultations.count, 1, "moving an appointment must not create a second one")
        XCTAssertEqual(consultations.first?.scheduledStart, date(2026, 8, 25, 16, 0))
    }

    func testARenamedEventUpdatesTheTitle() throws {
        let store = try makeMemoryStore()
        try sync(store, [event("e1", title: "Nouveau patient", date(2026, 8, 25, 14, 0))])
        try sync(store, [event("e1", title: "Jean Dupont", date(2026, 8, 25, 14, 0))])
        XCTAssertEqual(try store.consultations(in: window).first?.title, "Jean Dupont")
    }

    // MARK: Protecting recorded work

    func testMovingAnAppointmentThatAlreadyHasAPaymentRaisesAConflict() throws {
        let store = try makeMemoryStore()
        let patient = try store.createPatient(displayName: "Jean Dupont")
        let original = date(2026, 8, 25, 14, 0)
        try sync(store, [event("e1", title: "Jean Dupont", original)])

        let consultation = try XCTUnwrap(try store.consultations(in: window).first)
        try store.setStatus(.attended, forConsultation: consultation.id)
        _ = try store.recordPayment(consultationID: consultation.id, patientID: patient.id,
                                    amountCents: 7_000, methodID: "card", paidAt: original)

        let outcome = try sync(store, [
            event("e1", title: "Jean Dupont", date(2026, 8, 25, 9, 0), occurrence: original)
        ])

        XCTAssertEqual(outcome.conflicted, 1)
        XCTAssertEqual(outcome.updated, 0)

        let after = try XCTUnwrap(try store.consultation(id: consultation.id))
        XCTAssertEqual(after.scheduledStart, original, "the recorded slot must not be rewritten")
        XCTAssertEqual(after.syncState, .conflict)
        XCTAssertEqual(after.status, .attended)
        XCTAssertEqual(try store.payments(forConsultation: consultation.id).count, 1)
        XCTAssertEqual(try store.consultationsWithSyncIssues().count, 1)
    }

    func testDeletingAnEventWithRecordedWorkKeepsTheRecord() throws {
        let store = try makeMemoryStore()
        let patient = try store.createPatient(displayName: "Jean Dupont")
        try sync(store, [event("e1", title: "Jean Dupont", date(2026, 8, 25, 14, 0))])

        let consultation = try XCTUnwrap(try store.consultations(in: window).first)
        try store.setStatus(.attended, forConsultation: consultation.id)
        _ = try store.recordPayment(consultationID: consultation.id, patientID: patient.id,
                                    amountCents: 7_000, methodID: "card")

        let outcome = try sync(store, [])

        XCTAssertEqual(outcome.removed, 0)
        XCTAssertEqual(outcome.conflicted, 1)
        let after = try XCTUnwrap(try store.consultation(id: consultation.id))
        XCTAssertEqual(after.syncState, .orphaned)
        XCTAssertEqual(try store.payments(forPatient: patient.id).count, 1,
                       "a payment must never disappear because a calendar event did")
    }

    func testDeletingAnUntouchedEventRemovesItQuietly() throws {
        let store = try makeMemoryStore()
        try sync(store, [event("e1", title: "Jean Dupont", date(2026, 8, 25, 14, 0))])
        let outcome = try sync(store, [])
        XCTAssertEqual(outcome.removed, 1)
        XCTAssertEqual(try store.consultations(in: window).count, 0)
    }

    func testAnAbsenceIsAlsoProtected() throws {
        let store = try makeMemoryStore()
        try sync(store, [event("e1", title: "Jean Dupont", date(2026, 8, 25, 14, 0))])
        let consultation = try XCTUnwrap(try store.consultations(in: window).first)
        try store.setStatus(.absent, forConsultation: consultation.id)

        try sync(store, [])
        XCTAssertNotNil(try store.consultation(id: consultation.id))
        XCTAssertEqual(try store.consultation(id: consultation.id)?.syncState, .orphaned)
    }

    // MARK: Scope

    func testEventsFromCalendarsTheUserDidNotChooseAreIgnored() throws {
        let store = try makeMemoryStore()
        try sync(store, [
            event("e1", title: "Jean Dupont", date(2026, 8, 25, 14, 0)),
            event("e2", title: "Yoga", date(2026, 8, 25, 19, 0), calendar: "cal-perso"),
        ])
        XCTAssertEqual(try store.consultations(in: window).count, 1)
    }

    func testManualAppointmentsAreNeverTouchedBySynchronisation() throws {
        let store = try makeMemoryStore()
        let patient = try store.createPatient(displayName: "Jean Dupont")
        let manual = try store.createConsultation(
            patientID: patient.id, title: "Jean Dupont",
            start: date(2026, 8, 25, 11, 0), end: date(2026, 8, 25, 11, 50)
        )

        try sync(store, [])
        XCTAssertNotNil(try store.consultation(id: manual.id))
        XCTAssertEqual(try store.consultation(id: manual.id)?.syncState, .local)
    }

    func testTurningACalendarOffRemovesOnlyUntouchedAppointments() throws {
        let store = try makeMemoryStore()
        let patient = try store.createPatient(displayName: "Jean Dupont")
        try sync(store, [
            event("e1", title: "Jean Dupont", date(2026, 8, 25, 14, 0)),
            event("e2", title: "Jean Dupont", date(2026, 8, 26, 14, 0)),
        ])

        let kept = try XCTUnwrap(try store.consultations(onDay: date(2026, 8, 25)).first)
        try store.setStatus(.attended, forConsultation: kept.id)
        _ = try store.recordPayment(consultationID: kept.id, patientID: patient.id,
                                    amountCents: 7_000, methodID: "card")

        XCTAssertEqual(try store.purgeCalendar(calendarID), 1)
        XCTAssertNotNil(try store.consultation(id: kept.id))
        XCTAssertEqual(try store.consultations(in: window).count, 1)
    }

    // MARK: Resolving

    func testTheUserCanKeepEitherSideOfAConflict() throws {
        let store = try makeMemoryStore()
        let patient = try store.createPatient(displayName: "Jean Dupont")
        let original = date(2026, 8, 25, 14, 0)
        try sync(store, [event("e1", title: "Jean Dupont", original)])
        let consultation = try XCTUnwrap(try store.consultations(in: window).first)
        try store.setStatus(.attended, forConsultation: consultation.id)
        _ = try store.recordPayment(consultationID: consultation.id, patientID: patient.id,
                                    amountCents: 7_000, methodID: "card")
        try sync(store, [event("e1", title: "Jean Dupont", date(2026, 8, 25, 9, 0), occurrence: original)])

        // Keeping Cadence's version detaches the appointment from the calendar…
        try store.resolveConflict(consultation.id, keepingCalendarVersion: false)
        var after = try XCTUnwrap(try store.consultation(id: consultation.id))
        XCTAssertEqual(after.syncState, .local)
        XCTAssertEqual(after.source, .manual)
        XCTAssertNil(after.occurrenceKey)

        // …and a later synchronisation re-imports the event as its own appointment,
        // leaving the recorded one alone.
        let outcome = try sync(store, [event("e1", title: "Jean Dupont", date(2026, 8, 25, 9, 0), occurrence: original)])
        XCTAssertEqual(outcome.inserted, 1)
        after = try XCTUnwrap(try store.consultation(id: consultation.id))
        XCTAssertEqual(after.scheduledStart, original)
    }
}
