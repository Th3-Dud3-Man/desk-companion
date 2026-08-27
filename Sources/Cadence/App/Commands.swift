import SwiftUI
import CadenceCore

/// The menu bar. Every item here does something; there are no placeholders, and
/// every shortcut matches the one shown in the interface.
///
/// The `@MainActor` here produces one compiler warning, because SwiftUI declares
/// `Commands.body` without isolation while `View.body` has it. It is kept
/// deliberately: menus are built and invoked on the main thread, and this type
/// reads main-actor state, so the annotation describes reality. Dropping it to
/// silence the warning would mean either lying about the isolation or unpicking
/// it from the model, which would be worse than the warning.
@MainActor
struct CadenceCommands: Commands {
    @ObservedObject var bootstrap: AppBootstrap

    private var model: AppModel? { bootstrap.model }

    var body: some Commands {
        // Replace the stock "New" group with what this application can actually create.
        CommandGroup(replacing: .newItem) {
            Button("Nouveau rendez-vous…") { model?.requestNewConsultation(at: nil) }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(model == nil)

            Button("Nouveau patient…") { model?.requestNewPatient() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(model == nil)
        }

        CommandGroup(replacing: .undoRedo) {
            Button(model?.undoTitle ?? "Annuler") { model?.performUndo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(model?.canUndo != true)

            Button(model?.redoTitle ?? "Rétablir") { model?.performRedo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(model?.canRedo != true)
        }

        CommandGroup(after: .toolbar) {
            Button("Rechercher…") { model?.isCommandPaletteVisible = true }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(model == nil)

            Divider()

            ForEach(Destination.allCases) { destination in
                Button(destination.title) { model?.destination = destination }
                    .keyboardShortcut(destination.shortcut, modifiers: .command)
                    .disabled(model == nil)
            }

            Divider()

            Button("Aujourd'hui") { model?.goToToday() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(model == nil)

            Button("Jour précédent") { model?.shiftDay(by: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(model == nil)

            Button("Jour suivant") { model?.shiftDay(by: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(model == nil)
        }

        CommandMenu("Agenda") {
            Button("Synchroniser maintenant") {
                guard let model else { return }
                Task { await model.calendarSync.synchronise(trigger: .userAction) }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model == nil)

            Button("Gérer les calendriers…") {
                model?.destination = .settings
                model?.settingsSection = .calendars
            }
            .disabled(model == nil)
        }

        CommandGroup(replacing: .appSettings) {
            Button("Réglages…") { model?.destination = .settings }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(model == nil)
        }

        CommandGroup(after: .saveItem) {
            Button("Exporter les paiements du mois…") { model?.requestExport(.payments) }
                .disabled(model == nil)
            Button("Exporter les consultations du mois…") { model?.requestExport(.consultations) }
                .disabled(model == nil)
            Button("Exporter la liste des patients…") { model?.requestExport(.patients) }
                .disabled(model == nil)
            Divider()
            Button("Rapport d'activité en PDF…") { model?.requestReport() }
                .disabled(model == nil)
            Button("Synthèse de revenus (12 derniers mois)…") {
                guard let model else { return }
                let window = AppModel.IncomeWindow.trailingTwelveMonths
                model.requestIncomeReport(range: window.range(), label: window.label())
            }
            .disabled(model == nil)
        }

        CommandGroup(replacing: .help) {
            Button("Raccourcis clavier") { model?.present(.shortcuts) }
                .keyboardShortcut("/", modifiers: .command)
                .disabled(model == nil)
        }
    }
}
