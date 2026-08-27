import Foundation

/// One month of received income.
public struct MonthlyIncome: Hashable, Identifiable, Sendable {
    public let month: Date
    /// Money that actually arrived during the month.
    public let receivedCents: Int
    public let paymentCount: Int
    public let consultationCount: Int

    public var id: Date { month }
}

/// The document to hand to a bank.
///
/// Deliberately not the same thing as the activity report. A lender is asking one
/// question — how much money reliably comes in, and how regularly — so this counts
/// **only payments that have actually been received**, month by month, over a long
/// enough window to show a pattern. Anything merely agreed is reported separately
/// and never folded into the total.
///
/// It states plainly what it is: a summary produced from records the practitioner
/// keeps herself. It is not certified, and it says so rather than dressing itself up.
public enum IncomeReport {

    public struct Input: Sendable {
        public let practiceName: String
        public let range: DateRange
        public let months: [MonthlyIncome]
        public let byMethod: [MethodTotal]
        /// Agreed within the window but not yet received, reported apart from the total.
        public let outstandingCents: Int
        public let outstandingCount: Int
        public let currencyCode: String
        public let generatedAt: Date

        public init(
            practiceName: String,
            range: DateRange,
            months: [MonthlyIncome],
            byMethod: [MethodTotal],
            outstandingCents: Int,
            outstandingCount: Int,
            currencyCode: String,
            generatedAt: Date
        ) {
            self.practiceName = practiceName
            self.range = range
            self.months = months
            self.byMethod = byMethod
            self.outstandingCents = outstandingCents
            self.outstandingCount = outstandingCount
            self.currencyCode = currencyCode
            self.generatedAt = generatedAt
        }

        public var totalReceivedCents: Int { months.reduce(0) { $0 + $1.receivedCents } }
        public var totalConsultations: Int { months.reduce(0) { $0 + $1.consultationCount } }

        /// Months with any activity at all; averaging over empty months before the
        /// practice opened would understate a real income.
        public var activeMonths: [MonthlyIncome] { months.filter { $0.receivedCents > 0 } }

        public var monthlyAverageCents: Int {
            let active = activeMonths
            guard !active.isEmpty else { return 0 }
            return active.reduce(0) { $0 + $1.receivedCents } / active.count
        }

        public var bestMonthCents: Int { months.map(\.receivedCents).max() ?? 0 }
        public var leanestActiveMonthCents: Int { activeMonths.map(\.receivedCents).min() ?? 0 }

        public var averagePerConsultationCents: Int {
            guard totalConsultations > 0 else { return 0 }
            return totalReceivedCents / totalConsultations
        }
    }

    public static func html(for input: Input) -> String {
        let money = { (cents: Int) in Money(cents: cents, currencyCode: input.currencyCode).formatted() }
        let peak = max(1, input.bestMonthCents)

        let monthRows = input.months.map { month in
            let share = Double(month.receivedCents) / Double(peak)
            return """
            <tr>
              <td>\(escape(CadenceFormat.monthYear(month.month).capitalizedFirstLetter))</td>
              <td class="num">\(month.consultationCount)</td>
              <td class="num">\(month.paymentCount)</td>
              <td class="bar-cell">\(month.receivedCents > 0
                  ? "<span class=\"bar\" style=\"width: \(String(format: "%.1f", max(2, share * 100)))%\"></span>"
                  : "")</td>
              <td class="num strong">\(money(month.receivedCents))</td>
            </tr>
            """
        }.joined()

        let methodRows = input.byMethod.map { method in
            """
            <tr>
              <td>\(escape(method.label))</td>
              <td class="num">\(method.count)</td>
              <td class="num">\(Int((method.share * 100).rounded())) %</td>
              <td class="num strong">\(money(method.totalCents))</td>
            </tr>
            """
        }.joined()

        var outstandingBlock = ""
        if input.outstandingCents > 0 {
            outstandingBlock = """
            <p class="note">
              À la date d'établissement, \(input.outstandingCount) règlement(s) convenus sur la période,
              pour \(money(input.outstandingCents)), n'étaient pas encore encaissés. Ces montants ne sont
              <strong>pas</strong> comptés dans les totaux ci-dessus.
            </p>
            """
        }

        let periodLabel = "\(CadenceFormat.monthYear(input.range.start)) – \(CadenceFormat.monthYear(input.months.last?.month ?? input.range.start))"

        return """
        <!doctype html>
        <html lang="fr">
        <head>
        <meta charset="utf-8">
        <title>Synthèse de revenus — \(escape(input.practiceName))</title>
        <style>
          @page { size: A4; margin: 0; }
          * { box-sizing: border-box; }
          body {
            font-family: -apple-system, "SF Pro Text", "Helvetica Neue", Helvetica, Arial, sans-serif;
            color: #1B1C19; margin: 0; font-size: 11px; line-height: 1.5;
            -webkit-font-smoothing: antialiased;
          }
          h1 { font-size: 21px; margin: 0 0 3px; letter-spacing: -0.01em; }
          h2 {
            font-size: 10px; text-transform: uppercase; letter-spacing: 0.09em;
            color: #61625C; margin: 26px 0 9px; font-weight: 600;
          }
          .head { border-bottom: 2px solid #1B1C19; padding-bottom: 12px;
                  display: flex; justify-content: space-between; align-items: flex-end; }
          .head .meta { text-align: right; color: #61625C; font-size: 10px; line-height: 1.6; }
          .doc-type { font-size: 11px; font-weight: 600; color: #2E6B57;
                      text-transform: uppercase; letter-spacing: 0.09em; }
          .period { color: #1B1C19; font-weight: 600; font-size: 13px; margin-top: 2px; }

          .headline { display: flex; gap: 14px; margin-top: 22px; }
          .headline .kpi { flex: 1; border: 1px solid #E3E1D9; border-radius: 9px; padding: 13px 15px; }
          .headline .kpi.primary { background: #F3F7F5; border-color: #C9DED5; }
          .kpi-label { font-size: 9px; text-transform: uppercase; letter-spacing: 0.08em;
                       color: #61625C; font-weight: 600; }
          .kpi-value { font-size: 23px; font-weight: 600; margin-top: 4px;
                       font-variant-numeric: tabular-nums; letter-spacing: -0.02em; }
          .kpi.primary .kpi-value { color: #2E6B57; font-size: 27px; }
          .kpi-note { font-size: 9.5px; color: #93948C; margin-top: 3px; }

          table { width: 100%; border-collapse: collapse; }
          th { text-align: left; font-size: 9px; text-transform: uppercase; letter-spacing: 0.07em;
               color: #61625C; border-bottom: 1px solid #CFCCC2; padding: 6px; font-weight: 600; }
          td { padding: 5px 6px; border-bottom: 1px solid #F0EEE8; }
          td.num, th.num { text-align: right; font-variant-numeric: tabular-nums; }
          td.strong { font-weight: 600; }
          tfoot td { font-weight: 600; border-top: 1.5px solid #1B1C19; border-bottom: none;
                     background: none !important; padding-top: 7px; }
          tr:nth-child(even) td { background: #FAF9F5; }
          .bar-cell { width: 34%; padding-right: 14px; }
          .bar { display: block; height: 7px; border-radius: 4px; background: #2E6B57; }

          .cols { display: flex; gap: 24px; align-items: flex-start; }
          .cols > * { flex: 1; min-width: 0; }
          .note { color: #8F6414; background: #F6EDD9; border-radius: 7px;
                  padding: 9px 12px; font-size: 10px; margin-top: 14px; }
          footer { margin-top: 30px; padding-top: 10px; border-top: 1px solid #E3E1D9;
                   color: #7D7E77; font-size: 9px; line-height: 1.6; }
          .sign { margin-top: 26px; display: flex; justify-content: flex-end; }
          .sign .box { width: 230px; border-top: 1px solid #CFCCC2; padding-top: 6px;
                       font-size: 9px; color: #93948C; }
        </style>
        </head>
        <body>
          <div class="head">
            <div>
              <div class="doc-type">Synthèse de revenus</div>
              <h1>\(escape(input.practiceName))</h1>
              <div class="period">\(escape(periodLabel.capitalizedFirstLetter))</div>
            </div>
            <div class="meta">
              Établie le \(escape(CadenceFormat.numericDateTime(input.generatedAt)))<br>
              \(input.months.count) mois · \(input.activeMonths.count) mois d'activité<br>
              Montants effectivement encaissés
            </div>
          </div>

          <div class="headline">
            <div class="kpi primary">
              <div class="kpi-label">Total encaissé</div>
              <div class="kpi-value">\(money(input.totalReceivedCents))</div>
              <div class="kpi-note">sur la période</div>
            </div>
            <div class="kpi">
              <div class="kpi-label">Moyenne mensuelle</div>
              <div class="kpi-value">\(money(input.monthlyAverageCents))</div>
              <div class="kpi-note">sur les mois d'activité</div>
            </div>
            <div class="kpi">
              <div class="kpi-label">Consultations</div>
              <div class="kpi-value">\(input.totalConsultations)</div>
              <div class="kpi-note">honorées sur la période</div>
            </div>
            <div class="kpi">
              <div class="kpi-label">Moyenne / consultation</div>
              <div class="kpi-value">\(money(input.averagePerConsultationCents))</div>
              <div class="kpi-note">encaissé</div>
            </div>
          </div>

          <h2>Revenus mois par mois</h2>
          <table>
            <thead>
              <tr>
                <th>Mois</th>
                <th class="num">Consultations</th>
                <th class="num">Paiements</th>
                <th></th>
                <th class="num">Encaissé</th>
              </tr>
            </thead>
            <tbody>\(monthRows.isEmpty ? "<tr><td colspan=\"5\">Aucune activité sur la période.</td></tr>" : monthRows)</tbody>
            <tfoot>
              <tr>
                <td>Total</td>
                <td class="num">\(input.totalConsultations)</td>
                <td class="num">\(input.months.reduce(0) { $0 + $1.paymentCount })</td>
                <td></td>
                <td class="num">\(money(input.totalReceivedCents))</td>
              </tr>
            </tfoot>
          </table>

          <div class="cols">
            <div>
              <h2>Répartition par moyen de paiement</h2>
              <table>
                <thead><tr><th>Moyen</th><th class="num">Nb</th><th class="num">Part</th><th class="num">Total</th></tr></thead>
                <tbody>\(methodRows.isEmpty ? "<tr><td colspan=\"4\">Aucun paiement sur la période.</td></tr>" : methodRows)</tbody>
              </table>
            </div>
            <div>
              <h2>Régularité</h2>
              <table>
                <tbody>
                  <tr><td>Mois le plus élevé</td><td class="num strong">\(money(input.bestMonthCents))</td></tr>
                  <tr><td>Mois d'activité le plus faible</td><td class="num strong">\(money(input.leanestActiveMonthCents))</td></tr>
                  <tr><td>Mois d'activité</td><td class="num strong">\(input.activeMonths.count) / \(input.months.count)</td></tr>
                </tbody>
              </table>
            </div>
          </div>

          \(outstandingBlock)

          <div class="sign">
            <div class="box">Date et signature</div>
          </div>

          <footer>
            Document établi par la praticienne à partir des écritures qu'elle enregistre elle-même dans
            son logiciel de suivi, à la date indiquée ci-dessus. Seuls les règlements effectivement
            encaissés y figurent. <strong>Il ne s'agit ni d'une attestation comptable, ni d'un document
            fiscal, ni d'une pièce certifiée par un tiers</strong> ; il peut être recoupé avec les
            relevés bancaires et les déclarations correspondantes.
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

extension String {
    /// French month and date names arrive lowercase from the formatter.
    public var capitalizedFirstLetter: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}

extension CadenceStore {

    /// Received income, month by month, over a window.
    public func monthlyIncome(in range: DateRange, calendar: Calendar = .cadence) throws -> [MonthlyIncome] {
        var months: [Date] = []
        var cursor = DateRange.month(containing: range.start, calendar: calendar).start
        while cursor < range.end {
            months.append(cursor)
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }

        return try months.map { month in
            let bounds = DateRange.month(containing: month, calendar: calendar)
            let received = try settledPayments(in: bounds)
            let attended = try consultations(in: bounds, includeCancelled: false)
                .filter { $0.status == .attended }
            return MonthlyIncome(
                month: month,
                receivedCents: received.reduce(0) { $0 + $1.amountCents },
                paymentCount: received.count,
                consultationCount: attended.count
            )
        }
    }

    /// Assembles the bank-facing summary for `range`.
    public func incomeReport(
        for range: DateRange,
        settings: PracticeSettings? = nil,
        generatedAt: Date = Date(),
        calendar: Calendar = .cadence
    ) throws -> String {
        let settings = try settings ?? self.settings()
        let statistics = try statistics(for: range, settings: settings)
        let outstanding = try payments(in: range).filter(\.isPending)

        return IncomeReport.html(
            for: IncomeReport.Input(
                practiceName: settings.practiceName,
                range: range,
                months: try monthlyIncome(in: range, calendar: calendar),
                byMethod: statistics.byMethod,
                outstandingCents: outstanding.reduce(0) { $0 + $1.amountCents },
                outstandingCount: outstanding.count,
                currencyCode: settings.currencyCode,
                generatedAt: generatedAt
            )
        )
    }
}
