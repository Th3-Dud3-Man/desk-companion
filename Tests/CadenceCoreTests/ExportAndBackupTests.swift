import XCTest
@testable import CadenceCore

final class ExportTests: CadenceTestCase {

    private func populate(_ store: CadenceStore) throws -> (Patient, Patient) {
        let alice = try store.createPatient(displayName: "Alice Martin", email: "alice@example.com")
        let bruno = try store.createPatient(displayName: "Bruno; Petit \"dit Bru\"")

        let first = try store.createConsultation(patientID: alice.id, title: "Alice Martin",
                                                 start: date(2026, 8, 25, 9, 0), end: date(2026, 8, 25, 9, 50))
        try store.setStatus(.attended, forConsultation: first.id)
        _ = try store.recordPayment(consultationID: first.id, patientID: alice.id,
                                    amountCents: 7_050, methodID: "card", paidAt: date(2026, 8, 25, 9, 50))

        let second = try store.createConsultation(patientID: bruno.id, title: "Bruno Petit",
                                                  start: date(2026, 8, 25, 10, 0), end: date(2026, 8, 25, 10, 50))
        try store.setStatus(.absent, forConsultation: second.id)
        return (alice, bruno)
    }

    func testPaymentsCSVIsExcelReadyFrench() throws {
        let store = try makeMemoryStore()
        _ = try populate(store)

        let data = try store.exportPaymentsCSV(range: .day(containing: date(2026, 8, 25)))
        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF], "Excel needs the BOM to read accents")

        let text = String(data: data.dropFirst(3), encoding: .utf8) ?? ""
        XCTAssertTrue(text.hasPrefix("Date;Heure;Patient;Montant"))
        XCTAssertTrue(text.contains("\r\n"), "CRLF line endings")
        XCTAssertTrue(text.contains("70,50"), "French decimal comma")
        XCTAssertTrue(text.contains("25/08/2026"))
        XCTAssertTrue(text.contains("Carte"))

        let lines = text.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 2, "one header plus one payment")
    }

    func testFieldsContainingSeparatorsAreQuoted() throws {
        let store = try makeMemoryStore()
        _ = try populate(store)
        let text = String(data: try store.exportPatientsCSV().dropFirst(3), encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("\"Bruno; Petit \"\"dit Bru\"\"\""),
                      "a name holding the separator and quotes must survive the round trip")
    }

    func testConsultationsCSVCoversAttendanceAndPayment() throws {
        let store = try makeMemoryStore()
        _ = try populate(store)
        let text = String(data: try store.exportConsultationsCSV(range: .day(containing: date(2026, 8, 25))).dropFirst(3),
                          encoding: .utf8) ?? ""
        let lines = text.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(text.contains("Présent"))
        XCTAssertTrue(text.contains("Absent"))
        XCTAssertTrue(text.contains("09:00"))
    }

    func testPatientsCSVCarriesTheLearnedHabit() throws {
        let store = try makeMemoryStore()
        let patient = try store.createPatient(displayName: "Jean Dupont")
        for week in 1...5 {
            let start = Calendar.cadence.date(byAdding: .day, value: -7 * week, to: date(2026, 8, 25, 14, 0))!
            let consultation = try store.createConsultation(patientID: patient.id, title: "Jean Dupont",
                                                            start: start, end: start.addingTimeInterval(3_000))
            try store.setStatus(.attended, forConsultation: consultation.id)
            _ = try store.recordPayment(consultationID: consultation.id, patientID: patient.id,
                                        amountCents: 7_000, methodID: "card", paidAt: start)
        }

        let text = String(data: try store.exportPatientsCSV(now: date(2026, 8, 25, 20, 0)).dropFirst(3),
                          encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("Jean Dupont"))
        XCTAssertTrue(text.contains("70,00"))
        XCTAssertTrue(text.contains("Chaque semaine"))
        // "Habitude établie" column says yes.
        let row = text.components(separatedBy: "\r\n").first { $0.contains("Jean Dupont") } ?? ""
        XCTAssertEqual(row.components(separatedBy: ";")[12], "oui")
    }

    func testEmptyPeriodStillProducesAValidFile() throws {
        let store = try makeMemoryStore()
        let data = try store.exportPaymentsCSV(range: .day(containing: date(2026, 1, 1)))
        let text = String(data: data.dropFirst(3), encoding: .utf8) ?? ""
        XCTAssertEqual(text.components(separatedBy: "\r\n").filter { !$0.isEmpty }.count, 1,
                       "the header alone — never an empty or malformed file")
    }

    func testActivityReportContainsTheRealFigures() throws {
        let store = try makeMemoryStore()
        _ = try populate(store)
        let html = try store.activityReport(for: .day(containing: date(2026, 8, 25)),
                                            title: "Mardi 25 août 2026",
                                            generatedAt: date(2026, 8, 25, 21, 0))

        XCTAssertTrue(html.hasPrefix("<!doctype html>"))
        XCTAssertTrue(html.contains("Mardi 25 août 2026"))
        XCTAssertTrue(html.contains("Alice Martin"))
        XCTAssertTrue(html.contains("70,50") || html.contains("70,5"))
        XCTAssertTrue(html.contains("Carte"))
        XCTAssertTrue(html.contains("ne constitue pas une pièce comptable"))
        XCTAssertFalse(html.contains("http://"), "the report must not reference anything external")
        XCTAssertFalse(html.contains("https://"))
    }

    func testReportEscapesUserText() throws {
        let store = try makeMemoryStore()
        var settings = try store.settings()
        settings.practiceName = "Cabinet <script>alert(1)</script>"
        try store.saveSettings(settings)

        let html = try store.activityReport(for: .day(containing: date(2026, 8, 25)), title: "Test")
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
    }
}

final class BackupTests: CadenceTestCase {

    func testSnapshotIsAUsableDatabase() throws {
        let store = try makeFileStore()
        let patient = try store.createPatient(displayName: "Jean Dupont")
        _ = try store.recordPayment(consultationID: nil, patientID: patient.id,
                                    amountCents: 7_000, methodID: "card")

        let manager = BackupManager(store: store, directory: temporaryDirectory.appendingPathComponent("Backups"))
        let snapshot = try manager.createSnapshot(named: "test.sqlite3")
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot.url.path))
        XCTAssertGreaterThan(snapshot.byteCount, 0)

        // The snapshot opens on its own and holds the same data.
        let copy = try CadenceStore.open(at: snapshot.url)
        XCTAssertEqual(try copy.allPatients().map(\.displayName), ["Jean Dupont"])
        XCTAssertEqual(try copy.payments(forPatient: patient.id).count, 1)
    }

    func testOnlyOneSnapshotPerDay() throws {
        let store = try makeFileStore()
        let manager = BackupManager(store: store, directory: temporaryDirectory.appendingPathComponent("Backups"))
        let now = date(2026, 8, 25, 9, 0)

        XCTAssertNotNil(try manager.createDailySnapshotIfNeeded(now: now))
        XCTAssertNil(try manager.createDailySnapshotIfNeeded(now: date(2026, 8, 25, 18, 0)))
        XCTAssertNotNil(try manager.createDailySnapshotIfNeeded(now: date(2026, 8, 26, 9, 0)))
        XCTAssertEqual(try manager.snapshots().count, 2)
    }

    func testOldSnapshotsArePruned() throws {
        let store = try makeFileStore()
        let manager = BackupManager(store: store, directory: temporaryDirectory.appendingPathComponent("Backups"))
        for day in 1...20 {
            _ = try manager.createSnapshot(named: String(format: "cadence-2026-08-%02d.sqlite3", day))
        }
        try manager.prune(keeping: 14)
        XCTAssertEqual(try manager.snapshots().count, 14)
    }

    func testRestoreSwapsTheLiveDatabaseAndKeepsASafetyCopy() throws {
        let store = try makeFileStore()
        _ = try store.createPatient(displayName: "Avant la sauvegarde")

        let manager = BackupManager(store: store, directory: temporaryDirectory.appendingPathComponent("Backups"))
        let snapshot = try manager.createSnapshot(named: "point-de-reprise.sqlite3")

        _ = try store.createPatient(displayName: "Après la sauvegarde")
        XCTAssertEqual(try store.allPatients().count, 2)
        store.close()

        try BackupManager.restore(from: snapshot.url, replacing: databaseURL)

        let restored = try makeFileStore()
        XCTAssertEqual(try restored.allPatients().map(\.displayName), ["Avant la sauvegarde"])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: temporaryDirectory.appendingPathComponent("cadence-avant-restauration.sqlite3").path
            ),
            "restoring must not be the destructive act — the replaced file is kept"
        )
    }
}

final class FormattingTests: CadenceTestCase {

    func testMoneyNeverUsesFloatingPoint() {
        XCTAssertEqual(Money.euros(70.10).cents, 7_010)
        XCTAssertEqual((Money(cents: 10) + Money(cents: 20)).cents, 30)
        XCTAssertEqual(Money(cents: 7_000).csvValue, "70,00")
        XCTAssertEqual(Money(cents: 7_050).csvValue, "70,50")
        XCTAssertEqual(Money(cents: -1_234).csvValue, "-12,34")
        XCTAssertEqual(Money(cents: 5).csvValue, "0,05")
    }

    func testWholeAmountsDropTheDecimals() {
        XCTAssertEqual(plainSpaces(Money(cents: 7_000).formatted()), "70 €")
        XCTAssertEqual(plainSpaces(Money(cents: 7_050).formatted()), "70,50 €")
    }

    func testDurationsReadLikeSpeech() {
        XCTAssertEqual(CadenceFormat.duration(50 * 60), "50 min")
        XCTAssertEqual(CadenceFormat.duration(60 * 60), "1 h")
        XCTAssertEqual(CadenceFormat.duration(90 * 60), "1 h 30")
    }

    func testRelativeTimesReadLikeSpeech() {
        let now = date(2026, 8, 25, 14, 0)
        XCTAssertEqual(CadenceFormat.relative(date(2026, 8, 25, 14, 12), from: now), "dans 12 min")
        XCTAssertEqual(CadenceFormat.relative(date(2026, 8, 25, 13, 57), from: now), "il y a 3 min")
        XCTAssertEqual(CadenceFormat.relative(now, from: now), "maintenant")
        XCTAssertEqual(CadenceFormat.relative(date(2026, 8, 25, 16, 0), from: now), "dans 2 h")
    }

    func testWeekStartsOnMonday() {
        let week = DateRange.week(containing: date(2026, 8, 27, 15, 0))   // a Thursday
        XCTAssertEqual(week.start, date(2026, 8, 24))
        XCTAssertEqual(week.end, date(2026, 8, 31))
    }

    func testMonthAndPreviousPeriod() {
        let month = DateRange.month(containing: date(2026, 8, 15))
        XCTAssertEqual(month.start, date(2026, 8, 1))
        XCTAssertEqual(month.end, date(2026, 9, 1))

        let previous = month.previousPeriod()
        XCTAssertEqual(previous.end, month.start)
        XCTAssertEqual(previous.duration, month.duration)
    }

    func testDayRangeIsHalfOpen() {
        let day = DateRange.day(containing: date(2026, 8, 25, 12, 0))
        XCTAssertTrue(day.contains(date(2026, 8, 25, 0, 0)))
        XCTAssertTrue(day.contains(date(2026, 8, 25, 23, 59)))
        XCTAssertFalse(day.contains(date(2026, 8, 26, 0, 0)), "midnight belongs to the next day, exactly once")
    }

    func testSearchIgnoresAccentsCaseAndPunctuation() {
        XCTAssertTrue(TextNormaliser.matches("Chloé Müller", query: "chloe"))
        XCTAssertTrue(TextNormaliser.matches("Jean-Pierre O'Brien", query: "jean pierre"))
        XCTAssertTrue(TextNormaliser.matchesInitials("Jean Dupont", query: "jd"))
        XCTAssertFalse(TextNormaliser.matchesInitials("Jean Dupont", query: "dj"))
    }

    func testMonogramHandlesRealNames() {
        XCTAssertEqual(Patient(displayName: "Jean Dupont").monogram, "JD")
        XCTAssertEqual(Patient(displayName: "Chloé").monogram, "CH")
        XCTAssertEqual(Patient(displayName: "Jean-Pierre Martin").monogram, "JM")
    }

    func testColourSeedIsStableAcrossRuns() {
        XCTAssertEqual(Patient.seed(for: "Jean Dupont"), Patient.seed(for: "jean  dupont"))
        XCTAssertNotEqual(Patient.seed(for: "Jean Dupont"), Patient.seed(for: "Marie Curie"))
    }
}
