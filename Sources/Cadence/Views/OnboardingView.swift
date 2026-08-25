import SwiftUI
import CadenceCore

/// Three steps, all skippable. The point is to reach a working day as fast as
/// possible, not to collect information Cadence can work out on its own.
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var practiceName = ""
    @State private var amountText = "60"
    @State private var methodID = PaymentMethod.card.id
    @State private var wantsDemoData = false
    @State private var accessRequested = false

    private let stepTitles = ["Votre cabinet", "Votre agenda", "Prêt"]

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Hairline()

            Group {
                switch step {
                case 0: practiceStep
                case 1: calendarStep
                default: readyStep
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.xxl)
            .frame(height: 320)

            Hairline()
            footerBar
        }
        .frame(width: 560)
        .background(Ink.surface)
        .onAppear { practiceName = model.settings.practiceName }
    }

    private var headerBar: some View {
        HStack(spacing: Space.lg) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Ink.accent)
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Ink.textOnAccent)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text("Bienvenue dans Cadence")
                    .font(Typo.title)
                Text(stepTitles[min(step, stepTitles.count - 1)])
                    .font(Typo.caption)
                    .foregroundStyle(Ink.textSecondary)
            }
            Spacer()
            HStack(spacing: Space.sm) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Ink.accent : Ink.hairlineStrong)
                        .frame(width: index == step ? 18 : 6, height: 6)
                        .animation(Motion.quick, value: step)
                }
            }
        }
        .padding(Space.xxl)
    }

    private var practiceStep: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Text("Deux réglages, et vous pourrez commencer. Tout est modifiable ensuite.")
                .font(Typo.body)
                .foregroundStyle(Ink.textSecondary)

            FormRow(label: "Nom du cabinet", hint: "Apparaît en tête de vos rapports.") {
                CadenceTextField(placeholder: "Mon cabinet", text: $practiceName, symbol: "building.2")
            }

            HStack(alignment: .top, spacing: Space.xl) {
                FormRow(label: "Tarif habituel",
                        hint: "Une valeur de départ : Cadence apprendra ensuite ce que chaque patient paie réellement.") {
                    AmountField(text: $amountText).frame(width: 130)
                }
                FormRow(label: "Moyen le plus fréquent") {
                    MethodPicker(selection: $methodID, methods: model.settings.activeMethods)
                        .frame(width: 170)
                }
            }
        }
    }

    private var calendarStep: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Text("Cadence peut lire vos rendez-vous depuis les calendriers déjà présents sur ce Mac — iCloud, Google ou tout autre compte ajouté dans les Réglages Système. Elle n'y écrit jamais, et rien n'est envoyé sur Internet.")
                .font(Typo.body)
                .foregroundStyle(Ink.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            let sync = model.calendarSync
            HStack(spacing: Space.lg) {
                Image(systemName: sync.access.canRead ? "checkmark.circle.fill" : "calendar.badge.plus")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(sync.access.canRead ? Ink.accent : Ink.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sync.access.canRead ? "Accès accordé" : "Connecter mon agenda")
                        .font(Typo.bodyStrong)
                    Text(sync.access.canRead
                         ? "Choisissez les calendriers à suivre à l'étape suivante, dans les Réglages."
                         : "macOS vous demandera votre autorisation.")
                        .font(Typo.caption)
                        .foregroundStyle(Ink.textSecondary)
                }
                Spacer()
                if !sync.access.canRead {
                    Button(accessRequested ? "Ouvrir les réglages" : "Autoriser") {
                        if accessRequested {
                            sync.openSystemPrivacySettings()
                        } else {
                            accessRequested = true
                            Task { await sync.requestAccess() }
                        }
                    }
                    .buttonStyle(.cadencePrimary)
                }
            }
            .cadenceCard(padding: Space.lg)

            Text("Vous pouvez aussi vous en passer : les rendez-vous se créent en un clic avec ⌘N.")
                .font(Typo.caption)
                .foregroundStyle(Ink.textTertiary)
        }
    }

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Text("Votre journée s'ouvrira sur l'écran « Aujourd'hui ». Marquez une présence d'un clic, validez le paiement proposé, et tout est enregistré.")
                .font(Typo.body)
                .foregroundStyle(Ink.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $wantsDemoData) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Installer des données de démonstration")
                        .font(Typo.bodyStrong)
                    Text("Huit patients fictifs avec plusieurs mois d'historique, pour essayer. Elles sont marquées séparément et se retirent d'un clic.")
                        .font(Typo.caption)
                        .foregroundStyle(Ink.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: Space.sm) {
                SectionLabel(text: "À retenir")
                shortcutLine("⌘K", "Retrouver un patient ou lancer une action")
                shortcutLine("P / A", "Marquer présent ou absent, au clavier")
                shortcutLine("⏎", "Valider le paiement proposé")
                shortcutLine("⌘Z", "Annuler — il n'y a jamais de fenêtre de confirmation")
            }
        }
    }

    private func shortcutLine(_ keys: String, _ text: String) -> some View {
        HStack(spacing: Space.md) {
            Text(keys)
                .font(Typo.captionStrong)
                .foregroundStyle(Ink.textPrimary)
                .frame(width: 52, alignment: .leading)
            Text(text)
                .font(Typo.caption)
                .foregroundStyle(Ink.textSecondary)
        }
    }

    private var footerBar: some View {
        HStack(spacing: Space.md) {
            Button("Passer") { finish() }
                .buttonStyle(.cadenceGhost)
            Spacer()
            if step > 0 {
                Button("Retour") { step -= 1 }
                    .buttonStyle(.cadenceSecondary)
            }
            Button(step == 2 ? "Commencer" : "Continuer") {
                if step == 2 { finish() } else { step += 1 }
            }
            .buttonStyle(.cadencePrimary)
            .keyboardShortcut(.defaultAction)
        }
        .padding(Space.xxl)
    }

    private func finish() {
        var settings = model.settings
        let trimmed = practiceName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { settings.practiceName = trimmed }
        let cents = AmountField.parse(amountText)
        if cents > 0 { settings.defaultAmountCents = cents }
        settings.defaultMethodID = methodID
        settings.hasCompletedOnboarding = true
        model.save(settings: settings)

        if wantsDemoData {
            try? DemoData.install(into: model.store)
            model.reload()
        }
        model.isOnboarding = false
        dismiss()
    }
}
