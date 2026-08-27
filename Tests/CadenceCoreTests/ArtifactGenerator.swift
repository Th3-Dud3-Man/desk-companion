import XCTest
@testable import CadenceCore

/// The exports are a deliverable in their own right — an accountant reads them —
/// so their totals are checked against the records they claim to summarise, rather
/// than merely checked for being non-empty.
final class ExportReconciliationTests: CadenceTestCase {

    /// Builds the sample practice and returns a month with real activity in it.
    private func populatedStore() throws -> (CadenceStore, DateRange, Date) {
        let now = date(2026, 8, 25, 18, 0)
        let store = try makeMemoryStore()
        try DemoData.install(into: store, now: now)
        return (store, .month(containing: now), now)
    }

    func testTheReportTotalEqualsTheSumOfItsOwnLines() throws {
        let (store, month, now) = try populatedStore()
        let payments = try store.payments(in: month)
        let settled = try store.settledPayments(in: month)
        let statistics = try store.statistics(for: month)

        XCTAssertGreaterThan(payments.count, 5, "the fixture must actually have activity")
        XCTAssertGreaterThan(statistics.pendingCents, 0, "the fixture must exercise outstanding payments")

        XCTAssertEqual(
            statistics.revenueCents,
            settled.reduce(0) { $0 + $1.amountCents },
            "\"encaissé\" must be exactly the money that arrived during the period"
        )
        XCTAssertEqual(
            statistics.announcedCents,
            payments.reduce(0) { $0 + $1.amountCents },
            "\"convenu\" must be exactly what the detail table lists"
        )
        XCTAssertEqual(
            statistics.pendingCents,
            payments.filter(\.isPending).reduce(0) { $0 + $1.amountCents },
            "and what is outstanding must be the rest of it"
        )
        XCTAssertEqual(
            statistics.byMethod.reduce(0) { $0 + $1.totalCents },
            statistics.revenueCents,
            "the breakdown by payment method must add up to the total"
        )
        XCTAssertEqual(
            try store.dailyTotals(in: month).reduce(0) { $0 + $1.totalCents },
            statistics.revenueCents,
            "and so must the day-by-day figures"
        )

        let html = try store.activityReport(for: month, title: "Août 2026", generatedAt: now)
        XCTAssertTrue(html.contains("Total"))
        XCTAssertTrue(html.contains("ne constitue pas une pièce comptable"))
        // Every payment in the period appears in the detail table.
        for payment in payments {
            XCTAssertTrue(
                html.contains(CadenceFormat.numericDate(payment.paidAt)),
                "payment of \(payment.money.formatted()) is missing from the report"
            )
        }
    }

    func testThePaymentsExportContainsEveryPaymentExactlyOnce() throws {
        let (store, month, _) = try populatedStore()
        let payments = try store.payments(in: month)

        let data = try store.exportPaymentsCSV(range: month)
        let text = String(data: data.dropFirst(3), encoding: .utf8) ?? ""
        let lines = text.components(separatedBy: "\r\n").filter { !$0.isEmpty }

        XCTAssertEqual(lines.count, payments.count + 1, "one header, then one line per payment")

        // The amounts column adds up to the same total the statistics report.
        let exported = lines.dropFirst().compactMap { line -> Int? in
            let columns = line.components(separatedBy: ";")
            guard columns.count > 3 else { return nil }
            return Int(columns[3].replacingOccurrences(of: ",", with: ""))
        }
        XCTAssertEqual(
            exported.reduce(0, +),
            try store.statistics(for: month).announcedCents,
            "the export lists what was agreed in the period, so it sums to that figure"
        )
        XCTAssertTrue(text.contains("En attente"), "the export must say which payments have not arrived")
    }

    func testTheConsultationsExportCoversEverySlotInThePeriod() throws {
        let (store, month, _) = try populatedStore()
        let consultations = try store.consultations(in: month)
        let text = String(data: try store.exportConsultationsCSV(range: month).dropFirst(3), encoding: .utf8) ?? ""
        let lines = text.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, consultations.count + 1)
    }

    func testThePatientsExportReportsTheHabitsTheApplicationActsOn() throws {
        let (store, _, now) = try populatedStore()
        let text = String(data: try store.exportPatientsCSV(now: now).dropFirst(3), encoding: .utf8) ?? ""

        // Jean Dupont pays 70 € by card every week in the fixture; the export must
        // say exactly what the payment strip would offer.
        let row = try XCTUnwrap(text.components(separatedBy: "\r\n").first { $0.hasPrefix("Jean Dupont;") })
        let columns = row.components(separatedBy: ";")
        XCTAssertEqual(columns[10], "70,00", "usual amount")
        XCTAssertEqual(columns[11], "Carte", "usual method")
        XCTAssertEqual(columns[12], "oui", "habit established")
        XCTAssertEqual(columns[15], "Chaque semaine", "rhythm")
    }
}
