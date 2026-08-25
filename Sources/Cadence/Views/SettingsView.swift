import SwiftUI
import AppKit
import CadenceCore

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: sectionBinding) {
                    ForEach(SettingsSection.allCases) { section in
                        Label(section.title, systemImage: section.symbol)
                            .font(Typo.body)
                            .tag(section)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            .frame(width: 208)

            Hairline().frame(width: 1).frame(maxHeight: .infinity)

            ScrollView {
                VStack(alignment: .leading, spacing: Space.huge) {
                    switch model.settingsSection {
                    case .practice: PracticeSettingsPane()
                    case .calendars: CalendarSettingsPane()
                    case .payments: PaymentSettingsPane()
                    case .data: DataSettingsPane()
                    }
                }
                .padding(Space.xxl)
                .frame(maxWidth: 720, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sectionBinding: Binding<SettingsSection?> {
        Binding(
            get: { model.settingsSection },
            set: { if let value = $0 { model.settingsSection = value } }
        )
    }
}

// MARK: - Practice

@MainActor
struct PracticeSettingsPane: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = PracticeSettings.default
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            SettingsHeader(title: "Cabinet", subtitle: "Les valeurs par défaut de votre pratique.")

            SettingsCard {
                FormRow(label: "Nom du cabinet", hint: "Apparaît en tête des rapports exportés.") {
                    CadenceTextField(placeholder: "Mon cabinet", text: $draft.practiceName)
                }

                FormRow(label: "Durée d'une séance") {
                    Picker("", selection: $draft.defaultDurationMinutes) {
                        ForEach([30, 45, 50, 60, 75, 90], id: \.self) { minutes in
                            Text(CadenceFormat.duration(Double(minutes) * 60)).tag(minutes)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }

            }

            SettingsCard {
                Toggle("Masquer le contenu quand Cadence passe en arrière-plan", isOn: $draft.privacyBlurWhenInactive)
                    .toggleStyle(.switch)
                    .font(Typo.body)
                Text("Utile lorsqu'un patient est dans le bureau et que vous changez d'application.")
                    .font(Typo.caption)
                    .foregroundStyle(Ink.textTertiary)
            }

            HStack {
                Spacer()
                Button("Enregistrer") { model.save(settings: draft) }
                    .buttonStyle(.cadencePrimary)
                    .disabled(draft == model.settings)
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            draft = model.settings
        }
    }
}

// MARK: - Calendars

@MainActor
struct CalendarSettingsPane: View {
    @EnvironmentObject private var model: AppModel

    private var sync: CalendarSyncService { model.calendarSync }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            SettingsHeader(
                title: "Agenda",
                subtitle: "Cadence lit vos calendriers, sans jamais y écrire."
            )

            SettingsCard {
                HStack(spacing: Space.lg) {
                    Image(systemName: sync.statusSymbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(sync.access.canRead ? Ink.accent : Ink.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sync.access.canRead ? "Accès accordé" : "Accès à configurer")
                            .font(Typo.bodyStrong)
                        Text(sync.access.explanation)
                            .font(Typo.caption)
                            .foregroundStyle(Ink.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Space.md)
                    if !sync.access.canRead {
                        if sync.access == .notDetermined {
                            Button("Autoriser") { Task { await sync.requestAccess() } }
                                .buttonStyle(.cadencePrimary)
                        } else {
                            Button("Ouvrir les réglages") { sync.openSystemPrivacySettings() }
                                .buttonStyle(.cadenceSecondary)
                        }
                    }
                }
            }

            if sync.access.canRead {
                VStack(alignment: .leading, spacing: Space.md) {
                    HStack {
                        SectionLabel(text: "Calendriers")
                        Spacer()
                        Button("Actualiser la liste") { sync.refreshAvailableCalendars() }
                            .buttonStyle(.cadence(.ghost, size: .small))
                        Button("Synchroniser") { Task { await sync.synchronise(trigger: .userAction) } }
                            .buttonStyle(.cadence(.secondary, size: .small))
                            .disabled(sync.isSyncing || !sync.hasEnabledCalendars)
                    }

                    if sync.subscriptions.isEmpty {
                        Text("Aucun calendrier trouvé sur ce Mac.")
                            .font(Typo.caption)
                            .foregroundStyle(Ink.textTertiary)
                            .cadenceCard(padding: Space.lg)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(grouped.keys.sorted()), id: \.self) { account in
                                VStack(alignment: .leading, spacing: 0) {
                                    HStack {
                                        Text(account)
                                            .font(Typo.captionStrong)
                                            .foregroundStyle(Ink.textSecondary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, Space.lg)
                                    .padding(.top, Space.md)
                                    .padding(.bottom, Space.sm)

                                    ForEach(grouped[account] ?? []) { subscription in
                                        CalendarRow(subscription: subscription)
                                        if subscription.id != grouped[account]?.last?.id {
                                            Hairline().padding(.leading, Space.lg)
                                        }
                                    }
                                }
                            }
                        }
                        .cadenceCard(padding: 0)
                    }

                    if let error = sync.lastError {
                        InlineError(message: error, retryTitle: "Réessayer") {
                            Task { await sync.synchronise(trigger: .userAction) }
                        }
                    }
                }
            }

            SettingsCard {
                VStack(alignment: .leading, spacing: Space.md) {
                    Text("Google Calendar")
                        .font(Typo.bodyStrong)
                    Text("Ajoutez votre compte Google dans Réglages Système › Comptes Internet, en activant « Calendriers ». Ses calendriers apparaîtront alors dans la liste ci-dessus, exactement comme ceux d'iCloud. Aucune donnée n'est envoyée à un service tiers par Cadence.")
                        .font(Typo.caption)
                        .foregroundStyle(Ink.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Ouvrir Comptes Internet") { sync.openInternetAccountsSettings() }
                        .buttonStyle(.cadence(.secondary, size: .small))
                }
            }
        }
    }

    private var grouped: [String: [CalendarSubscription]] {
        Dictionary(grouping: sync.subscriptions) { $0.accountName ?? "Ce Mac" }
    }
}

@MainActor
private struct CalendarRow: View {
    @EnvironmentObject private var model: AppModel
    let subscription: CalendarSubscription

    var body: some View {
        HStack(spacing: Space.lg) {
            Toggle("", isOn: Binding(
                get: { subscription.isEnabled },
                set: { model.calendarSync.setEnabled($0, for: subscription.id) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(colour)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 1) {
                Text(subscription.title)
                    .font(Typo.body)
                    .foregroundStyle(Ink.textPrimary)
                if subscription.isEnabled {
                    Text(statusText)
                        .font(Typo.caption)
                        .foregroundStyle(subscription.lastStatus == .failed ? Ink.danger : Ink.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
    }

    private var colour: Color {
        guard let hex = subscription.colourHex, let value = UInt32(hex, radix: 16) else { return Ink.textTertiary }
        return Color(nsColor: NSColor(cadenceHex: value))
    }

    private var statusText: String {
        if let date = subscription.lastSyncAt {
            let detail = subscription.lastMessage.map { " · \($0)" } ?? ""
            return "\(subscription.lastStatus.label) \(CadenceFormat.since(date))\(detail)"
        }
        return subscription.lastStatus.label
    }
}

// MARK: - Payments

@MainActor
struct PaymentSettingsPane: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = PracticeSettings.default
    @State private var amountText = ""
    @State private var newMethodLabel = ""
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            SettingsHeader(
                title: "Tarifs et paiements",
                subtitle: "Le tarif par défaut ne sert qu'aux nouveaux patients : ensuite, Cadence propose ce que chacun paie réellement."
            )

            SettingsCard {
                HStack(alignment: .top, spacing: Space.xl) {
                    FormRow(label: "Tarif par défaut") {
                        AmountField(text: $amountText).frame(width: 130)
                    }
                    FormRow(label: "Moyen par défaut") {
                        MethodPicker(selection: $draft.defaultMethodID, methods: draft.activeMethods)
                            .frame(width: 170)
                    }
                    Spacer()
                }
            }

            VStack(alignment: .leading, spacing: Space.md) {
                SectionLabel(text: "Moyens de paiement")
                Text("Renommez, désactivez ou ajoutez ce que vous acceptez. Les paiements déjà enregistrés conservent leur moyen d'origine.")
                    .font(Typo.caption)
                    .foregroundStyle(Ink.textSecondary)

                VStack(spacing: 0) {
                    ForEach($draft.paymentMethods) { $method in
                        HStack(spacing: Space.lg) {
                            Toggle("", isOn: $method.isEnabled)
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                            Image(systemName: method.symbol)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Ink.textSecondary)
                                .frame(width: 18)
                            TextField("Nom", text: $method.label)
                                .textFieldStyle(.plain)
                                .font(Typo.body)
                            Spacer(minLength: Space.md)
                            if draft.paymentMethods.count > 1 {
                                Button {
                                    draft.paymentMethods.removeAll { $0.id == method.id }
                                } label: {
                                    Image(systemName: "minus.circle").font(.system(size: 11))
                                }
                                .buttonStyle(.cadence(.ghost, size: .small))
                                .help("Retirer ce moyen de paiement")
                            }
                        }
                        .padding(.horizontal, Space.lg)
                        .padding(.vertical, Space.md)
                        if method.id != draft.paymentMethods.last?.id { Hairline().padding(.leading, Space.lg) }
                    }
                }
                .cadenceCard(padding: 0)

                HStack(spacing: Space.md) {
                    CadenceTextField(placeholder: "Ajouter un moyen de paiement", text: $newMethodLabel, symbol: "plus")
                    Button("Ajouter") { addMethod() }
                        .buttonStyle(.cadenceSecondary)
                        .disabled(newMethodLabel.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            HStack {
                Spacer()
                Button("Enregistrer") { save() }
                    .buttonStyle(.cadencePrimary)
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            draft = model.settings
            amountText = Money(cents: draft.defaultAmountCents).csvValue
        }
    }

    private func addMethod() {
        let label = newMethodLabel.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return }
        let identifier = TextNormaliser.normalise(label).replacingOccurrences(of: " ", with: "-")
        guard !draft.paymentMethods.contains(where: { $0.id == identifier }) else { return }
        draft.paymentMethods.append(PaymentMethod(id: identifier, label: label, symbol: "creditcard"))
        newMethodLabel = ""
    }

    private func save() {
        var updated = draft
        updated.defaultAmountCents = AmountField.parse(amountText)
        if !updated.activeMethods.contains(where: { $0.id == updated.defaultMethodID }) {
            updated.defaultMethodID = updated.activeMethods.first?.id ?? PaymentMethod.card.id
        }
        model.save(settings: updated)
        draft = updated
    }
}

// MARK: - Data

@MainActor
struct DataSettingsPane: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var bootstrap: AppBootstrap

    @State private var snapshots: [BackupFile] = []
    @State private var demoInstalled = false
    @State private var confirmsDemoRemoval = false
    @State private var restoreTarget: BackupFile?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            SettingsHeader(
                title: "Données et sauvegardes",
                subtitle: "Tout est stocké sur ce Mac. Aucune donnée patient n'est envoyée sur Internet."
            )

            SettingsCard {
                VStack(alignment: .leading, spacing: Space.md) {
                    Text("Emplacement du dossier")
                        .font(Typo.bodyStrong)
                    Text(CadenceStore.defaultFileURL().path)
                        .font(Typo.caption)
                        .foregroundStyle(Ink.textSecondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    HStack(spacing: Space.md) {
                        Button("Révéler dans le Finder") { bootstrap.revealDataFolder() }
                            .buttonStyle(.cadence(.secondary, size: .small))
                        Button("Créer une sauvegarde maintenant") { createSnapshot() }
                            .buttonStyle(.cadence(.secondary, size: .small))
                    }
                }
            }

            VStack(alignment: .leading, spacing: Space.md) {
                HStack {
                    SectionLabel(text: "Sauvegardes locales")
                    Spacer()
                    Text("une par jour · les \(BackupManager.retention) dernières sont conservées")
                        .font(Typo.caption)
                        .foregroundStyle(Ink.textTertiary)
                }
                if snapshots.isEmpty {
                    Text("Aucune sauvegarde pour l'instant. La première sera créée automatiquement au prochain lancement.")
                        .font(Typo.caption)
                        .foregroundStyle(Ink.textTertiary)
                        .cadenceCard(padding: Space.lg)
                } else {
                    VStack(spacing: 0) {
                        ForEach(snapshots) { snapshot in
                            HStack(spacing: Space.lg) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Ink.textTertiary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(CadenceFormat.numericDateTime(snapshot.createdAt))
                                        .font(Typo.bodyNumeric)
                                    Text(snapshot.sizeDescription)
                                        .font(Typo.caption)
                                        .foregroundStyle(Ink.textTertiary)
                                }
                                Spacer(minLength: Space.md)
                                Button("Restaurer…") { restoreTarget = snapshot }
                                    .buttonStyle(.cadence(.secondary, size: .small))
                            }
                            .padding(.horizontal, Space.lg)
                            .padding(.vertical, Space.md)
                            if snapshot.id != snapshots.last?.id { Hairline().padding(.leading, Space.lg) }
                        }
                    }
                    .cadenceCard(padding: 0)
                }
            }

            SettingsCard {
                VStack(alignment: .leading, spacing: Space.md) {
                    Text("Données de démonstration")
                        .font(Typo.bodyStrong)
                    Text("Huit patients fictifs avec plusieurs mois d'historique, pour essayer Cadence sans saisir quoi que ce soit. Elles sont marquées séparément et se retirent d'un clic, sans toucher à vos données réelles.")
                        .font(Typo.caption)
                        .foregroundStyle(Ink.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Space.md) {
                        if demoInstalled {
                            Button("Supprimer les données de démonstration") { confirmsDemoRemoval = true }
                                .buttonStyle(.cadenceDestructive)
                        } else {
                            Button("Installer les données de démonstration") { installDemo() }
                                .buttonStyle(.cadenceSecondary)
                        }
                    }
                }
            }
        }
        .onAppear(perform: refresh)
        .alert("Supprimer les données de démonstration ?", isPresented: $confirmsDemoRemoval) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) { removeDemo() }
        } message: {
            let inventory = (try? DemoData.inventory(in: model.store)) ?? (patients: 0, consultations: 0, payments: 0)
            Text("\(inventory.patients) patients, \(inventory.consultations) rendez-vous et \(inventory.payments) paiements de démonstration seront supprimés. Vos données réelles ne sont pas concernées.")
        }
        .alert(
            "Restaurer cette sauvegarde ?",
            isPresented: Binding(get: { restoreTarget != nil }, set: { if !$0 { restoreTarget = nil } })
        ) {
            Button("Annuler", role: .cancel) { restoreTarget = nil }
            Button("Restaurer", role: .destructive) { restore() }
        } message: {
            Text("Les données actuelles seront remplacées par celles du \(restoreTarget.map { CadenceFormat.numericDateTime($0.createdAt) } ?? ""). Une copie de sécurité de l'état actuel est conservée dans le dossier de données.")
        }
    }

    private func refresh() {
        snapshots = (try? model.backups.snapshots()) ?? []
        demoInstalled = (try? DemoData.isInstalled(in: model.store)) ?? false
    }

    private func createSnapshot() {
        do {
            _ = try model.backups.createSnapshot()
            refresh()
            model.showToast("Sauvegarde créée", undoLabel: nil)
        } catch {
            model.report(error)
        }
    }

    private func installDemo() {
        do {
            try DemoData.install(into: model.store)
            model.reload()
            refresh()
            model.showToast("Données de démonstration installées", undoLabel: nil)
        } catch {
            model.report(error)
        }
    }

    private func removeDemo() {
        do {
            try DemoData.remove(from: model.store)
            model.reload()
            refresh()
            model.showToast("Données de démonstration supprimées", undoLabel: nil)
        } catch {
            model.report(error)
        }
    }

    private func restore() {
        guard let target = restoreTarget else { return }
        restoreTarget = nil
        do {
            try bootstrap.restore(from: target.url)
        } catch {
            model.report(error)
        }
    }
}

// MARK: - Shared pieces

@MainActor
struct SettingsHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title)
                .font(Typo.display)
                .foregroundStyle(Ink.textPrimary)
            Text(subtitle)
                .font(Typo.body)
                .foregroundStyle(Ink.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

@MainActor
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceCard(padding: Space.xl)
    }
}
