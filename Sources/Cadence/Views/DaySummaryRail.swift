import SwiftUI
import CadenceCore

/// The right-hand rail: what the day has produced and what is still outstanding.
/// It answers "am I done?" without the user counting rows.
@MainActor
struct DaySummaryRail: View {
    @EnvironmentObject private var model: AppModel

    private var statistics: PeriodStatistics { model.dayStatistics }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                takings
                progress
                if !statistics.byMethod.isEmpty { methods }
                if !model.itemsAwaitingPayment.isEmpty { outstanding }
                if statistics.absent > 0 { absences }
                Spacer(minLength: Space.md)
            }
            .padding(Space.xl)
        }
        .scrollContentBackground(.hidden)
        .background(Ink.surface)
    }

    // MARK: Sections

    private var takings: some View {
        MetricTile(
            label: "Encaissé",
            value: statistics.revenue(currencyCode: model.settings.currencyCode).formatted(),
            note: statistics.paymentCount == 0
                ? "Aucun paiement enregistré"
                : "\(statistics.paymentCount) paiement\(statistics.paymentCount > 1 ? "s" : "")",
            tone: statistics.revenueCents > 0 ? .positive : .neutral
        )
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(text: "Avancement")
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text("\(statistics.attended + statistics.absent)")
                    .font(Typo.titleNumeric)
                    .foregroundStyle(Ink.textPrimary)
                Text("sur \(statistics.planned) rendez-vous")
                    .font(Typo.caption)
                    .foregroundStyle(Ink.textSecondary)
            }
            ProgressBar(
                fraction: statistics.planned == 0
                    ? 0
                    : Double(statistics.attended + statistics.absent) / Double(statistics.planned)
            )
            HStack(spacing: Space.lg) {
                CountLabel(symbol: "checkmark.circle.fill", tint: Ink.accent,
                           value: statistics.attended, label: "présents")
                if statistics.absent > 0 {
                    CountLabel(symbol: "xmark.circle.fill", tint: Ink.danger,
                               value: statistics.absent, label: "absents")
                }
                if statistics.pending > 0 {
                    CountLabel(symbol: "circle.dashed", tint: Ink.textTertiary,
                               value: statistics.pending, label: "à venir")
                }
            }
        }
    }

    private var methods: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(text: "Moyens de paiement")
            ShareBar(
                slices: statistics.byMethod.map { method in
                    (colour: Ink.monogramTint(seed: Patient.seed(for: method.methodID)), share: method.share)
                }
            )
            VStack(spacing: Space.sm) {
                ForEach(statistics.byMethod) { method in
                    HStack(spacing: Space.md) {
                        Circle()
                            .fill(Ink.monogramTint(seed: Patient.seed(for: method.methodID)))
                            .frame(width: 7, height: 7)
                        Text(method.label)
                            .font(Typo.caption)
                            .foregroundStyle(Ink.textSecondary)
                        Spacer(minLength: Space.sm)
                        Text(method.money(currencyCode: model.settings.currencyCode).formatted())
                            .font(Typo.captionNumeric)
                            .foregroundStyle(Ink.textPrimary)
                    }
                }
            }
        }
    }

    private var outstanding: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                SectionLabel(text: "Reste à traiter")
                Spacer()
                Text("\(model.itemsAwaitingPayment.count)")
                    .font(Typo.captionNumeric)
                    .foregroundStyle(Ink.warning)
            }
            VStack(spacing: Space.xs) {
                ForEach(model.itemsAwaitingPayment) { item in
                    Button {
                        model.recordPayment(item.advice.primary, for: item)
                    } label: {
                        HStack(spacing: Space.md) {
                            Text(CadenceFormat.time(item.consultation.scheduledStart))
                                .font(Typo.captionNumeric)
                                .foregroundStyle(Ink.textTertiary)
                            Text(item.title)
                                .font(Typo.caption)
                                .foregroundStyle(Ink.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: Space.sm)
                            Text(item.advice.primary.money.formatted())
                                .font(Typo.captionNumeric)
                                .foregroundStyle(Ink.accent)
                        }
                        .padding(.horizontal, Space.md)
                        .frame(height: 26)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.cadence(.ghost, size: .small))
                    .help("Enregistrer \(item.advice.primary.money.formatted()) pour \(item.title)")
                }
            }
        }
    }

    private var absences: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel(text: "Absences")
            ForEach(model.dayItems.filter { $0.consultation.status == .absent }) { item in
                HStack(spacing: Space.md) {
                    Text(CadenceFormat.time(item.consultation.scheduledStart))
                        .font(Typo.captionNumeric)
                        .foregroundStyle(Ink.textTertiary)
                    Text(item.title)
                        .font(Typo.caption)
                        .foregroundStyle(Ink.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

@MainActor
struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.surfaceSunken)
                Capsule()
                    .fill(Ink.accent)
                    .frame(width: max(0, min(1, fraction)) * geometry.size.width)
            }
        }
        .frame(height: 5)
        .accessibilityLabel("Avancement : \(Int((fraction * 100).rounded())) %")
    }
}

@MainActor
struct CountLabel: View {
    let symbol: String
    let tint: Color
    let value: Int
    let label: String

    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(tint)
            Text("\(value)")
                .font(Typo.captionNumeric)
                .foregroundStyle(Ink.textPrimary)
            Text(label)
                .font(Typo.caption)
                .foregroundStyle(Ink.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}
