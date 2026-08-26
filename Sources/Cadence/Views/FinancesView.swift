import SwiftUI
import CadenceCore

enum StatsPeriod: String, CaseIterable, Identifiable {
    case day, week, month, year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "Jour"
        case .week: return "Semaine"
        case .month: return "Mois"
        case .year: return "Année"
        }
    }

    func range(containing date: Date) -> DateRange {
        switch self {
        case .day: return .day(containing: date)
        case .week: return .week(containing: date)
        case .month: return .month(containing: date)
        case .year: return .year(containing: date)
        }
    }

    func label(for date: Date) -> String {
        switch self {
        case .day: return CadenceFormat.dayFull(date).capitalizedFirst
        case .week:
            let range = DateRange.week(containing: date)
            let end = Calendar.cadence.date(byAdding: .day, value: 6, to: range.start) ?? range.start
            return "Semaine du \(CadenceFormat.dayShort(range.start)) au \(CadenceFormat.dayShort(end))"
        case .month: return CadenceFormat.monthYear(date).capitalizedFirst
        case .year: return String(Calendar.cadence.component(.year, from: date))
        }
    }

    var component: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }

    var previousLabel: String {
        switch self {
        case .day: return "la veille"
        case .week: return "la semaine précédente"
        case .month: return "le mois précédent"
        case .year: return "l'année précédente"
        }
    }
}

/// Not an accounting package: a small set of figures that answer "how is the
/// practice doing?", each one traceable to the records behind it.
@MainActor
struct FinancesView: View {
    @EnvironmentObject private var model: AppModel

    @State private var period: StatsPeriod = .month
    @State private var anchor = Date()
    @State private var comparison: PeriodComparison?
    @State private var daily: [DailyTotal] = []

    private var range: DateRange { period.range(containing: anchor) }
    private var statistics: PeriodStatistics { comparison?.current ?? .empty(range: range) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: Space.huge) {
                    headline
                    if statistics.planned > 0 || statistics.paymentCount > 0 {
                        chart
                        HStack(alignment: .top, spacing: Space.xl) {
                            methodsCard
                            attendanceCard
                        }
                    } else {
                        EmptyState(
                            symbol: "chart.bar",
                            title: "Aucune activité sur cette période",
                            message: "Changez de période, ou enregistrez des consultations pour voir apparaître les chiffres."
                        )
                        .frame(height: 220)
                    }
                    exports
                }
                .padding(Space.xxl)
            }
            .scrollContentBackground(.hidden)
        }
        .onAppear { anchor = model.selectedDay; load() }
        .onChange(of: period) { _, _ in load() }
        .onChange(of: anchor) { _, _ in load() }
        .onChange(of: model.dataRevision) { _, _ in load() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: 1) {
                Text(period.label(for: anchor))
                    .font(Typo.display)
                    .foregroundStyle(Ink.textPrimary)
                Text(subtitle)
                    .font(Typo.body)
                    .foregroundStyle(Ink.textSecondary)
            }
            Spacer(minLength: Space.lg)

            Picker("", selection: $period) {
                ForEach(StatsPeriod.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)

            HStack(spacing: Space.xs) {
                Button { shift(-1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.cadence(.ghost, size: .small))
                Button("Actuel") { anchor = Date() }
                    .buttonStyle(.cadence(.secondary, size: .small))
                    .disabled(range.contains(Date()))
                Button { shift(1) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.cadence(.ghost, size: .small))
            }
        }
        .padding(.horizontal, Space.xxl)
        .padding(.vertical, Space.xl)
    }

    private var subtitle: String {
        guard statistics.planned > 0 || statistics.paymentCount > 0 else { return "Aucune activité enregistrée" }
        var parts = ["\(statistics.attended) consultation\(statistics.attended > 1 ? "s" : "")"]
        if statistics.absent > 0 { parts.append("\(statistics.absent) absence\(statistics.absent > 1 ? "s" : "")") }
        if statistics.uniquePatients > 0 { parts.append("\(statistics.uniquePatients) patient\(statistics.uniquePatients > 1 ? "s" : "")") }
        return parts.joined(separator: " · ")
    }

    private func shift(_ steps: Int) {
        guard let next = Calendar.cadence.date(byAdding: period.component, value: steps, to: anchor) else { return }
        anchor = next
    }

    // MARK: Cards

    private var headline: some View {
        HStack(alignment: .top, spacing: Space.xl) {
            MetricTile(
                label: "Encaissé",
                value: statistics.revenue(currencyCode: model.settings.currencyCode).formatted(),
                note: "\(statistics.paymentCount) paiement\(statistics.paymentCount > 1 ? "s" : "")",
                tone: .positive
            )
            Divider().frame(height: 58)
            MetricTile(
                label: "Consultations",
                value: "\(statistics.attended)",
                note: "sur \(statistics.planned) prévue\(statistics.planned > 1 ? "s" : "")"
            )
            Divider().frame(height: 58)
            MetricTile(
                label: "Moyenne",
                value: statistics.averagePerAttendedCents
                    .map { Money(cents: $0, currencyCode: model.settings.currencyCode).formatted() } ?? "—",
                note: "par consultation honorée"
            )
            Divider().frame(height: 58)
            evolutionTile
        }
        .cadenceCard(padding: Space.xl)
    }

    @ViewBuilder
    private var evolutionTile: some View {
        if let comparison, let change = comparison.revenueChange {
            let percentage = Int((change * 100).rounded())
            MetricTile(
                label: "Évolution",
                value: percentage == 0 ? "stable" : "\(percentage > 0 ? "+" : "")\(percentage) %",
                note: "vs. \(period.previousLabel) (\(comparison.previous.revenue(currencyCode: model.settings.currencyCode).formatted()))",
                tone: percentage == 0 ? .neutral : (percentage > 0 ? .positive : .negative)
            )
        } else {
            MetricTile(
                label: "Évolution",
                value: "—",
                note: "pas d'activité sur \(period.previousLabel)"
            )
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack {
                SectionLabel(text: period == .year ? "Par jour d'activité" : "Jour par jour")
                Spacer()
                if let peak = daily.map(\.totalCents).max(), peak > 0 {
                    Text("maximum \(Money(cents: peak, currencyCode: model.settings.currencyCode).formatted())")
                        .font(Typo.caption)
                        .foregroundStyle(Ink.textTertiary)
                }
            }
            RevenueChart(totals: daily, currencyCode: model.settings.currencyCode)
                .frame(height: 132)
        }
        .cadenceCard(padding: Space.xl)
    }

    private var methodsCard: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            SectionLabel(text: "Répartition des moyens de paiement")
            if statistics.byMethod.isEmpty {
                Text("Aucun paiement sur la période.")
                    .font(Typo.caption)
                    .foregroundStyle(Ink.textTertiary)
            } else {
                ShareBar(
                    slices: statistics.byMethod.map { method in
                        (colour: Ink.monogramTint(seed: Patient.seed(for: method.methodID)), share: method.share)
                    },
                    height: 8
                )
                VStack(spacing: Space.md) {
                    ForEach(statistics.byMethod) { method in
                        HStack(spacing: Space.md) {
                            Circle()
                                .fill(Ink.monogramTint(seed: Patient.seed(for: method.methodID)))
                                .frame(width: 8, height: 8)
                            Text(method.label)
                                .font(Typo.body)
                                .foregroundStyle(Ink.textPrimary)
                            Text("\(method.count)")
                                .font(Typo.captionNumeric)
                                .foregroundStyle(Ink.textTertiary)
                            Spacer(minLength: Space.md)
                            Text("\(Int((method.share * 100).rounded())) %")
                                .font(Typo.captionNumeric)
                                .foregroundStyle(Ink.textSecondary)
                            Text(method.money(currencyCode: model.settings.currencyCode).formatted())
                                .font(Typo.bodyStrongNumeric)
                                .foregroundStyle(Ink.textPrimary)
                                .frame(width: 76, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceCard(padding: Space.xl)
    }

    private var attendanceCard: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            SectionLabel(text: "Assiduité")
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text(statistics.attendanceRate.map { "\(Int(($0 * 100).rounded())) %" } ?? "—")
                    .font(Typo.displayNumeric)
                    .foregroundStyle(Ink.textPrimary)
                Text("de présence")
                    .font(Typo.caption)
                    .foregroundStyle(Ink.textSecondary)
            }
            ProgressBar(fraction: statistics.attendanceRate ?? 0)

            VStack(spacing: Space.md) {
                statLine("Présents", "\(statistics.attended)", Ink.accent)
                statLine("Absents", "\(statistics.absent)", Ink.danger)
                if statistics.cancelled > 0 { statLine("Annulés", "\(statistics.cancelled)", Ink.textTertiary) }
                if statistics.pending > 0 { statLine("À traiter", "\(statistics.pending)", Ink.warning) }
                if statistics.unpaidAttended > 0 {
                    statLine("Présents sans paiement", "\(statistics.unpaidAttended)", Ink.warning)
                }
                if let average = statistics.measuredDurationAverage {
                    statLine("Durée réelle moyenne", CadenceFormat.duration(average), Ink.textSecondary)
                    Text("Mesurée sur \(statistics.measuredDurationCount) séance\(statistics.measuredDurationCount > 1 ? "s" : "") démarrées et terminées dans Cadence.")
                        .font(Typo.caption)
                        .foregroundStyle(Ink.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceCard(padding: Space.xl)
    }

    private func statLine(_ label: String, _ value: String, _ tint: Color) -> some View {
        HStack(spacing: Space.md) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(label).font(Typo.body).foregroundStyle(Ink.textSecondary)
            Spacer(minLength: Space.md)
            Text(value).font(Typo.bodyStrongNumeric).foregroundStyle(Ink.textPrimary)
        }
    }

    private var exports: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            SectionLabel(text: "Exporter")
            Text("Les exports portent sur la période affichée et produisent un vrai fichier, prêt pour un tableur ou un comptable.")
                .font(Typo.caption)
                .foregroundStyle(Ink.textSecondary)
            HStack(spacing: Space.md) {
                Button("Paiements (CSV)") {
                    model.requestExport(.payments, range: range, rangeLabel: period.label(for: anchor))
                }
                .buttonStyle(.cadenceSecondary)

                Button("Consultations (CSV)") {
                    model.requestExport(.consultations, range: range, rangeLabel: period.label(for: anchor))
                }
                .buttonStyle(.cadenceSecondary)

                Button("Patients (CSV)") {
                    model.requestExport(.patients, range: range, rangeLabel: "Tous")
                }
                .buttonStyle(.cadenceSecondary)

                Divider().frame(height: 18)

                Button("Rapport d'activité (PDF)") {
                    model.requestReport(range: range, title: "Activité · \(period.label(for: anchor))")
                }
                .buttonStyle(.cadencePrimary)
            }
        }
        .cadenceCard(padding: Space.xl)
    }

    private func load() {
        do {
            comparison = try model.store.comparison(for: range, settings: model.settings)
            daily = try model.store.dailyTotals(in: range)
        } catch {
            model.report(error)
        }
    }
}

/// A plain column chart. No library, no animation, no decoration — it exists to be
/// read at a glance.
@MainActor
struct RevenueChart: View {
    let totals: [DailyTotal]
    let currencyCode: String

    var body: some View {
        GeometryReader { geometry in
            let peak = max(1, totals.map(\.totalCents).max() ?? 1)
            let count = max(1, totals.count)
            let spacing: CGFloat = count > 40 ? 1 : (count > 14 ? 2 : 5)
            let barWidth = max(2, (geometry.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(totals) { total in
                    let fraction = Double(total.totalCents) / Double(peak)
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: min(3, barWidth / 2), style: .continuous)
                            .fill(total.totalCents > 0 ? Ink.accent : Ink.hairline)
                            .frame(
                                width: barWidth,
                                height: max(total.totalCents > 0 ? 3 : 1, CGFloat(fraction) * (geometry.size.height - 16))
                            )
                    }
                    .help("\(CadenceFormat.numericDate(total.day)) · \(Money(cents: total.totalCents, currencyCode: currencyCode).formatted()) · \(total.consultationCount) consultation(s)")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityLabel("Recettes jour par jour")
    }
}
