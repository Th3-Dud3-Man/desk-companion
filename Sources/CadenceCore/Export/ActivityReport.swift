import Foundation

/// Builds the printable activity report.
///
/// The report is produced as self-contained HTML and rendered to PDF by the macOS
/// layer. Doing it this way keeps every number, label and layout decision inside the
/// tested core, and leaves the platform with nothing but the printing step.
public enum ActivityReport {

    public struct Input: Sendable {
        public let practiceName: String
        public let range: DateRange
        public let title: String
        public let statistics: PeriodStatistics
        public let comparison: PeriodComparison?
        public let dailyTotals: [DailyTotal]
        public let payments: [Payment]
        public let patientNames: [UUID: String]
        public let settings: PracticeSettings
        public let generatedAt: Date

        public init(
            practiceName: String,
            range: DateRange,
            title: String,
            statistics: PeriodStatistics,
            comparison: PeriodComparison?,
            dailyTotals: [DailyTotal],
            payments: [Payment],
            patientNames: [UUID: String],
            settings: PracticeSettings,
            generatedAt: Date = Date()
        ) {
            self.practiceName = practiceName
            self.range = range
            self.title = title
            self.statistics = statistics
            self.comparison = comparison
            self.dailyTotals = dailyTotals
            self.payments = payments
            self.patientNames = patientNames
            self.settings = settings
            self.generatedAt = generatedAt
        }
    }

    public static func html(for input: Input) -> String {
        let statistics = input.statistics
        let currency = input.settings.currencyCode
        let money = { (cents: Int) in Money(cents: cents, currencyCode: currency).formatted() }

        let attendance = statistics.attendanceRate.map { "\(Int(($0 * 100).rounded())) %" } ?? "—"
        let average = statistics.averagePerAttendedCents.map(money) ?? "—"

        var evolution = ""
        if let comparison = input.comparison, let change = comparison.revenueChange {
            let percentage = Int((change * 100).rounded())
            let text = percentage == 0 ? "stable" : "\(percentage > 0 ? "+" : "")\(percentage) %"
            let direction = percentage == 0 ? "" : (percentage > 0 ? "up" : "down")
            evolution = """
            <div class="kpi">
              <div class="kpi-label">Évolution</div>
              <div class="kpi-value \(direction)">\(text)</div>
              <div class="kpi-note">vs. période précédente (\(money(comparison.previous.revenueCents)))</div>
            </div>
            """
        }

        let methodRows = statistics.byMethod.map { method in
            """
            <tr>
              <td>\(escape(method.label))</td>
              <td class="num">\(method.count)</td>
              <td class="num">\(money(method.totalCents))</td>
              <td class="num">\(Int((method.share * 100).rounded())) %</td>
            </tr>
            """
        }.joined()

        let activeDays = input.dailyTotals.filter { $0.consultationCount > 0 || $0.totalCents > 0 }
        let dayRows = activeDays.map { day in
            """
            <tr>
              <td>\(escape(CadenceFormat.weekdayCompact(day.day)))</td>
              <td class="num">\(day.consultationCount)</td>
              <td class="num">\(money(day.totalCents))</td>
            </tr>
            """
        }.joined()

        let paymentRows = input.payments.sorted { $0.paidAt < $1.paidAt }.map { payment in
            let settlement = payment.isPending
                ? "<span class=\"pending\">en attente</span>"
                : "reçu"
            return """
            <tr>
              <td>\(escape(CadenceFormat.numericDate(payment.paidAt)))</td>
              <td>\(escape(input.patientNames[payment.patientID] ?? "—"))</td>
              <td>\(escape(input.settings.methodLabel(payment.methodID)))</td>
              <td>\(settlement)</td>
              <td class="num">\(money(payment.amountCents))</td>
            </tr>
            """
        }.joined()

        let announcedTotal = input.payments.reduce(0) { $0 + $1.amountCents }

        var pendingKPI = ""
        if statistics.pendingCents > 0 {
            pendingKPI = """
            <div class="kpi">
              <div class="kpi-label">En attente</div>
              <div class="kpi-value warn">\(money(statistics.pendingCents))</div>
              <div class="kpi-note">\(statistics.pendingCount) règlement(s) annoncé(s) non reçu(s)</div>
            </div>
            """
        }

        let unpaidNote = statistics.unpaidAttended > 0
            ? "<p class=\"warn\">\(statistics.unpaidAttended) consultation(s) marquée(s) présente(s) sans paiement enregistré sur la période.</p>"
            : ""

        return """
        <!doctype html>
        <html lang="fr">
        <head>
        <meta charset="utf-8">
        <title>\(escape(input.title))</title>
        <style>
          @page { size: A4; margin: 0; }   /* margins come from the print job */
          * { box-sizing: border-box; }
          body {
            font-family: -apple-system, "SF Pro Text", "Helvetica Neue", Helvetica, Arial, sans-serif;
            color: #1B1C19; margin: 0; font-size: 11px; line-height: 1.45;
            -webkit-font-smoothing: antialiased;
          }
          h1 { font-size: 20px; margin: 0 0 2px; letter-spacing: -0.01em; }
          h2 {
            font-size: 10px; text-transform: uppercase; letter-spacing: 0.08em;
            color: #61625C; margin: 26px 0 8px; font-weight: 600;
          }
          .head { border-bottom: 1.5px solid #1B1C19; padding-bottom: 10px; margin-bottom: 4px;
                  display: flex; justify-content: space-between; align-items: flex-end; }
          .head .meta { text-align: right; color: #61625C; font-size: 10px; }
          .period { color: #2E6B57; font-weight: 600; font-size: 12px; }
          .kpis { display: flex; gap: 10px; margin-top: 18px; flex-wrap: wrap; }
          .kpi { flex: 1 1 120px; border: 1px solid #E3E1D9; border-radius: 8px; padding: 10px 12px; }
          .kpi-label { font-size: 9px; text-transform: uppercase; letter-spacing: 0.07em; color: #61625C; font-weight: 600; }
          .kpi-value { font-size: 20px; font-weight: 600; margin-top: 3px;
                       font-variant-numeric: tabular-nums; letter-spacing: -0.02em; }
          .kpi-note { font-size: 9.5px; color: #93948C; margin-top: 2px; }
          .kpi-value.up { color: #2E6B57; } .kpi-value.down { color: #A34129; }
          table { width: 100%; border-collapse: collapse; }
          th { text-align: left; font-size: 9px; text-transform: uppercase; letter-spacing: 0.06em;
               color: #61625C; border-bottom: 1px solid #CFCCC2; padding: 5px 6px; font-weight: 600; }
          td { padding: 4px 6px; border-bottom: 1px solid #F0EEE8; }
          td.num, th.num { text-align: right; font-variant-numeric: tabular-nums; }
          tr:nth-child(even) td { background: #FAF9F5; }
          .cols { display: flex; gap: 22px; align-items: flex-start; }
          .cols > * { flex: 1; min-width: 0; }
          .warn { color: #8F6414; background: #F6EDD9; border-radius: 6px; padding: 7px 10px; font-size: 10px; }
          .kpi-value.warn { background: none; padding: 0; font-size: 20px; border-radius: 0; }
          .pending { color: #8F6414; }
          .footnote { color: #93948C; font-size: 9.5px; margin-top: 6px; }
          footer { margin-top: 26px; padding-top: 8px; border-top: 1px solid #E3E1D9;
                   color: #93948C; font-size: 9px; }
          tfoot td { font-weight: 600; border-top: 1.5px solid #CFCCC2; border-bottom: none; background: none !important; }
        </style>
        </head>
        <body>
          <div class="head">
            <div>
              <h1>\(escape(input.practiceName))</h1>
              <div class="period">\(escape(input.title))</div>
            </div>
            <div class="meta">
              Rapport d'activité<br>
              établi le \(escape(CadenceFormat.numericDateTime(input.generatedAt)))
            </div>
          </div>

          <div class="kpis">
            <div class="kpi">
              <div class="kpi-label">Encaissé</div>
              <div class="kpi-value">\(money(statistics.revenueCents))</div>
              <div class="kpi-note">\(statistics.paymentCount) paiement(s)</div>
            </div>
            <div class="kpi">
              <div class="kpi-label">Consultations</div>
              <div class="kpi-value">\(statistics.attended)</div>
              <div class="kpi-note">sur \(statistics.planned) prévue(s)</div>
            </div>
            <div class="kpi">
              <div class="kpi-label">Absences</div>
              <div class="kpi-value">\(statistics.absent)</div>
              <div class="kpi-note">présence \(attendance)</div>
            </div>
            <div class="kpi">
              <div class="kpi-label">Moyenne</div>
              <div class="kpi-value">\(average)</div>
              <div class="kpi-note">par consultation honorée</div>
            </div>
            \(pendingKPI)
            \(evolution)
          </div>

          \(unpaidNote)

          <div class="cols">
            <div>
              <h2>Répartition des moyens de paiement</h2>
              <table>
                <thead><tr><th>Moyen</th><th class="num">Nb</th><th class="num">Total</th><th class="num">Part</th></tr></thead>
                <tbody>\(methodRows.isEmpty ? "<tr><td colspan=\"4\">Aucun paiement sur la période.</td></tr>" : methodRows)</tbody>
              </table>
            </div>
            <div>
              <h2>Jour par jour</h2>
              <table>
                <thead><tr><th>Jour</th><th class="num">Consult.</th><th class="num">Encaissé</th></tr></thead>
                <tbody>\(dayRows.isEmpty ? "<tr><td colspan=\"3\">Aucune activité sur la période.</td></tr>" : dayRows)</tbody>
              </table>
            </div>
          </div>

          <h2>Détail des paiements convenus sur la période</h2>
          <table>
            <thead><tr><th>Date</th><th>Patient</th><th>Moyen</th><th>Règlement</th><th class="num">Montant</th></tr></thead>
            <tbody>\(paymentRows.isEmpty ? "<tr><td colspan=\"5\">Aucun paiement sur la période.</td></tr>" : paymentRows)</tbody>
            <tfoot><tr><td colspan="4">Total convenu</td><td class="num">\(money(announcedTotal))</td></tr></tfoot>
          </table>
          <p class="footnote">
            « Encaissé » compte l'argent reçu pendant la période ; ce tableau liste les paiements
            convenus pendant la période. Un virement convenu en fin de mois et reçu le mois suivant
            apparaît donc ici, et dans les recettes du mois suivant.
          </p>

          <footer>
            Document produit par Cadence à partir des données saisies localement. Il rend compte de
            l'activité enregistrée et ne constitue pas une pièce comptable ni un document fiscal.
          </footer>
        </body>
        </html>
        """
    }

    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

extension CadenceStore {

    /// Assembles a report for `range`, pulling everything it needs from the database.
    public func activityReport(
        for range: DateRange,
        title: String,
        settings: PracticeSettings? = nil,
        generatedAt: Date = Date()
    ) throws -> String {
        let settings = try settings ?? self.settings()
        let payments = try payments(in: range)
        let names = try patients(ids: Array(Set(payments.map(\.patientID))))
            .mapValues(\.displayName)

        return ActivityReport.html(
            for: ActivityReport.Input(
                practiceName: settings.practiceName,
                range: range,
                title: title,
                statistics: try statistics(for: range, settings: settings),
                comparison: try comparison(for: range, settings: settings),
                dailyTotals: try dailyTotals(in: range),
                payments: payments,
                patientNames: names,
                settings: settings,
                generatedAt: generatedAt
            )
        )
    }
}
