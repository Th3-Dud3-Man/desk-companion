import Foundation
import EventKit
import AppKit
import Combine
import CadenceCore

/// Reads the Mac's calendars and hands the events to the (tested) merge engine.
///
/// EventKit is the whole calendar story on purpose. A Google account added in
/// System Settings → Internet Accounts publishes its calendars through CalDAV, and
/// they appear here exactly like iCloud or local ones. That buys Google Calendar
/// support with no OAuth flow, no client secret in the binary, no quota, and — the
/// point that matters most for this application — **no patient data leaving the Mac**.
///
/// Cadence never writes to a calendar. Reading is enough, and the risk of damaging
/// the user's real agenda is not worth taking.
@MainActor
final class CalendarSyncService: ObservableObject {

    enum Access: Equatable {
        case notDetermined
        case granted
        case denied
        case restricted
        /// macOS granted write-only access, which cannot read the schedule.
        case writeOnly

        var canRead: Bool { self == .granted }

        var explanation: String {
            switch self {
            case .notDetermined:
                return "Cadence n'a pas encore demandé l'accès à vos calendriers."
            case .granted:
                return "Cadence peut lire les calendriers que vous avez sélectionnés."
            case .denied:
                return "L'accès aux calendriers a été refusé. Vous pouvez l'accorder dans Réglages Système › Confidentialité et sécurité › Calendriers."
            case .restricted:
                return "L'accès aux calendriers est restreint sur ce Mac."
            case .writeOnly:
                return "macOS n'a accordé qu'un accès en écriture. Cadence a besoin de la lecture pour retrouver vos rendez-vous : accordez l'accès complet dans Réglages Système › Confidentialité et sécurité › Calendriers."
            }
        }
    }

    // MARK: State

    @Published private(set) var access: Access = .notDetermined
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var lastOutcome: CalendarSyncOutcome?
    @Published private(set) var lastError: String?
    @Published private(set) var subscriptions: [CalendarSubscription] = []

    /// Called after a synchronisation changes anything, so the model can refresh.
    var onChange: (() -> Void)?

    private let store: CadenceStore
    private let eventStore = EKEventStore()
    private var changeObserver: NSObjectProtocol?
    private var automaticSyncTask: Task<Void, Never>?

    init(store: CadenceStore) {
        self.store = store
        self.access = Self.currentAccess()
        self.subscriptions = (try? store.calendarSubscriptions()) ?? []

        // macOS tells us when anything in the calendar database changes — a new
        // event, an edit from the phone, an account finishing its own refresh.
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: eventStore, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.synchronise(trigger: .calendarChanged) }
        }
    }

    deinit {
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
    }

    var hasEnabledCalendars: Bool { subscriptions.contains(where: \.isEnabled) }

    // MARK: Access

    static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .fullAccess: return .granted
        case .writeOnly: return .writeOnly
        @unknown default: return .notDetermined
        }
    }

    /// Asks macOS for calendar access, then lists what is available.
    @discardableResult
    func requestAccess() async -> Access {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            access = granted ? .granted : Self.currentAccess()
            lastError = nil
        } catch {
            access = Self.currentAccess()
            lastError = error.localizedDescription
        }
        if access.canRead { refreshAvailableCalendars() }
        return access
    }

    /// Opens the exact System Settings pane, rather than telling the user to go hunting.
    func openSystemPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        if let url { NSWorkspace.shared.open(url) }
    }

    /// Opens the pane where a Google account is added to the Mac.
    func openInternetAccountsSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preferences.internetaccounts")
        if let url { NSWorkspace.shared.open(url) }
    }

    // MARK: Calendars

    /// Merges what macOS reports with what the user already chose.
    func refreshAvailableCalendars() {
        guard access.canRead else { return }
        let discovered = eventStore.calendars(for: .event).map { calendar in
            CalendarSubscription(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                colourHex: Self.hex(from: calendar.cgColor),
                accountName: calendar.source?.title
            )
        }
        do {
            try store.reconcileCalendars(discovered)
            subscriptions = try store.calendarSubscriptions()
        } catch {
            lastError = AppModel.humanMessage(for: error)
        }
    }

    func setEnabled(_ enabled: Bool, for calendarID: String) {
        do {
            try store.setCalendarEnabled(calendarID, enabled: enabled)
            if !enabled {
                // Untouched appointments from that calendar go; anything worked on stays.
                _ = try store.purgeCalendar(calendarID)
            }
            subscriptions = try store.calendarSubscriptions()
            onChange?()
            if enabled { Task { await synchronise(trigger: .userAction) } }
        } catch {
            lastError = AppModel.humanMessage(for: error)
        }
    }

    // MARK: Synchronising

    enum Trigger {
        /// Opening the application.
        case launch
        /// The user asked for it, so failures are worth saying out loud.
        case userAction
        /// macOS told us the calendar database changed.
        case calendarChanged
    }

    func synchronise(trigger: Trigger = .userAction) async {
        guard access.canRead else {
            if trigger == .userAction { lastError = access.explanation }
            return
        }
        guard !isSyncing else { return }

        let enabledIDs = (try? store.enabledCalendarIDs()) ?? []
        guard !enabledIDs.isEmpty else {
            if trigger == .userAction {
                lastError = "Aucun calendrier sélectionné. Choisissez-en un dans les Réglages."
            }
            return
        }

        isSyncing = true
        lastError = nil
        for id in enabledIDs { try? store.updateCalendarStatus(id, status: .syncing) }

        let settings = (try? store.settings()) ?? .default
        let now = Date()
        let window = DateRange(
            start: Calendar.cadence.date(byAdding: .day, value: -settings.syncPastDays, to: now) ?? now,
            end: Calendar.cadence.date(byAdding: .day, value: settings.syncFutureDays, to: now) ?? now
        )

        let events = await Self.fetchEvents(calendarIDs: enabledIDs, window: window)

        do {
            let outcome = try store.applyCalendarSync(
                events: events, calendarIDs: Set(enabledIDs), window: window, now: now
            )
            lastOutcome = outcome
            lastSyncAt = now
            for id in enabledIDs {
                try? store.updateCalendarStatus(id, status: .synced, message: outcome.summary, syncedAt: now)
            }
            subscriptions = (try? store.calendarSubscriptions()) ?? subscriptions
            if outcome.changeCount > 0 || trigger == .userAction { onChange?() }
        } catch {
            let message = AppModel.humanMessage(for: error)
            lastError = message
            for id in enabledIDs { try? store.updateCalendarStatus(id, status: .failed, message: message) }
            subscriptions = (try? store.calendarSubscriptions()) ?? subscriptions
        }

        isSyncing = false
    }

    /// Reads events off the main thread, using its own event store instance so
    /// nothing actor-isolated crosses a thread boundary.
    private nonisolated static func fetchEvents(
        calendarIDs: [String],
        window: DateRange
    ) async -> [CalendarImportEvent] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let localStore = EKEventStore()
                let wanted = Set(calendarIDs)
                let calendars = localStore.calendars(for: .event)
                    .filter { wanted.contains($0.calendarIdentifier) }

                guard !calendars.isEmpty else {
                    continuation.resume(returning: [])
                    return
                }

                let predicate = localStore.predicateForEvents(
                    withStart: window.start, end: window.end, calendars: calendars
                )
                let events = localStore.events(matching: predicate)

                let imported: [CalendarImportEvent] = events.compactMap { event in
                    // All-day entries are holidays and reminders, not consultations.
                    guard !event.isAllDay else { return nil }
                    guard event.status != .canceled else { return nil }
                    guard let identifier = event.eventIdentifier, !identifier.isEmpty else { return nil }
                    guard let start = event.startDate, let end = event.endDate else { return nil }

                    let title = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return CalendarImportEvent(
                        eventIdentifier: identifier,
                        calendarIdentifier: event.calendar?.calendarIdentifier ?? "",
                        title: title.isEmpty ? "Sans titre" : title,
                        start: start,
                        end: end,
                        location: event.location?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                        occurrenceDate: event.occurrenceDate ?? start
                    )
                }
                continuation.resume(returning: imported)
            }
        }
    }

    // MARK: Status for the interface

    /// One short line the user can read at a glance, and always truthful.
    var statusLine: String {
        if isSyncing { return "Synchronisation…" }
        if !access.canRead { return access == .notDetermined ? "Agenda non connecté" : "Accès refusé" }
        if !hasEnabledCalendars { return "Aucun calendrier sélectionné" }
        if let lastError { return lastError }
        if let lastSyncAt { return "À jour · \(CadenceFormat.since(lastSyncAt))" }
        return "Jamais synchronisé"
    }

    var statusSymbol: String {
        if isSyncing { return "arrow.triangle.2.circlepath" }
        if !access.canRead { return "calendar.badge.exclamationmark" }
        if lastError != nil { return "exclamationmark.triangle.fill" }
        if lastSyncAt != nil { return "checkmark.circle.fill" }
        return "calendar"
    }

    private static func hex(from cgColor: CGColor?) -> String? {
        guard let cgColor, let colour = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB) else { return nil }
        let red = Int((colour.redComponent * 255).rounded())
        let green = Int((colour.greenComponent * 255).rounded())
        let blue = Int((colour.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", red, green, blue)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
