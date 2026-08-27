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
                if !model.pendingPayments.isEmpty { awaitingSettlement }
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
        VStack(alignment: .leading, spacing: Space.lg) {
            MetricTile(
                label: "Encaissé",
                value: statistics.revenue(currencyCode: model.settings.currencyCode).formatted(),
                note: statistics.paymentCount == 0
                    ? "Aucun paiement reçu"
                    : "\(statistics.paymentCount) paiement\(statistics.paymentCount > 1 ? "s" : "")",
                tone: statistics.revenueCents > 0 ? .positive : .neutral
            )
            if statistics.hasPending {
                HStack(spacing: Space.sm) {
                    Image(systemName: "clock.badge")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Ink.warning)
                    Text("\(statistics.pending(currencyCode: model.settings.currencyCode).formatted()) annoncés, en attente")
                        .font(Typo.caption)
                        .foregroundStyle(Ink.warning)
                }
            }
        }
    }

    /// The transfers and cheques waiting to land. Ticking one off is a single click,
    /// right where the user is already looking at the day's money.
    private var awaitingSettlement: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                SectionLabel(text: "En attente de règlement")
                Spacer()
                Text(Money(cents: model.outstandingCents,
                           currencyCode: model.settings.currencyCode).formatted())
                    .font(Typo.captionNumeric)
                    .foregroundStyle(Ink.warning)
            }
            VStack(spacing: Space.xs) {
                ForEach(model.pendingPayments.prefix(5)) { payment in
                    HStack(spacing: Space.md) {
                        SettlementTick(isSettled: false) { model.settle(payment) }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(model.patient(id: payment.patientID)?.displayName ?? "—")
                                .font(Typo.caption)
                                .foregroundStyle(Ink.textPrimary)
                                .lineLimit(1)
                            Text("\(model.settings.methodLabel(payment.methodID)) · \(CadenceFormat.numericDate(payment.paidAt))")
                                .font(Typo.caption)
                                .foregroundStyle(Ink.textTertiary)
                        }
                        Spacer(minLength: Space.sm)
                        Text(payment.money.formatted())
                            .font(Typo.captionNumeric)
                            .foregroundStyle(Ink.textPrimary)
                    }
                }
                if model.pendingPayments.count > 5 {
                    Button("Voir les \(model.pendingPayments.count) en attente") {
                        model.destination = .finances
                    }
                    .buttonStyle(.cadence(.ghost, size: .small))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(text: "Avancement")
            HStack(spacing: Space.lg) {
                DayProgressRing(done: statistics.attended + statistics.absent, total: statistics.planned)
                VStack(alignment: .leading, spacing: 2) {
                    Text(progressHeadline)
                        .font(Typo.bodyStrong)
                        .foregroundStyle(statistics.pending == 0 && statistics.planned > 0 ? Ink.accent : Ink.textPrimary)
                    Text("sur \(statistics.planned) rendez-vous")
                        .font(Typo.caption)
                        .foregroundStyle(Ink.textSecondary)
                }
                Spacer(minLength: 0)
            }
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

    private var progressHeadline: String {
        if statistics.planned == 0 { return "Rien de prévu" }
        if statistics.pending == 0 { return "Journée bouclée" }
        return "\(statistics.attended + statistics.absent) traités"
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
