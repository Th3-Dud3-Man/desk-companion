import SwiftUI
import CadenceCore

/// One appointment on the day rail.
///
/// The whole product is judged on this component: marking someone present and
/// recording their usual payment has to be two clicks, or one keystroke each,
/// without a dialog, a navigation, or a moment's thought.
struct ConsultationRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let item: DayItem
    let isSelected: Bool
    let isHovered: Bool
    let isNext: Bool
    let onSelect: () -> Void

    private var consultation: Consultation { item.consultation }
    private var status: ConsultationStatus { consultation.status }

    /// The payment strip is shown when there is a payment to record — never for an
    /// absence, and never before the patient has actually been marked present.
    private var showsPaymentStrip: Bool { item.awaitsPayment }

    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            timeGutter
            railMarker
            VStack(alignment: .leading, spacing: Space.md) {
                mainLine
                if showsPaymentStrip {
                    PaymentStrip(item: item)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity)
                        )
                }
                if consultation.syncState == .conflict || consultation.syncState == .orphaned {
                    SyncIssueNote(consultation: consultation)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Space.xxl)
        .padding(.vertical, Space.lg)
        .frame(minHeight: Metrics.rowHeight)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Ink.accent)
                .frame(width: isSelected ? 2.5 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .animation(Motion.respectful(Motion.standard, reduceMotion: reduceMotion), value: showsPaymentStrip)
        .animation(Motion.respectful(Motion.instant, reduceMotion: reduceMotion), value: isHovered)
        .contextMenu { RowMenu(item: item) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: Pieces

    private var timeGutter: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(CadenceFormat.time(consultation.scheduledStart))
                .font(isNext ? Typo.bodyStrongNumeric : Typo.bodyNumeric)
                .foregroundStyle(isPast ? Ink.textTertiary : Ink.textPrimary)
            Text(CadenceFormat.duration(consultation.scheduledDuration))
                .font(Typo.caption)
                .foregroundStyle(Ink.textTertiary)
        }
        .frame(width: Metrics.timeGutter, alignment: .leading)
    }

    private var railMarker: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .strokeBorder(markerColour, lineWidth: 1.5)
                    .frame(width: 9, height: 9)
                if status.isResolved || status == .inProgress {
                    Circle().fill(markerColour).frame(width: 5, height: 5)
                }
            }
            .padding(.top, 4)
        }
        .frame(width: 10)
    }

    private var mainLine: some View {
        HStack(spacing: Space.lg) {
            if let patient = item.patient {
                PatientAvatar(patient: patient, size: 28)
            } else {
                UnknownAvatar(size: 28)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(Typo.heading)
                    .foregroundStyle(Ink.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(Typo.caption)
                        .foregroundStyle(Ink.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Space.md)
            trailing
        }
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: Space.md) {
            switch status {
            case .scheduled, .confirmed:
                if isHovered || isSelected || isNext {
                    HStack(spacing: Space.sm) {
                        Button("Présent") { model.mark(.attended, for: item) }
                            .buttonStyle(.cadence(.primary, size: .small))
                            .help("Marquer présent (P)")
                        Button("Absent") { model.mark(.absent, for: item) }
                            .buttonStyle(.cadence(.secondary, size: .small))
                            .help("Marquer absent (A)")
                    }
                } else {
                    StatusChip(status: .of(status))
                }

            case .inProgress:
                HStack(spacing: Space.md) {
                    if let start = consultation.actualStart {
                        Text(CadenceFormat.duration(model.now.timeIntervalSince(start)))
                            .font(Typo.captionNumeric)
                            .foregroundStyle(Ink.accent)
                            .monospacedDigit()
                    }
                    Button("Terminer") { model.endSession(item) }
                        .buttonStyle(.cadence(.primary, size: .small))
                        .help("Terminer la séance et marquer présent")
                }

            case .attended:
                if let payment = item.payment {
                    PaymentBadge(payment: payment, settings: model.settings)
                } else {
                    StatusChip(status: .of(.attended))
                }

            case .absent, .cancelled:
                StatusChip(status: .of(status))
            }

            RowMenuButton(item: item, isVisible: isHovered || isSelected)
        }
    }

    private var subtitle: String? {
        var parts: [String] = []
        if consultation.isUnassigned { parts.append("À rattacher") }
        if let location = consultation.location, !location.isEmpty { parts.append(location) }
        if let duration = consultation.actualDuration {
            parts.append("réel \(CadenceFormat.duration(duration))")
        }
        if status == .attended, item.payment == nil, !parts.contains("À rattacher") {
            parts.append("paiement à enregistrer")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var isPast: Bool {
        model.isShowingToday && consultation.scheduledEnd < model.now
    }

    private var markerColour: Color {
        switch status {
        case .attended, .inProgress: return Ink.accent
        case .absent: return Ink.danger
        case .cancelled: return Ink.textTertiary
        case .scheduled, .confirmed: return isNext ? Ink.accent : Ink.hairlineStrong
        }
    }

    private var rowBackground: some View {
        Group {
            if isSelected {
                Ink.accentSoft.opacity(0.55)
            } else if isHovered {
                Ink.surfaceHover
            } else if showsPaymentStrip {
                Ink.surface
            } else {
                Color.clear
            }
        }
    }

    private var accessibilitySummary: String {
        var parts = [CadenceFormat.time(consultation.scheduledStart), item.title, status.label]
        if let payment = item.payment {
            parts.append("\(payment.money.formatted()) en \(model.settings.methodLabel(payment.methodID))")
        } else if item.awaitsPayment {
            parts.append("paiement à enregistrer")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Recorded payment

struct PaymentBadge: View {
    let payment: Payment
    let settings: PracticeSettings

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: settings.methodSymbol(payment.methodID))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Ink.accent)
            Text(payment.money.formatted())
                .font(Typo.bodyStrongNumeric)
                .foregroundStyle(Ink.textPrimary)
            Text(settings.methodLabel(payment.methodID))
                .font(Typo.caption)
                .foregroundStyle(Ink.textSecondary)
        }
        .padding(.horizontal, Space.md)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).fill(Ink.accentSoft))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Payé \(payment.money.formatted()) en \(settings.methodLabel(payment.methodID))")
    }
}

// MARK: - Payment strip

/// What appears the instant a patient is marked present.
///
/// The habitual payment is one button. Everything else — another method, another
/// amount, deferring — is one click away but visually secondary, because in the
/// overwhelming majority of sessions the first button is the right one.
struct PaymentStrip: View {
    @EnvironmentObject private var model: AppModel
    let item: DayItem

    private var advice: PaymentAdvice { item.advice }
    private var settings: PracticeSettings { model.settings }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.md) {
                primaryButton

                ForEach(alternateSuggestions, id: \.id) { suggestion in
                    Button {
                        model.recordPayment(suggestion, for: item)
                    } label: {
                        HStack(spacing: Space.sm) {
                            Image(systemName: settings.methodSymbol(suggestion.methodID))
                                .font(.system(size: 10, weight: .medium))
                            if suggestion.amountCents == advice.primary.amountCents {
                                Text(settings.methodLabel(suggestion.methodID))
                            } else {
                                Text("\(suggestion.money.formatted()) · \(settings.methodLabel(suggestion.methodID))")
                            }
                        }
                    }
                    .buttonStyle(.cadence(.secondary, size: .small))
                }

                Button("Autre…") {
                    model.present(.editPayment(draftPayment, patientName: item.title))
                }
                .buttonStyle(.cadence(.ghost, size: .small))
                .help("Saisir un autre montant ou ajouter une note")

                Spacer(minLength: Space.md)

                Text(advice.basis.shortLabel)
                    .font(Typo.caption)
                    .foregroundStyle(advice.isHabit ? Ink.accent : Ink.textTertiary)
                    .help(advice.basis.label)
            }
        }
        .padding(.top, Space.xxs)
    }

    private var primaryButton: some View {
        Button {
            model.recordPayment(advice.primary, for: item)
        } label: {
            HStack(spacing: Space.md) {
                Image(systemName: settings.methodSymbol(advice.primary.methodID))
                    .font(.system(size: 12, weight: .medium))
                Text(advice.primary.money.formatted())
                    .font(Typo.headingNumeric)
                Text(settings.methodLabel(advice.primary.methodID))
                    .font(Typo.body)
                    .opacity(0.85)
                Text("⏎")
                    .font(Typo.caption)
                    .opacity(0.6)
                    .padding(.leading, Space.xs)
            }
        }
        .buttonStyle(.cadence(.primary, size: .large))
        .help(advice.basis.label)
        .accessibilityLabel("Enregistrer \(advice.primary.money.formatted()) en \(settings.methodLabel(advice.primary.methodID)). \(advice.basis.label)")
    }

    /// Other combinations this patient has actually used, then the remaining methods
    /// at the same amount. Capped so the row never becomes a wall of buttons.
    private var alternateSuggestions: [PaymentSuggestion] {
        var seen: Set<String> = [advice.primary.id]
        var result: [PaymentSuggestion] = []
        for suggestion in advice.alternatives where !seen.contains(suggestion.id) {
            seen.insert(suggestion.id)
            result.append(suggestion)
            if result.count == 2 { break }
        }
        for suggestion in advice.quickMethodSwitches where !seen.contains(suggestion.id) {
            seen.insert(suggestion.id)
            result.append(suggestion)
            if result.count == 3 { break }
        }
        return result
    }

    private var draftPayment: Payment {
        Payment(
            consultationID: item.consultation.id,
            patientID: item.patient?.id ?? UUID(),
            amountCents: advice.primary.amountCents,
            currencyCode: settings.currencyCode,
            methodID: advice.primary.methodID,
            paidAt: Date()
        )
    }
}

// MARK: - Sync issues

struct SyncIssueNote: View {
    @EnvironmentObject private var model: AppModel
    let consultation: Consultation

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: consultation.syncState == .conflict ? "arrow.triangle.branch" : "calendar.badge.minus")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Ink.warning)
            Text(message)
                .font(Typo.caption)
                .foregroundStyle(Ink.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.md)
            if consultation.syncState == .conflict {
                Button("Garder l'agenda") { model.resolveConflict(consultation, keepingCalendar: true) }
                    .buttonStyle(.cadence(.ghost, size: .small))
                Button("Garder Cadence") { model.resolveConflict(consultation, keepingCalendar: false) }
                    .buttonStyle(.cadence(.secondary, size: .small))
            } else {
                Button("Détacher de l'agenda") { model.resolveConflict(consultation, keepingCalendar: false) }
                    .buttonStyle(.cadence(.ghost, size: .small))
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Ink.warningSoft))
    }

    private var message: String {
        consultation.syncState == .conflict
            ? "Ce rendez-vous a changé dans votre agenda après avoir été traité ici. Cadence n'a rien modifié."
            : "Ce rendez-vous a disparu de votre agenda, mais il porte des informations : il a été conservé."
    }
}

// MARK: - Row menu

struct RowMenuButton: View {
    let item: DayItem
    let isVisible: Bool

    var body: some View {
        Menu {
            RowMenu(item: item)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Ink.textSecondary)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 24)
        .opacity(isVisible ? 1 : 0)
        .accessibilityLabel("Autres actions")
    }
}

struct RowMenu: View {
    @EnvironmentObject private var model: AppModel
    let item: DayItem

    var body: some View {
        if !item.consultation.status.isResolved {
            Button("Marquer présent") { model.mark(.attended, for: item) }
            Button("Marquer absent") { model.mark(.absent, for: item) }
            Divider()
        }

        if item.consultation.status == .inProgress {
            Button("Terminer la séance") { model.endSession(item) }
        } else if item.consultation.status != .attended {
            Button("Démarrer la séance") { model.startSession(item) }
        }

        if item.consultation.status == .attended, item.payment == nil {
            Button("Enregistrer \(item.advice.primary.money.formatted())") {
                model.recordPayment(item.advice.primary, for: item)
            }
        }

        if item.consultation.status == .absent {
            // Some practices bill late cancellations; Cadence never asks, but allows it.
            Button("Facturer l'absence…") {
                model.present(.editPayment(
                    Payment(
                        consultationID: item.consultation.id,
                        patientID: item.patient?.id ?? UUID(),
                        amountCents: item.advice.primary.amountCents,
                        currencyCode: model.settings.currencyCode,
                        methodID: item.advice.primary.methodID
                    ),
                    patientName: item.title
                ))
            }
            .disabled(item.patient == nil)
        }

        if let payment = item.payment {
            Divider()
            Button("Modifier le paiement…") {
                model.present(.editPayment(payment, patientName: item.title))
            }
            Button("Supprimer le paiement") {
                model.deletePayment(payment, patientName: item.title)
            }
        }

        Divider()

        if item.consultation.isUnassigned {
            Menu("Associer à…") {
                ForEach(model.patients) { patient in
                    Button(patient.displayName) { model.assign(patientID: patient.id, to: item.consultation) }
                }
            }
            Button("Créer « \(AppModel.suggestedName(from: item.consultation.title)) »") {
                model.createPatientAndAssign(from: item.consultation)
            }
        } else if let patient = item.patient {
            Button("Ouvrir la fiche de \(patient.displayName)") {
                model.destination = .patients
                model.selectPatient(patient.id)
            }
            Menu("Changer de patient…") {
                ForEach(model.patients) { candidate in
                    Button(candidate.displayName) { model.assign(patientID: candidate.id, to: item.consultation) }
                }
            }
        }

        Divider()
        Button("Modifier le rendez-vous…") { model.present(.editConsultation(item.consultation)) }
        if item.consultation.status != .cancelled {
            Button("Annuler le rendez-vous") { model.mark(.cancelled, for: item) }
        }
        Button("Supprimer le rendez-vous") { model.deleteConsultation(item.consultation) }
    }
}
