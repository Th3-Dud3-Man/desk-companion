import SwiftUI
import Combine
import CadenceCore

/// The five places the application can be. Deliberately few.
enum Destination: String, CaseIterable, Identifiable, Hashable {
    case today, agenda, patients, finances, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Aujourd'hui"
        case .agenda: return "Agenda"
        case .patients: return "Patients"
        case .finances: return "Finances"
        case .settings: return "Réglages"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "sun.horizon"
        case .agenda: return "calendar"
        case .patients: return "person.2"
        case .finances: return "chart.bar"
        case .settings: return "gearshape"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .today: return "1"
        case .agenda: return "2"
        case .patients: return "3"
        case .finances: return "4"
        case .settings: return "5"
        }
    }
}

/// One line of the day rail, with everything needed to draw it already resolved.
struct DayItem: Identifiable, Equatable {
    let consultation: Consultation
    let patient: Patient?
    let payment: Payment?
    let advice: PaymentAdvice

    var id: UUID { consultation.id }
    var title: String { patient?.displayName ?? consultation.title }
    var needsAttention: Bool { !consultation.status.isResolved }
    var awaitsPayment: Bool { consultation.status == .attended && payment == nil }

    static func == (lhs: DayItem, rhs: DayItem) -> Bool {
        lhs.consultation == rhs.consultation
            && lhs.patient == rhs.patient
            && lhs.payment == rhs.payment
            && lhs.advice.primary == rhs.advice.primary
            && lhs.advice.basis == rhs.advice.basis
    }
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var undoLabel: String?
}

/// The single source of view state.
///
/// Every mutation goes to the database first and the published properties are
/// rebuilt from it afterwards, so what is on screen is always what is on disk —
/// there is no in-memory model that can drift out of step with the file.
@MainActor
final class AppModel: ObservableObject {

    // MARK: Published state

    @Published var destination: Destination = .today
    @Published private(set) var settings: PracticeSettings
    @Published private(set) var patients: [Patient] = []

    @Published private(set) var selectedDay: Date
    @Published private(set) var dayItems: [DayItem] = []
    @Published private(set) var dayStatistics: PeriodStatistics
    @Published private(set) var unassignedToday: [DayItem] = []

    @Published var selectedPatientID: UUID?
    @Published private(set) var selectedProfile: PatientProfile?

    @Published var toast: ToastMessage?
    @Published var failure: String?
    @Published var isCommandPaletteVisible = false
    @Published var activeSheet: AppSheet?
    @Published var settingsSection: SettingsSection = .practice
    /// Set once at launch when the practice has never been set up.
    @Published var isOnboarding = false

    /// Ticks so the "now" line and countdowns stay honest without polling the store.
    @Published private(set) var now: Date = Date()

    @Published private(set) var undoRevision = 0

    // MARK: Collaborators

    let store: CadenceStore
    let undoStack = UndoStack()
    let backups: BackupManager
    let calendarSync: CalendarSyncService

    private var clockTimer: AnyCancellable?
    private var toastDismissal: Task<Void, Never>?

    // MARK: Lifecycle

    init(store: CadenceStore) {
        self.store = store
        self.settings = (try? store.settings()) ?? .default
        self.selectedDay = Calendar.cadence.startOfDay(for: Date())
        self.dayStatistics = .empty(range: .day(containing: Date()))
        self.backups = BackupManager(store: store)
        self.calendarSync = CalendarSyncService(store: store)

        reload()

        // A snapshot on the first launch of the day, quietly, in the background.
        Task.detached(priority: .background) { [backups] in
            try? backups.createDailySnapshotIfNeeded()
        }

        clockTimer = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                guard let self else { return }
                self.now = date
                // Crossing midnight while the app is open should move the day on.
                if !Calendar.cadence.isDate(self.selectedDay, inSameDayAs: date),
                   Calendar.cadence.isDateInToday(self.selectedDay) == false,
                   self.isShowingToday == false {
                    return
                }
            }

        calendarSync.onChange = { [weak self] in
            Task { @MainActor in self?.reload() }
        }
    }

    var isShowingToday: Bool { Calendar.cadence.isDateInToday(selectedDay) }

    // MARK: - Reloading

    /// Rebuilds every published property from the database. Cheap enough (a handful
    /// of indexed queries against a local file) to be the only refresh mechanism.
    func reload() {
        do {
            settings = try store.settings()
            patients = try store.allPatients()

            let range = DateRange.day(containing: selectedDay)
            let consultations = try store.consultations(in: range)
            let paymentsByConsultation = try store.paymentsByConsultation(in: range)
            let patientsByID = try store.patients(ids: Array(Set(consultations.compactMap(\.patientID))))

            // The advice for a patient is the same for every row they appear in, so
            // their payment history is fetched once per patient, not once per row.
            var adviceCache: [UUID: PaymentAdvice] = [:]
            var items: [DayItem] = []
            for consultation in consultations {
                let patient = consultation.patientID.flatMap { patientsByID[$0] }
                let advice: PaymentAdvice
                if let patient {
                    if let cached = adviceCache[patient.id] {
                        advice = cached
                    } else {
                        advice = HabitEngine.advise(
                            payments: try store.payments(forPatient: patient.id),
                            patient: patient, settings: settings, now: Date()
                        )
                        adviceCache[patient.id] = advice
                    }
                } else {
                    advice = HabitEngine.advise(payments: [], patient: nil, settings: settings, now: Date())
                }
                items.append(
                    DayItem(
                        consultation: consultation,
                        patient: patient,
                        payment: paymentsByConsultation[consultation.id]?.first,
                        advice: advice
                    )
                )
            }

            dayItems = items
            unassignedToday = items.filter { $0.consultation.isUnassigned && $0.consultation.status != .cancelled }
            dayStatistics = try store.statistics(for: range, settings: settings)

            if let selectedPatientID {
                selectedProfile = try store.profile(forPatient: selectedPatientID, settings: settings)
            } else {
                selectedProfile = nil
            }
            undoRevision = undoStack.revision
        } catch {
            report(error)
        }
    }

    func selectPatient(_ id: UUID?) {
        selectedPatientID = id
        do {
            selectedProfile = try id.flatMap { try store.profile(forPatient: $0, settings: settings) }
        } catch {
            report(error)
        }
    }

    // MARK: - Day navigation

    func select(day: Date) {
        selectedDay = Calendar.cadence.startOfDay(for: day)
        reload()
    }

    func goToToday() { select(day: Date()) }

    func shiftDay(by days: Int) {
        guard let next = Calendar.cadence.date(byAdding: .day, value: days, to: selectedDay) else { return }
        select(day: next)
    }

    /// The next appointment still to happen today, used by the header.
    var nextItem: DayItem? {
        dayItems
            .filter { !$0.consultation.status.isResolved && $0.consultation.scheduledEnd > now }
            .min { $0.consultation.scheduledStart < $1.consultation.scheduledStart }
    }

    var runningItem: DayItem? {
        dayItems.first { $0.consultation.status == .inProgress }
    }

    var itemsAwaitingPayment: [DayItem] {
        dayItems.filter(\.awaitsPayment)
    }

    // MARK: - Attendance

    func mark(_ status: ConsultationStatus, for item: DayItem) {
        let previous = item.consultation.status
        guard previous != status else { return }
        let id = item.consultation.id

        perform(
            label: "\(ConsultationStatusPresentation.of(status).label) · \(item.title)",
            confirmation: "\(item.title) · \(ConsultationStatusPresentation.of(status).label.lowercased())",
            action: { try self.store.setStatus(status, forConsultation: id) },
            revert: { try self.store.setStatus(previous, forConsultation: id) }
        )
    }

    func startSession(_ item: DayItem) {
        let id = item.consultation.id
        let previousStatus = item.consultation.status
        let previousStart = item.consultation.actualStart

        perform(
            label: "Démarrage · \(item.title)",
            confirmation: "Séance démarrée · \(item.title)",
            action: { try self.store.startConsultation(id) },
            revert: {
                try self.store.setStatus(previousStatus, forConsultation: id)
                if previousStart == nil { try self.store.clearActualTimes(id) }
            }
        )
    }

    func endSession(_ item: DayItem) {
        let id = item.consultation.id
        let previousStatus = item.consultation.status
        let previousEnd = item.consultation.actualEnd

        perform(
            label: "Fin de séance · \(item.title)",
            confirmation: "Séance terminée · \(item.title)",
            action: { try self.store.endConsultation(id) },
            revert: {
                try self.store.setStatus(previousStatus, forConsultation: id)
                if previousEnd == nil {
                    guard var consultation = try self.store.consultation(id: id) else { return }
                    consultation.actualEnd = nil
                    try self.store.upsertConsultationSilently(consultation)
                }
            }
        )
    }

    // MARK: - Payments

    /// Records a payment. Immediate, with no confirmation — ⌘Z is the safety net.
    func recordPayment(_ suggestion: PaymentSuggestion, for item: DayItem, note: String? = nil) {
        guard let patient = item.patient else {
            failure = "Ce rendez-vous n'est rattaché à aucun patient. Associez-le d'abord à un patient."
            return
        }
        let consultationID = item.consultation.id
        let amount = Money(cents: suggestion.amountCents, currencyCode: settings.currencyCode)
        var recordedID: UUID?
        var recorded: Payment?

        perform(
            label: "Paiement de \(amount.formatted()) · \(patient.displayName)",
            confirmation: "\(amount.formatted()) · \(settings.methodLabel(suggestion.methodID)) enregistré",
            action: {
                let payment = try self.store.recordPayment(
                    consultationID: consultationID,
                    patientID: patient.id,
                    amountCents: suggestion.amountCents,
                    methodID: suggestion.methodID,
                    currencyCode: self.settings.currencyCode,
                    note: note
                )
                recordedID = payment.id
                recorded = payment
            },
            revert: {
                if let recordedID { try self.store.deletePaymentSilently(recordedID) }
            },
            replay: {
                if let recorded { try self.store.restorePayment(recorded) }
            }
        )
    }

    /// Saves a payment the user composed by hand (another amount, a late-cancellation
    /// charge). Identical guarantees to the one-click path, including undo.
    func recordExistingPayment(_ payment: Payment, patientName: String) {
        let snapshot = payment
        perform(
            label: "Paiement de \(payment.money.formatted()) · \(patientName)",
            confirmation: "\(payment.money.formatted()) · \(settings.methodLabel(payment.methodID)) enregistré",
            action: { try self.store.updatePayment(snapshot) },
            revert: { try self.store.deletePaymentSilently(snapshot.id) },
            replay: { try self.store.restorePayment(snapshot) }
        )
    }

    func deletePayment(_ payment: Payment, patientName: String) {
        let snapshot = payment
        perform(
            label: "Suppression du paiement · \(patientName)",
            confirmation: "Paiement supprimé",
            action: { try self.store.deletePayment(snapshot.id) },
            revert: { try self.store.restorePayment(snapshot) }
        )
    }

    func updatePayment(_ payment: Payment, original: Payment) {
        perform(
            label: "Modification du paiement",
            confirmation: "Paiement modifié",
            action: { try self.store.updatePayment(payment) },
            revert: { try self.store.updatePayment(original) }
        )
    }

    // MARK: - Patients and consultations

    @discardableResult
    func createPatient(named name: String) -> Patient? {
        do {
            let patient = try store.createPatient(displayName: name)
            reload()
            showToast("Patient créé · \(patient.displayName)")
            return patient
        } catch {
            report(error)
            return nil
        }
    }

    func updatePatient(_ patient: Patient) {
        do {
            let original = try store.patient(id: patient.id)
            try store.updatePatient(patient)
            if let original {
                undoStack.register(
                    label: "Modification de \(original.displayName)",
                    undo: { try self.store.upsertPatient(original); Task { @MainActor in self.reload() } },
                    redo: { try self.store.upsertPatient(patient); Task { @MainActor in self.reload() } }
                )
            }
            reload()
        } catch {
            report(error)
        }
    }

    func setPatientArchived(_ patient: Patient, archived: Bool) {
        perform(
            label: archived ? "Archivage de \(patient.displayName)" : "Réactivation de \(patient.displayName)",
            confirmation: archived ? "\(patient.displayName) archivé" : "\(patient.displayName) réactivé",
            action: { try self.store.setPatientArchived(patient.id, archived: archived) },
            revert: { try self.store.setPatientArchived(patient.id, archived: !archived) }
        )
    }

    /// Genuinely destructive, so this one is confirmed by the caller and is not undoable.
    func deletePatient(_ patient: Patient) {
        do {
            try store.deletePatient(patient.id)
            if selectedPatientID == patient.id { selectedPatientID = nil }
            undoStack.clear()
            reload()
            showToast("\(patient.displayName) supprimé")
        } catch {
            report(error)
        }
    }

    func deletionImpact(for patient: Patient) -> (consultations: Int, payments: Int) {
        (try? store.deletionImpact(forPatient: patient.id)) ?? (0, 0)
    }

    @discardableResult
    func createConsultation(patientID: UUID?, title: String, start: Date, end: Date, location: String? = nil) -> Consultation? {
        do {
            let consultation = try store.createConsultation(
                patientID: patientID, title: title, start: start, end: end, location: location
            )
            let id = consultation.id
            undoStack.register(
                label: "Création du rendez-vous",
                undo: { try self.store.deleteConsultation(id); Task { @MainActor in self.reload() } },
                redo: { try self.store.upsertConsultationSilently(consultation); Task { @MainActor in self.reload() } }
            )
            select(day: start)
            showToast("Rendez-vous créé · \(CadenceFormat.time(start))")
            return consultation
        } catch {
            report(error)
            return nil
        }
    }

    func updateConsultation(_ consultation: Consultation, original: Consultation) {
        perform(
            label: "Modification du rendez-vous",
            confirmation: "Rendez-vous modifié",
            action: { try self.store.updateConsultation(consultation) },
            revert: { try self.store.updateConsultation(original) }
        )
    }

    func deleteConsultation(_ consultation: Consultation) {
        let snapshot = consultation
        perform(
            label: "Suppression du rendez-vous",
            confirmation: "Rendez-vous supprimé",
            action: { try self.store.deleteConsultation(snapshot.id) },
            revert: { try self.store.upsertConsultationSilently(snapshot) }
        )
    }

    func assign(patientID: UUID?, to consultation: Consultation) {
        let previous = consultation.patientID
        let id = consultation.id
        let name = patientID.flatMap { identifier in patients.first { $0.id == identifier }?.displayName } ?? "aucun patient"
        perform(
            label: "Association du rendez-vous",
            confirmation: "Rendez-vous associé à \(name)",
            action: { try self.store.assignPatient(patientID, toConsultation: id) },
            revert: { try self.store.assignPatient(previous, toConsultation: id, rememberAlias: false) }
        )
    }

    /// Creates a patient from an unmatched calendar event and links them in one step.
    func createPatientAndAssign(from consultation: Consultation) {
        let suggested = Self.suggestedName(from: consultation.title)
        do {
            let patient = try store.createPatient(displayName: suggested)
            try store.assignPatient(patient.id, toConsultation: consultation.id)
            reload()
            showToast("\(patient.displayName) créé et rattaché")
        } catch {
            report(error)
        }
    }

    /// Turns "RDV Séance - Jean Dupont (visio)" into "Jean Dupont".
    static func suggestedName(from title: String) -> String {
        let cleaned = TextNormaliser.candidateName(fromEventTitle: title)
        guard !cleaned.isEmpty else { return title }
        return cleaned
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    func resolveConflict(_ consultation: Consultation, keepingCalendar: Bool) {
        do {
            try store.resolveConflict(consultation.id, keepingCalendarVersion: keepingCalendar)
            reload()
            showToast(keepingCalendar ? "Version de l'agenda conservée" : "Rendez-vous détaché de l'agenda", undoLabel: nil)
        } catch {
            report(error)
        }
    }

    // MARK: - Settings

    func save(settings newValue: PracticeSettings) {
        do {
            try store.saveSettings(newValue)
            settings = newValue
            reload()
        } catch {
            report(error)
        }
    }

    // MARK: - Undo

    var canUndo: Bool { undoStack.canUndo }
    var canRedo: Bool { undoStack.canRedo }
    var undoTitle: String { undoStack.nextUndoLabel.map { "Annuler \($0)" } ?? "Annuler" }
    var redoTitle: String { undoStack.nextRedoLabel.map { "Rétablir \($0)" } ?? "Rétablir" }

    func performUndo() {
        do {
            if let label = try undoStack.undo() {
                reload()
                showToast("Annulé · \(label)")
            }
        } catch {
            report(error)
        }
    }

    func performRedo() {
        do {
            if let label = try undoStack.redo() {
                reload()
                showToast("Rétabli · \(label)")
            }
        } catch {
            report(error)
        }
    }

    // MARK: - Feedback

    func showToast(_ text: String, undoLabel: String? = "Annuler") {
        toast = ToastMessage(text: text, undoLabel: undoStack.canUndo ? undoLabel : nil)
        toastDismissal?.cancel()
        toastDismissal = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(Motion.standard) { self.toast = nil }
        }
    }

    func dismissToast() {
        toastDismissal?.cancel()
        toast = nil
    }

    func report(_ error: Error) {
        failure = Self.humanMessage(for: error)
        NSLog("Cadence error: %@", String(describing: error))
    }

    static func humanMessage(for error: Error) -> String {
        if let sqlite = error as? SQLiteError {
            return "La base de données a refusé l'opération (\(sqlite.code)). Vos données précédentes sont intactes."
        }
        return (error as NSError).localizedDescription
    }

    // MARK: - Plumbing

    /// Runs a mutation, registers how to reverse it, refreshes, and confirms.
    private func perform(
        label: String,
        confirmation: String,
        action: @escaping () throws -> Void,
        revert: @escaping () throws -> Void,
        replay: (() throws -> Void)? = nil
    ) {
        do {
            try action()
            undoStack.register(
                label: label,
                undo: { try revert(); Task { @MainActor in self.reload() } },
                redo: { try (replay ?? action)(); Task { @MainActor in self.reload() } }
            )
            reload()
            showToast(confirmation)
        } catch {
            report(error)
        }
    }

    // MARK: - Intents from the menu bar and the command palette

    func present(_ sheet: AppSheet) { activeSheet = sheet }

    func requestNewConsultation(at date: Date? = nil) {
        let suggested = date ?? defaultSlotForNewConsultation()
        activeSheet = .newConsultation(suggested)
    }

    func requestNewPatient() { activeSheet = .newPatient }

    /// A sensible default for a new appointment: the next round slot, on the day
    /// currently being looked at.
    func defaultSlotForNewConsultation() -> Date {
        let calendar = Calendar.cadence
        let reference = isShowingToday ? Date() : selectedDay.addingTimeInterval(9 * 3_600)
        let minute = calendar.component(.minute, from: reference)
        let rounded = calendar.date(
            bySetting: .minute, value: minute < 30 ? 30 : 0,
            of: minute < 30 ? reference : reference.addingTimeInterval(3_600)
        ) ?? reference
        var components = calendar.dateComponents([.hour, .minute], from: rounded)
        components.year = calendar.component(.year, from: selectedDay)
        components.month = calendar.component(.month, from: selectedDay)
        components.day = calendar.component(.day, from: selectedDay)
        components.second = 0
        return calendar.date(from: components) ?? reference
    }
}

/// Everything that can appear over the workspace. One enum, so two sheets can never
/// fight over the screen.
enum AppSheet: Identifiable, Equatable {
    case newConsultation(Date)
    case newPatient
    case editPatient(Patient)
    case editConsultation(Consultation)
    case editPayment(Payment, patientName: String)
    case shortcuts

    var id: String {
        switch self {
        case .newConsultation(let date): return "new-consultation-\(date.timeIntervalSince1970)"
        case .newPatient: return "new-patient"
        case .editPatient(let patient): return "edit-patient-\(patient.id)"
        case .editConsultation(let consultation): return "edit-consultation-\(consultation.id)"
        case .editPayment(let payment, _): return "edit-payment-\(payment.id)"
        case .shortcuts: return "shortcuts"
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case practice, calendars, payments, data

    var id: String { rawValue }

    var title: String {
        switch self {
        case .practice: return "Cabinet"
        case .calendars: return "Agenda"
        case .payments: return "Tarifs et paiements"
        case .data: return "Données et sauvegardes"
        }
    }

    var symbol: String {
        switch self {
        case .practice: return "building.2"
        case .calendars: return "calendar"
        case .payments: return "creditcard"
        case .data: return "externaldrive"
        }
    }
}
