import XCTest
@testable import CadenceCore

final class StoreTests: CadenceTestCase {

    func testMigrationIsIdempotentAndVersioned() throws {
        let store = try makeFileStore()
        XCTAssertEqual(store.database.userVersion, Schema.currentVersion)
        store.close()

        // Opening again must not re-run migrations or lose anything.
        let reopened = try makeFileStore()
        XCTAssertEqual(reopened.database.userVersion, Schema.currentVersion)
        XCTAssertNoThrow(try reopened.allPatients())
    }

    func testWriteAheadLoggingIsOn() throws {
        let store = try makeFileStore()
        let mode = try store.database.query("PRAGMA journal_mode;").first?.string("journal_mode")
        XCTAssertEqual(mode?.lowercased(), "wal")
    }

    func testForeignKeysAreEnforced() throws {
        let store = try makeFileStore()
        let enabled = try store.database.query("PRAGMA foreign_keys;").first?.int("foreign_keys")
        XCTAssertEqual(enabled, 1)
    }

    func testFailedTransactionRollsEverythingBack() throws {
        let store = try makeMemoryStore()
        _ = try store.createPatient(displayName: "Avant")

        struct Boom: Error {}
        XCTAssertThrowsError(
            try store.write {
                _ = try store.createPatient(displayName: "Pendant")
                throw Boom()
            }
        )

        let names = try store.allPatients().map(\.displayName)
        XCTAssertEqual(names, ["Avant"], "a failed transaction must leave no trace")
    }

    func testNestedTransactionsCommitOnlyOnce() throws {
        let store = try makeMemoryStore()
        try store.write {
            _ = try store.createPatient(displayName: "Externe")     // itself a transaction
            try store.write {
                _ = try store.createPatient(displayName: "Interne")
            }
        }
        XCTAssertEqual(try store.allPatients().count, 2)
    }

    func testDeletingAPatientRemovesTheirPaymentsButKeepsTheConsultationRecord() throws {
        let store = try makeMemoryStore()
        let patient = try store.createPatient(displayName: "Jean Dupont")
        let consultation = try store.createConsultation(
            patientID: patient.id, title: "Jean Dupont",
            start: date(2026, 8, 25, 14, 0), end: date(2026, 8, 25, 14, 50)
        )
        _ = try store.recordPayment(consultationID: consultation.id, patientID: patient.id,
                                    amountCents: 7_000, methodID: "card")

        let impact = try store.deletionImpact(forPatient: patient.id)
        XCTAssertEqual(impact.consultations, 1)
        XCTAssertEqual(impact.payments, 1)

        try store.deletePatient(patient.id)

        XCTAssertNil(try store.patient(id: patient.id))
        XCTAssertEqual(try store.payments(forConsultation: consultation.id).count, 0)
        let orphaned = try XCTUnwrap(try store.consultation(id: consultation.id))
        XCTAssertNil(orphaned.patientID, "the slot survives, unlinked, so the day's history stays intact")
        XCTAssertEqual(orphaned.title, "Jean Dupont")
    }

    func testArchivedPatientsAreHiddenButNotLost() throws {
        let store = try makeMemoryStore()
        let patient = try store.createPatient(displayName: "Paul Mercier")
        try store.setPatientArchived(patient.id, archived: true)

        XCTAssertEqual(try store.allPatients().count, 0)
        XCTAssertEqual(try store.allPatients(includeArchived: true).count, 1)

        try store.setPatientArchived(patient.id, archived: false)
        XCTAssertEqual(try store.allPatients().count, 1)
    }

    func testStartingAndEndingASessionRecordsRealTimes() throws {
        let store = try makeMemoryStore()
        let patient = try store.createPatient(displayName: "Jean Dupont")
        let scheduled = date(2026, 8, 25, 14, 0)
        let consultation = try store.createConsultation(
            patientID: patient.id, title: "Jean Dupont",
            start: scheduled, end: scheduled.addingTimeInterval(3_000)
        )

        try store.startConsultation(consultation.id, at: date(2026, 8, 25, 14, 7))
        var updated = try XCTUnwrap(try store.consultation(id: consultation.id))
        XCTAssertEqual(updated.status, .inProgress)
        XCTAssertTrue(updated.isRunning)
        XCTAssertEqual(updated.actualStart, date(2026, 8, 25, 14, 7))

        try store.endConsultation(consultation.id, at: date(2026, 8, 25, 14, 57))
        updated = try XCTUnwrap(try store.consultation(id: consultation.id))
        XCTAssertEqual(updated.status, .attended)
        XCTAssertEqual(updated.actualDuration, 50 * 60)
        XCTAssertEqual(CadenceFormat.duration(try XCTUnwrap(updated.actualDuration)), "50 min")

        try store.clearActualTimes(consultation.id)
        updated = try XCTUnwrap(try store.consultation(id: consultation.id))
        XCTAssertNil(updated.actualStart)
        XCTAssertNil(updated.actualDuration)
    }

    func testAssigningAPatientRemembersTheCalendarWording() throws {
        let store = try makeMemoryStore()
        let patient = try store.createPatient(displayName: "Jean Dupont")
        let start = date(2026, 8, 25, 14, 0)
        var consultation = Consultation(
            title: "RDV - J. DUPONT (cabinet)", source: .calendar,
            scheduledStart: start, scheduledEnd: start.addingTimeInterval(3_000), syncState: .synced
        )
        consultation.occurrenceKey = "e1|1"
        try store.upsertConsultationSilently(consultation)

        try store.assignPatient(patient.id, toConsultation: consultation.id)

        // Next week the same wording arrives again and matches without asking.
        let match = try store.matchPatient(forTitle: "RDV - J. DUPONT (cabinet)")
        XCTAssertEqual(match.patientID, patient.id)
        XCTAssertEqual(match.confidence, .remembered)
    }

    func testSettingsRoundTrip() throws {
        let store = try makeFileStore()
        var settings = try store.settings()
        settings.practiceName = "Cabinet du Parc"
        settings.defaultAmountCents = 7_500
        settings.defaultMethodID = "cash"
        settings.dayStartHour = 7
        settings.hasCompletedOnboarding = true
        settings.paymentMethods = [
            PaymentMethod(id: "cash", label: "Espèces", symbol: "banknote"),
            PaymentMethod(id: "card", label: "CB", symbol: "creditcard"),
            PaymentMethod(id: "vitale", label: "Tiers payant", symbol: "cross.case"),
        ]
        try store.saveSettings(settings)
        store.close()

        let reloaded = try makeFileStore().settings()
        XCTAssertEqual(reloaded.practiceName, "Cabinet du Parc")
        XCTAssertEqual(reloaded.defaultAmountCents, 7_500)
        XCTAssertEqual(reloaded.defaultMethodID, "cash")
        XCTAssertEqual(reloaded.dayStartHour, 7)
        XCTAssertTrue(reloaded.hasCompletedOnboarding)
        XCTAssertEqual(reloaded.paymentMethods.count, 3)
        XCTAssertEqual(reloaded.methodLabel("card"), "CB", "a renamed method must be reflected everywhere")
        XCTAssertEqual(reloaded.methodLabel("cheque"), "Cheque", "a removed method still renders past payments")
    }

    func testCalendarSubscriptionsPreserveUserChoicesAcrossDiscovery() throws {
        let store = try makeMemoryStore()
        try store.reconcileCalendars([
            CalendarSubscription(id: "a", title: "Cabinet", accountName: "iCloud"),
            CalendarSubscription(id: "b", title: "Perso", accountName: "Google"),
        ])
        try store.setCalendarEnabled("a", enabled: true)

        // macOS reports the same calendars again, one renamed, and one has gone.
        try store.reconcileCalendars([
            CalendarSubscription(id: "a", title: "Cabinet 2026", accountName: "iCloud"),
            CalendarSubscription(id: "c", title: "Formation", accountName: "Google"),
        ])

        let subscriptions = try store.calendarSubscriptions()
        XCTAssertEqual(Set(subscriptions.map(\.id)), ["a", "c"])
        let cabinet = try XCTUnwrap(subscriptions.first { $0.id == "a" })
        XCTAssertTrue(cabinet.isEnabled, "the user's choice must survive a rename")
        XCTAssertEqual(cabinet.title, "Cabinet 2026")
    }

    func testUnassignedConsultationsAreSurfaced() throws {
        let store = try makeMemoryStore()
        let start = date(2026, 8, 25, 14, 0)
        try store.upsertConsultationSilently(
            Consultation(title: "Réunion équipe", source: .calendar,
                         scheduledStart: start, scheduledEnd: start.addingTimeInterval(3_000))
        )
        let range = DateRange.day(containing: start)
        XCTAssertEqual(try store.unassignedConsultations(in: range).count, 1)
    }

    func testBusyDaysAreReported() throws {
        let store = try makeMemoryStore()
        let patient = try store.createPatient(displayName: "Jean Dupont")
        _ = try store.createConsultation(patientID: patient.id, title: "x",
                                         start: date(2026, 8, 25, 9, 0), end: date(2026, 8, 25, 9, 50))
        _ = try store.createConsultation(patientID: patient.id, title: "x",
                                         start: date(2026, 8, 25, 11, 0), end: date(2026, 8, 25, 11, 50))
        _ = try store.createConsultation(patientID: patient.id, title: "x",
                                         start: date(2026, 8, 27, 9, 0), end: date(2026, 8, 27, 9, 50))

        let busy = try store.busyDayStarts(in: .week(containing: date(2026, 8, 25)))
        XCTAssertEqual(busy.count, 2)
        XCTAssertTrue(busy.contains(Calendar.cadence.startOfDay(for: date(2026, 8, 25))))
    }

    func testAuditTrailRecordsTheDay() throws {
        let store = try makeMemoryStore()
        let patient = try store.createPatient(displayName: "Jean Dupont")
        let consultation = try store.createConsultation(patientID: patient.id, title: "Jean Dupont",
                                                        start: date(2026, 8, 25, 14, 0),
                                                        end: date(2026, 8, 25, 14, 50))
        try store.setStatus(.attended, forConsultation: consultation.id)
        _ = try store.recordPayment(consultationID: consultation.id, patientID: patient.id,
                                    amountCents: 7_000, methodID: "card")

        let kinds = try store.recentActions().map(\.kind)
        XCTAssertTrue(kinds.contains(.paymentRecorded))
        XCTAssertTrue(kinds.contains(.consultationStatusChanged))
        XCTAssertTrue(kinds.contains(.consultationCreated))
        XCTAssertTrue(kinds.contains(.patientCreated))
    }
}
