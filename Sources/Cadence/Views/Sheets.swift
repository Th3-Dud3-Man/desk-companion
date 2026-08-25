import SwiftUI
import CadenceCore

/// Shared chrome for every sheet: same header, same footer, same keys.
/// ⏎ confirms, ⎋ cancels — everywhere, without exception.
@MainActor
struct SheetChrome<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var confirmTitle: String = "Enregistrer"
    var isConfirmEnabled: Bool = true
    var destructiveTitle: String? = nil
    var onDestructive: (() -> Void)? = nil
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typo.title)
                    .foregroundStyle(Ink.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Typo.caption)
                        .foregroundStyle(Ink.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.xxl)
            .padding(.top, Space.xxl)
            .padding(.bottom, Space.lg)

            Hairline()

            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    content()
                }
                .padding(Space.xxl)
            }
            .scrollContentBackground(.hidden)
            .frame(maxHeight: 460)

            Hairline()

            HStack(spacing: Space.md) {
                if let destructiveTitle, let onDestructive {
                    Button(destructiveTitle, action: onDestructive)
                        .buttonStyle(.cadenceDestructive)
                }
                Spacer()
                Button("Annuler", action: onCancel)
                    .buttonStyle(.cadenceSecondary)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: onConfirm)
                    .buttonStyle(.cadencePrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isConfirmEnabled)
            }
            .padding(Space.xxl)
        }
        .frame(width: 520)
        .background(Ink.surface)
    }
}

/// A labelled row inside a sheet. Keeps every form aligned identically.
@MainActor
struct FormRow<Content: View>: View {
    let label: String
    var hint: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(label)
                .font(Typo.captionStrong)
                .foregroundStyle(Ink.textSecondary)
            content()
            if let hint {
                Text(hint)
                    .font(Typo.caption)
                    .foregroundStyle(Ink.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Consultation editor

@MainActor
struct ConsultationEditor: View {
    enum Mode {
        case create(suggestedStart: Date)
        case edit(Consultation)
    }

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var patientID: UUID?
    @State private var manualTitle = ""
    @State private var start = Date()
    @State private var durationMinutes = 50
    @State private var location = ""
    @State private var notes = ""
    @State private var didLoad = false

    var body: some View {
        SheetChrome(
            title: isEditing ? "Modifier le rendez-vous" : "Nouveau rendez-vous",
            subtitle: CadenceFormat.dayFull(start).capitalizedFirst,
            confirmTitle: isEditing ? "Enregistrer" : "Créer",
            isConfirmEnabled: isValid,
            onCancel: { dismiss() },
            onConfirm: save
        ) {
            FormRow(label: "Patient") {
                PatientPicker(selection: $patientID, allowsNone: true)
            }

            if patientID == nil {
                FormRow(label: "Intitulé", hint: "Utilisé lorsque le rendez-vous n'est pas rattaché à un patient.") {
                    CadenceTextField(placeholder: "Par exemple : premier contact", text: $manualTitle)
                }
            }

            HStack(alignment: .top, spacing: Space.lg) {
                FormRow(label: "Début") {
                    DatePicker("", selection: $start, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.field)
                        .labelsHidden()
                }
                FormRow(label: "Durée") {
                    Picker("", selection: $durationMinutes) {
                        ForEach([30, 45, 50, 60, 75, 90, 120], id: \.self) { minutes in
                            Text(CadenceFormat.duration(Double(minutes) * 60)).tag(minutes)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
            }

            FormRow(label: "Lieu") {
                CadenceTextField(placeholder: "Cabinet, visioconférence…", text: $location, symbol: "mappin")
            }

            FormRow(label: "Notes", hint: "Notes pratiques uniquement — Cadence n'est pas un dossier clinique.") {
                CadenceTextField(placeholder: "", text: $notes, isMultiline: true)
            }
        }
        .onAppear(perform: load)
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var isValid: Bool {
        patientID != nil || !manualTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        switch mode {
        case .create(let suggested):
            start = suggested
            durationMinutes = model.settings.defaultDurationMinutes
        case .edit(let consultation):
            patientID = consultation.patientID
            manualTitle = consultation.patientID == nil ? consultation.title : ""
            start = consultation.scheduledStart
            durationMinutes = max(5, Int(consultation.scheduledDuration / 60))
            location = consultation.location ?? ""
            notes = consultation.notes ?? ""
        }
    }

    private func save() {
        let end = start.addingTimeInterval(Double(durationMinutes) * 60)
        let title = model.patient(id: patientID)?.displayName
            ?? manualTitle.trimmingCharacters(in: .whitespaces)

        switch mode {
        case .create:
            model.createConsultation(
                patientID: patientID, title: title, start: start, end: end,
                location: location.isEmpty ? nil : location
            )
        case .edit(let original):
            var updated = original
            updated.patientID = patientID
            updated.title = title
            updated.scheduledStart = start
            updated.scheduledEnd = end
            updated.location = location.isEmpty ? nil : location
            updated.notes = notes.isEmpty ? nil : notes
            model.updateConsultation(updated, original: original)
        }
        dismiss()
    }
}

// MARK: - Patient picker

@MainActor
struct PatientPicker: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selection: UUID?
    var allowsNone = false

    var body: some View {
        Menu {
            if allowsNone {
                Button("Aucun patient") { selection = nil }
                Divider()
            }
            ForEach(model.patients) { patient in
                Button(patient.displayName) { selection = patient.id }
            }
            if model.patients.isEmpty {
                Text("Aucun patient enregistré")
            }
        } label: {
            HStack(spacing: Space.md) {
                if let patient = selectedPatient {
                    PatientAvatar(patient: patient, size: 20)
                    Text(patient.displayName).font(Typo.body)
                } else {
                    Image(systemName: "person.crop.circle.dashed")
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.textTertiary)
                    Text("Choisir un patient").font(Typo.body).foregroundStyle(Ink.textTertiary)
                }
                Spacer(minLength: Space.sm)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Ink.textTertiary)
            }
            .padding(.horizontal, Space.md)
            .frame(height: Metrics.controlHeight)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Ink.surfaceSunken))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(Ink.hairlineStrong, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel("Patient : \(selectedPatient?.displayName ?? "aucun")")
    }

    private var selectedPatient: Patient? {
        model.patient(id: selection)
    }
}

// MARK: - Patient editor

@MainActor
struct PatientEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let patient: Patient?

    @State private var displayName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var notes = ""
    @State private var usesCustomTariff = false
    @State private var amountText = ""
    @State private var methodID = PaymentMethod.card.id
    @State private var didLoad = false

    var body: some View {
        SheetChrome(
            title: patient == nil ? "Nouveau patient" : "Modifier le patient",
            confirmTitle: patient == nil ? "Créer" : "Enregistrer",
            isConfirmEnabled: !displayName.trimmingCharacters(in: .whitespaces).isEmpty,
            onCancel: { dismiss() },
            onConfirm: save
        ) {
            FormRow(label: "Nom") {
                CadenceTextField(placeholder: "Prénom Nom", text: $displayName, symbol: "person")
            }

            HStack(alignment: .top, spacing: Space.lg) {
                FormRow(label: "E-mail") {
                    CadenceTextField(placeholder: "", text: $email, symbol: "envelope")
                }
                FormRow(label: "Téléphone") {
                    CadenceTextField(placeholder: "", text: $phone, symbol: "phone")
                }
            }

            FormRow(
                label: "Tarif de départ",
                hint: "Utilisé tant que ce patient n'a pas d'historique. Ensuite, Cadence propose ce qu'il paie réellement."
            ) {
                VStack(alignment: .leading, spacing: Space.md) {
                    Toggle("Définir un tarif pour ce patient", isOn: $usesCustomTariff)
                        .toggleStyle(.checkbox)
                        .font(Typo.body)
                    if usesCustomTariff {
                        HStack(spacing: Space.md) {
                            AmountField(text: $amountText)
                                .frame(width: 120)
                            MethodPicker(selection: $methodID, methods: model.settings.activeMethods)
                        }
                    }
                }
            }

            FormRow(label: "Notes", hint: "Informations pratiques. Cadence n'est pas un dossier médical.") {
                CadenceTextField(placeholder: "", text: $notes, isMultiline: true)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let patient else {
            amountText = Money(cents: model.settings.defaultAmountCents).csvValue
            methodID = model.settings.defaultMethodID
            return
        }
        displayName = patient.displayName
        email = patient.email ?? ""
        phone = patient.phone ?? ""
        notes = patient.notes ?? ""
        usesCustomTariff = patient.defaultAmountCents != nil
        amountText = Money(cents: patient.defaultAmountCents ?? model.settings.defaultAmountCents).csvValue
        methodID = patient.defaultMethodID ?? model.settings.defaultMethodID
    }

    private func save() {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        let parts = name.split(separator: " ").map(String.init)
        let cents = AmountField.parse(amountText)

        if var existing = patient {
            existing.displayName = name
            existing.firstName = parts.first
            existing.lastName = parts.count > 1 ? parts.dropFirst().joined(separator: " ") : nil
            existing.email = email.isEmpty ? nil : email
            existing.phone = phone.isEmpty ? nil : phone
            existing.notes = notes.isEmpty ? nil : notes
            existing.defaultAmountCents = usesCustomTariff ? cents : nil
            existing.defaultMethodID = usesCustomTariff ? methodID : nil
            model.updatePatient(existing)
        } else {
            if let created = model.createPatient(named: name) {
                var updated = created
                updated.firstName = parts.first
                updated.lastName = parts.count > 1 ? parts.dropFirst().joined(separator: " ") : nil
                updated.email = email.isEmpty ? nil : email
                updated.phone = phone.isEmpty ? nil : phone
                updated.notes = notes.isEmpty ? nil : notes
                updated.defaultAmountCents = usesCustomTariff ? cents : nil
                updated.defaultMethodID = usesCustomTariff ? methodID : nil
                model.updatePatient(updated)
                model.selectPatient(updated.id)
            }
        }
        dismiss()
    }
}

// MARK: - Payment editor

@MainActor
struct PaymentEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let payment: Payment
    let patientName: String

    @State private var amountText = ""
    @State private var methodID = PaymentMethod.card.id
    @State private var paidAt = Date()
    @State private var note = ""
    @State private var didLoad = false

    /// The same sheet both edits a recorded payment and captures a new one, so it
    /// asks the store which case it is in rather than being told.
    private var existingPayment: Payment? { (try? model.store.payment(id: payment.id)) ?? nil }
    private var isExisting: Bool { existingPayment != nil }

    var body: some View {
        SheetChrome(
            title: isExisting ? "Modifier le paiement" : "Enregistrer un paiement",
            subtitle: patientName,
            confirmTitle: isExisting ? "Enregistrer" : "Ajouter",
            isConfirmEnabled: AmountField.parse(amountText) > 0,
            destructiveTitle: isExisting ? "Supprimer" : nil,
            onDestructive: isExisting ? {
                model.deletePayment(payment, patientName: patientName)
                dismiss()
            } : nil,
            onCancel: { dismiss() },
            onConfirm: save
        ) {
            HStack(alignment: .top, spacing: Space.lg) {
                FormRow(label: "Montant") {
                    AmountField(text: $amountText)
                }
                FormRow(label: "Moyen de paiement") {
                    MethodPicker(selection: $methodID, methods: model.settings.activeMethods)
                }
            }

            FormRow(label: "Date et heure") {
                DatePicker("", selection: $paidAt, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.field)
                    .labelsHidden()
            }

            FormRow(label: "Note") {
                CadenceTextField(placeholder: "Facultatif", text: $note)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        amountText = Money(cents: payment.amountCents).csvValue
        methodID = payment.methodID
        paidAt = payment.paidAt
        note = payment.note ?? ""
    }

    private func save() {
        var updated = payment
        updated.amountCents = AmountField.parse(amountText)
        updated.methodID = methodID
        updated.paidAt = paidAt
        updated.note = note.isEmpty ? nil : note
        updated.currencyCode = model.settings.currencyCode

        if let original = existingPayment {
            model.updatePayment(updated, original: original)
        } else {
            model.recordExistingPayment(updated, patientName: patientName)
        }
        dismiss()
    }
}

/// Amount entry that accepts what people actually type: `70`, `70,50`, `70.5`.
@MainActor
struct AmountField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: Space.sm) {
            TextField("0", text: $text)
                .textFieldStyle(.plain)
                .font(Typo.headingNumeric)
                .multilineTextAlignment(.trailing)
            Text("€")
                .font(Typo.body)
                .foregroundStyle(Ink.textSecondary)
        }
        .padding(.horizontal, Space.md)
        .frame(height: Metrics.controlHeight)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Ink.surfaceSunken))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(Ink.hairlineStrong, lineWidth: 1)
        )
        .accessibilityLabel("Montant en euros")
    }

    static func parse(_ text: String) -> Int {
        let cleaned = text
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned) else { return 0 }
        return Int((value * 100).rounded())
    }
}

@MainActor
struct MethodPicker: View {
    @Binding var selection: String
    let methods: [PaymentMethod]

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(methods) { method in
                Label(method.label, systemImage: method.symbol).tag(method.id)
            }
        }
        .labelsHidden()
        .accessibilityLabel("Moyen de paiement")
    }
}

// MARK: - Shortcuts

@MainActor
struct ShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss

    struct Shortcut: Identifiable {
        let keys: String
        let action: String
        var id: String { keys + action }
    }

    struct ShortcutGroup: Identifiable {
        let id: String
        let shortcuts: [Shortcut]
    }

    private let groups: [ShortcutGroup] = [
        ShortcutGroup(id: "Navigation", shortcuts: [
            Shortcut(keys: "⌘1 … ⌘5", action: "Aller à une section"),
            Shortcut(keys: "⌘T", action: "Revenir à aujourd'hui"),
            Shortcut(keys: "⌥⌘← / ⌥⌘→", action: "Jour précédent / suivant"),
            Shortcut(keys: "⌘K", action: "Recherche et actions"),
        ]),
        ShortcutGroup(id: "Journée", shortcuts: [
            Shortcut(keys: "↑ / ↓", action: "Se déplacer dans la journée"),
            Shortcut(keys: "P", action: "Marquer présent"),
            Shortcut(keys: "A", action: "Marquer absent"),
            Shortcut(keys: "⏎", action: "Valider le paiement proposé"),
            Shortcut(keys: "⎋", action: "Désélectionner"),
        ]),
        ShortcutGroup(id: "Général", shortcuts: [
            Shortcut(keys: "⌘N", action: "Nouveau rendez-vous"),
            Shortcut(keys: "⇧⌘N", action: "Nouveau patient"),
            Shortcut(keys: "⌘R", action: "Synchroniser l'agenda"),
            Shortcut(keys: "⌘Z / ⇧⌘Z", action: "Annuler / rétablir"),
            Shortcut(keys: "⌘,", action: "Réglages"),
        ]),
    ]

    var body: some View {
        SheetChrome(
            title: "Raccourcis clavier",
            subtitle: "Toute la journée peut se piloter au clavier.",
            confirmTitle: "Fermer",
            onCancel: { dismiss() },
            onConfirm: { dismiss() }
        ) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: Space.md) {
                    SectionLabel(text: group.id)
                    VStack(spacing: Space.sm) {
                        ForEach(group.shortcuts) { shortcut in
                            HStack(spacing: Space.lg) {
                                Text(shortcut.keys)
                                    .font(Typo.captionStrong)
                                    .foregroundStyle(Ink.textPrimary)
                                    .frame(width: 110, alignment: .leading)
                                Text(shortcut.action)
                                    .font(Typo.caption)
                                    .foregroundStyle(Ink.textSecondary)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
        }
    }
}
