import SwiftUI
import CadenceCore

@MainActor
struct PatientsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var showsArchived = false

    var body: some View {
        HStack(spacing: 0) {
            listColumn
                .frame(width: 268)
            Hairline().frame(width: 1).frame(maxHeight: .infinity)
            detailColumn
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: List

    private var listColumn: some View {
        VStack(spacing: 0) {
            VStack(spacing: Space.md) {
                HStack(spacing: Space.md) {
                    CadenceTextField(placeholder: "Rechercher un patient", text: $query, symbol: "magnifyingglass")
                    Button {
                        model.requestNewPatient()
                    } label: {
                        Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.cadence(.primary, size: .regular))
                    .help("Nouveau patient (⇧⌘N)")
                }

                HStack {
                    Text("\(filtered.count) patient\(filtered.count > 1 ? "s" : "")")
                        .font(Typo.caption)
                        .foregroundStyle(Ink.textTertiary)
                    Spacer()
                    Toggle("Archivés", isOn: $showsArchived)
                        .toggleStyle(.checkbox)
                        .font(Typo.caption)
                }
            }
            .padding(Space.lg)

            Hairline()

            if filtered.isEmpty {
                EmptyState(
                    symbol: query.isEmpty ? "person.2" : "magnifyingglass",
                    title: query.isEmpty ? "Aucun patient" : "Aucun résultat",
                    message: query.isEmpty ? "Les patients apparaissent ici dès qu'un rendez-vous leur est rattaché." : nil,
                    actionTitle: query.isEmpty ? "Créer un patient" : nil,
                    action: query.isEmpty ? { model.requestNewPatient() } : nil
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { patient in
                            PatientListRow(
                                patient: patient,
                                isSelected: model.selectedPatientID == patient.id
                            )
                            .onTapGesture { model.selectPatient(patient.id) }
                        }
                    }
                    .padding(.vertical, Space.xs)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Ink.surface)
    }

    private var filtered: [Patient] {
        (try? model.store.searchPatients(query, includeArchived: showsArchived)) ?? []
    }

    // MARK: Detail

    @ViewBuilder
    private var detailColumn: some View {
        if let profile = model.selectedProfile {
            PatientRecord(profile: profile)
        } else {
            EmptyState(
                symbol: "person.text.rectangle",
                title: "Sélectionnez un patient",
                message: "Son historique, ses paiements et ses habitudes s'afficheront ici."
            )
        }
    }
}

@MainActor
private struct PatientListRow: View {
    @EnvironmentObject private var model: AppModel
    let patient: Patient
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Space.lg) {
            PatientAvatar(patient: patient, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(patient.displayName)
                    .font(Typo.bodyStrong)
                    .foregroundStyle(Ink.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(Typo.caption)
                        .foregroundStyle(Ink.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if patient.isArchived {
                Image(systemName: "archivebox")
                    .font(.system(size: 10))
                    .foregroundStyle(Ink.textTertiary)
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .background(isSelected ? Ink.accentSoft : (isHovered ? Ink.surfaceHover : Color.clear))
        .overlay(alignment: .leading) {
            Rectangle().fill(Ink.accent).frame(width: isSelected ? 2.5 : 0)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var subtitle: String? {
        patient.phone ?? patient.email
    }
}

// MARK: - Record

@MainActor
struct PatientRecord: View {
    @EnvironmentObject private var model: AppModel
    let profile: PatientProfile

    @State private var confirmsDeletion = false

    private var patient: Patient { profile.patient }
    private var settings: PracticeSettings { model.settings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.huge) {
                header
                habitCard
                metrics
                if let next = profile.nextAppointment { nextAppointment(next) }
                if !profile.unpaidConsultations.isEmpty { unpaid }
                history
                if !profile.payments.isEmpty { payments }
                if let notes = patient.notes, !notes.isEmpty { notesSection(notes) }
            }
            .padding(Space.xxl)
        }
        .scrollContentBackground(.hidden)
        .alert("Supprimer \(patient.displayName) ?", isPresented: $confirmsDeletion) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer définitivement", role: .destructive) { model.deletePatient(patient) }
        } message: {
            let impact = model.deletionImpact(for: patient)
            Text("\(impact.payments) paiement(s) seront supprimés et \(impact.consultations) rendez-vous perdront leur rattachement. Cette action ne peut pas être annulée — préférez l'archivage si vous souhaitez seulement masquer ce patient.")
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top, spacing: Space.xl) {
            PatientAvatar(patient: patient, size: 52)

            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.md) {
                    Text(patient.displayName)
                        .font(Typo.display)
                        .foregroundStyle(Ink.textPrimary)
                    if patient.isArchived {
                        Text("Archivé")
                            .font(Typo.label)
                            .textCase(.uppercase)
                            .foregroundStyle(Ink.textSecondary)
                            .padding(.horizontal, Space.sm)
                            .frame(height: 18)
                            .background(Capsule().fill(Ink.neutralSoft))
                    }
                    if patient.isDemo {
                        Text("Démonstration")
                            .font(Typo.label)
                            .textCase(.uppercase)
                            .foregroundStyle(Ink.warning)
                            .padding(.horizontal, Space.sm)
                            .frame(height: 18)
                            .background(Capsule().fill(Ink.warningSoft))
                    }
                }

                HStack(spacing: Space.lg) {
                    if let phone = patient.phone { contactLine("phone", phone) }
                    if let email = patient.email { contactLine("envelope", email) }
                    if let slot = profile.usualSlotDescription { contactLine("clock", slot) }
                }
            }

            Spacer(minLength: Space.lg)

            HStack(spacing: Space.md) {
                Button("Nouveau rendez-vous") {
                    model.requestNewConsultation(at: nil, for: patient.id)
                }
                .buttonStyle(.cadence(.secondary, size: .small))

                Menu {
                    Button("Modifier…") { model.present(.editPatient(patient)) }
                    Button(patient.isArchived ? "Réactiver" : "Archiver") {
                        model.setPatientArchived(patient, archived: !patient.isArchived)
                    }
                    Divider()
                    Button("Supprimer…", role: .destructive) { confirmsDeletion = true }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 28)
            }
        }
    }

    private func contactLine(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: Space.xs) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(Ink.textTertiary)
            Text(text)
                .font(Typo.caption)
                .foregroundStyle(Ink.textSecondary)
        }
    }

    /// What Cadence has learned, stated plainly and with its evidence.
    private var habitCard: some View {
        HStack(alignment: .top, spacing: Space.xxl) {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionLabel(text: "Paiement proposé")
                HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                    Text(profile.advice.primary.money.formatted())
                        .font(Typo.displayNumeric)
                        .foregroundStyle(Ink.accent)
                    Text(settings.methodLabel(profile.advice.primary.methodID))
                        .font(Typo.body)
                        .foregroundStyle(Ink.textSecondary)
                }
                Text(profile.advice.basis.label)
                    .font(Typo.caption)
                    .foregroundStyle(profile.advice.isHabit ? Ink.accent : Ink.textTertiary)
                if profile.advice.isHabit {
                    ConfidenceBar(confidence: profile.advice.confidence)
                        .frame(width: 130)
                }
            }

            Divider().frame(height: 62)

            VStack(alignment: .leading, spacing: Space.sm) {
                SectionLabel(text: "Rythme")
                Text(profile.rhythm.label)
                    .font(Typo.bodyStrong)
                    .foregroundStyle(Ink.textPrimary)
                if let first = profile.firstSeen {
                    Text("Suivi depuis le \(CadenceFormat.numericDate(first))")
                        .font(Typo.caption)
                        .foregroundStyle(Ink.textTertiary)
                }
                if let average = profile.measuredDurationAverage {
                    Text("Durée réelle moyenne \(CadenceFormat.duration(average))")
                        .font(Typo.caption)
                        .foregroundStyle(Ink.textTertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .cadenceCard(padding: Space.xl)
    }

    private var metrics: some View {
        HStack(alignment: .top, spacing: Space.xl) {
            MetricTile(label: "Consultations", value: "\(profile.attended)",
                       note: profile.upcoming > 0 ? "\(profile.upcoming) à venir" : nil, isCompact: true)
            MetricTile(label: "Absences", value: "\(profile.absent)",
                       note: profile.attendanceRate.map { "présence \(Int(($0 * 100).rounded())) %" },
                       tone: profile.absent > 0 ? .warning : .neutral, isCompact: true)
            MetricTile(label: "Total encaissé",
                       value: profile.totalCollected(currencyCode: settings.currencyCode).formatted(),
                       note: "\(profile.paymentCount) paiement\(profile.paymentCount > 1 ? "s" : "")",
                       tone: .positive, isCompact: true)
            MetricTile(label: "Dernière séance",
                       value: profile.lastSeen.map(CadenceFormat.dayShort) ?? "—",
                       note: profile.lastSeen.map { CadenceFormat.since($0) },
                       isCompact: true)
        }
        .cadenceCard(padding: Space.xl)
    }

    private func nextAppointment(_ consultation: Consultation) -> some View {
        HStack(spacing: Space.lg) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Ink.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Prochain rendez-vous")
                    .font(Typo.caption)
                    .foregroundStyle(Ink.textTertiary)
                Text("\(CadenceFormat.dayLong(consultation.scheduledStart).capitalizedFirst) à \(CadenceFormat.time(consultation.scheduledStart))")
                    .font(Typo.bodyStrong)
                    .foregroundStyle(Ink.textPrimary)
            }
            Spacer()
            Button("Voir ce jour") { model.select(day: consultation.scheduledStart); model.destination = .today }
                .buttonStyle(.cadence(.secondary, size: .small))
        }
        .cadenceCard(padding: Space.lg)
    }

    private var unpaid: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(text: "Consultations sans paiement")
            VStack(spacing: 0) {
                ForEach(Array(profile.unpaidConsultations.prefix(6))) { consultation in
                    HStack(spacing: Space.lg) {
                        Text(CadenceFormat.numericDate(consultation.scheduledStart))
                            .font(Typo.captionNumeric)
                            .foregroundStyle(Ink.textSecondary)
                        Text(CadenceFormat.time(consultation.scheduledStart))
                            .font(Typo.captionNumeric)
                            .foregroundStyle(Ink.textTertiary)
                        Spacer()
                        Button("Enregistrer \(profile.advice.primary.money.formatted())") {
                            model.present(.editPayment(
                                Payment(
                                    consultationID: consultation.id,
                                    patientID: patient.id,
                                    amountCents: profile.advice.primary.amountCents,
                                    currencyCode: settings.currencyCode,
                                    methodID: profile.advice.primary.methodID,
                                    paidAt: consultation.scheduledEnd
                                ),
                                patientName: patient.displayName
                            ))
                        }
                        .buttonStyle(.cadence(.secondary, size: .small))
                    }
                    .padding(.vertical, Space.sm)
                    if consultation.id != profile.unpaidConsultations.prefix(6).last?.id { Hairline() }
                }
            }
            .cadenceCard(padding: Space.lg)
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                SectionLabel(text: "Historique")
                Spacer()
                Text("\(profile.consultations.count) rendez-vous")
                    .font(Typo.caption)
                    .foregroundStyle(Ink.textTertiary)
            }

            let paymentsByConsultation = Dictionary(
                profile.payments.compactMap { payment -> (UUID, Payment)? in
                    guard let id = payment.consultationID else { return nil }
                    return (id, payment)
                },
                uniquingKeysWith: { first, _ in first }
            )

            VStack(spacing: 0) {
                ForEach(Array(profile.consultations.prefix(24))) { consultation in
                    HStack(spacing: Space.lg) {
                        Text(CadenceFormat.numericDate(consultation.scheduledStart))
                            .font(Typo.captionNumeric)
                            .foregroundStyle(Ink.textSecondary)
                            .frame(width: 82, alignment: .leading)
                        Text(CadenceFormat.time(consultation.scheduledStart))
                            .font(Typo.captionNumeric)
                            .foregroundStyle(Ink.textTertiary)
                            .frame(width: 44, alignment: .leading)
                        StatusChip(status: .of(consultation.status))
                        if let duration = consultation.actualDuration {
                            Text(CadenceFormat.duration(duration))
                                .font(Typo.caption)
                                .foregroundStyle(Ink.textTertiary)
                        }
                        Spacer(minLength: Space.md)
                        if let payment = paymentsByConsultation[consultation.id] {
                            Text("\(payment.money.formatted()) · \(settings.methodLabel(payment.methodID))")
                                .font(Typo.captionNumeric)
                                .foregroundStyle(Ink.textPrimary)
                        } else if consultation.status == .attended {
                            Text("non réglé")
                                .font(Typo.caption)
                                .foregroundStyle(Ink.warning)
                        }
                    }
                    .padding(.vertical, Space.sm)
                    if consultation.id != profile.consultations.prefix(24).last?.id { Hairline() }
                }
            }
            .cadenceCard(padding: Space.lg)

            if profile.consultations.count > 24 {
                Text("Les 24 derniers rendez-vous sont affichés. L'export CSV contient l'historique complet.")
                    .font(Typo.caption)
                    .foregroundStyle(Ink.textTertiary)
            }
        }
    }

    private var payments: some View {
        HStack(alignment: .top, spacing: Space.xl) {
            distribution(title: "Montants", slices: profile.amountDistribution)
            distribution(title: "Moyens de paiement", slices: profile.methodDistribution)
        }
    }

    private func distribution(title: String, slices: [DistributionSlice]) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(text: title)
            VStack(spacing: Space.sm) {
                ForEach(slices.prefix(4), id: \.key) { slice in
                    HStack(spacing: Space.md) {
                        Text(slice.label)
                            .font(Typo.caption)
                            .foregroundStyle(Ink.textPrimary)
                            .frame(width: 78, alignment: .leading)
                        ProgressBar(fraction: slice.share)
                        Text("\(Int((slice.share * 100).rounded())) %")
                            .font(Typo.captionNumeric)
                            .foregroundStyle(Ink.textSecondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceCard(padding: Space.lg)
    }

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(text: "Notes")
            Text(notes)
                .font(Typo.body)
                .foregroundStyle(Ink.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .cadenceCard(padding: Space.lg)
        }
    }
}

/// Shows how sure the habit engine is, without pretending to a precision it lacks.
@MainActor
struct ConfidenceBar: View {
    let confidence: Double

    var body: some View {
        HStack(spacing: Space.sm) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.surfaceSunken)
                    Capsule()
                        .fill(Ink.accent)
                        .frame(width: max(0, min(1, confidence)) * geometry.size.width)
                }
            }
            .frame(height: 4)
            Text(label)
                .font(Typo.caption)
                .foregroundStyle(Ink.textTertiary)
        }
        .accessibilityLabel("Habitude \(label)")
    }

    private var label: String {
        switch confidence {
        case 0.85...: return "très régulier"
        case 0.7..<0.85: return "régulier"
        default: return "assez régulier"
        }
    }
}
