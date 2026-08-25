import Foundation

// MARK: - Patient

public struct Patient: Identifiable, Hashable, Sendable {
    public var id: UUID
    /// The name shown everywhere. Always populated, even when the parts are unknown.
    public var displayName: String
    public var firstName: String?
    public var lastName: String?
    public var email: String?
    public var phone: String?
    /// Stable seed used to derive the monogram tint, so a patient keeps the same
    /// colour for the lifetime of the file.
    public var colourSeed: Int
    /// Free-form practical notes. Explicitly *not* clinical records — see docs/DONNEES.md.
    public var notes: String?
    /// Optional per-patient override used before any payment history exists.
    public var defaultAmountCents: Int?
    public var defaultMethodID: String?
    public var isArchived: Bool
    public var isDemo: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        displayName: String,
        firstName: String? = nil,
        lastName: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        colourSeed: Int? = nil,
        notes: String? = nil,
        defaultAmountCents: Int? = nil,
        defaultMethodID: String? = nil,
        isArchived: Bool = false,
        isDemo: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phone = phone
        self.colourSeed = colourSeed ?? Patient.seed(for: displayName)
        self.notes = notes
        self.defaultAmountCents = defaultAmountCents
        self.defaultMethodID = defaultMethodID
        self.isArchived = isArchived
        self.isDemo = isDemo
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Deterministic, stable across launches and platforms (`hashValue` is not).
    public static func seed(for name: String) -> Int {
        var hash = 5381
        for byte in TextNormaliser.normalise(name).utf8 {
            hash = ((hash &* 33) &+ Int(byte)) & 0x7FFF_FFFF
        }
        return hash
    }

    /// One or two letters for the avatar, e.g. `Jean Dupont` → `JD`.
    public var monogram: String {
        let parts = displayName
            .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "'" })
            .filter { !$0.isEmpty }
        guard let first = parts.first else { return "?" }
        if parts.count >= 2, let last = parts.last, let a = first.first, let b = last.first {
            return String([a, b]).uppercased()
        }
        return String(first.prefix(2)).uppercased()
    }

    /// Surname-first key so the patient list sorts the way a paper file would.
    public var sortKey: String {
        let base = lastName ?? displayName.split(separator: " ").last.map(String.init) ?? displayName
        return TextNormaliser.normalise(base) + " " + TextNormaliser.normalise(displayName)
    }
}

// MARK: - Consultation

public struct Consultation: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var patientID: UUID?
    /// Title as it appears in the calendar, kept verbatim so an unmatched event is
    /// still readable and can be reconciled later.
    public var title: String
    public var source: ConsultationSource
    public var externalEventID: String?
    public var externalCalendarID: String?
    /// `eventIdentifier|startEpoch`. Recurring events share one identifier across all
    /// their occurrences, so the start date is part of the identity.
    public var occurrenceKey: String?
    public var scheduledStart: Date
    public var scheduledEnd: Date
    /// Written only by the explicit "Démarrer" action. Never inferred.
    public var actualStart: Date?
    /// Written only by the explicit "Terminer" action. Never inferred.
    public var actualEnd: Date?
    public var status: ConsultationStatus
    public var location: String?
    public var notes: String?
    public var syncState: ConsultationSyncState
    public var isDemo: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        patientID: UUID? = nil,
        title: String,
        source: ConsultationSource = .manual,
        externalEventID: String? = nil,
        externalCalendarID: String? = nil,
        occurrenceKey: String? = nil,
        scheduledStart: Date,
        scheduledEnd: Date,
        actualStart: Date? = nil,
        actualEnd: Date? = nil,
        status: ConsultationStatus = .scheduled,
        location: String? = nil,
        notes: String? = nil,
        syncState: ConsultationSyncState = .local,
        isDemo: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.patientID = patientID
        self.title = title
        self.source = source
        self.externalEventID = externalEventID
        self.externalCalendarID = externalCalendarID
        self.occurrenceKey = occurrenceKey
        self.scheduledStart = scheduledStart
        self.scheduledEnd = max(scheduledEnd, scheduledStart)
        self.actualStart = actualStart
        self.actualEnd = actualEnd
        self.status = status
        self.location = location
        self.notes = notes
        self.syncState = syncState
        self.isDemo = isDemo
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var scheduledDuration: TimeInterval { scheduledEnd.timeIntervalSince(scheduledStart) }

    /// Real elapsed time, only when both ends were genuinely recorded.
    public var actualDuration: TimeInterval? {
        guard let actualStart, let actualEnd, actualEnd > actualStart else { return nil }
        return actualEnd.timeIntervalSince(actualStart)
    }

    public var isUnassigned: Bool { patientID == nil }

    /// True while the session is running: started, not finished.
    public var isRunning: Bool { status == .inProgress }
}

// MARK: - Payment

public struct Payment: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var consultationID: UUID?
    public var patientID: UUID
    public var amountCents: Int
    public var currencyCode: String
    public var methodID: String
    public var paidAt: Date
    public var note: String?
    public var isDemo: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        consultationID: UUID? = nil,
        patientID: UUID,
        amountCents: Int,
        currencyCode: String = "EUR",
        methodID: String,
        paidAt: Date = Date(),
        note: String? = nil,
        isDemo: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.consultationID = consultationID
        self.patientID = patientID
        self.amountCents = amountCents
        self.currencyCode = currencyCode
        self.methodID = methodID
        self.paidAt = paidAt
        self.note = note
        self.isDemo = isDemo
        self.createdAt = createdAt
    }

    public var money: Money { Money(cents: amountCents, currencyCode: currencyCode) }
}

// MARK: - Audit trail

public struct ActionLogEntry: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var entityType: String
    public var entityID: UUID?
    public var kind: ActionKind
    public var detail: String
    public var at: Date

    public init(
        id: UUID = UUID(),
        entityType: String,
        entityID: UUID?,
        kind: ActionKind,
        detail: String,
        at: Date = Date()
    ) {
        self.id = id
        self.entityType = entityType
        self.entityID = entityID
        self.kind = kind
        self.detail = detail
        self.at = at
    }
}

// MARK: - Calendar subscription

public enum CalendarSyncStatus: String, Codable, Sendable {
    case never
    case syncing
    case synced
    case offline
    case failed
    case denied

    public var label: String {
        switch self {
        case .never: return "Jamais synchronisé"
        case .syncing: return "Synchronisation…"
        case .synced: return "Synchronisé"
        case .offline: return "Hors ligne"
        case .failed: return "Erreur"
        case .denied: return "Accès refusé"
        }
    }
}

public struct CalendarSubscription: Identifiable, Hashable, Sendable {
    /// The EventKit calendar identifier.
    public var id: String
    public var title: String
    public var colourHex: String?
    /// Account name as macOS reports it ("iCloud", "Google", "Sur mon Mac"…).
    public var accountName: String?
    public var isEnabled: Bool
    public var lastSyncAt: Date?
    public var lastStatus: CalendarSyncStatus
    public var lastMessage: String?

    public init(
        id: String,
        title: String,
        colourHex: String? = nil,
        accountName: String? = nil,
        isEnabled: Bool = false,
        lastSyncAt: Date? = nil,
        lastStatus: CalendarSyncStatus = .never,
        lastMessage: String? = nil
    ) {
        self.id = id
        self.title = title
        self.colourHex = colourHex
        self.accountName = accountName
        self.isEnabled = isEnabled
        self.lastSyncAt = lastSyncAt
        self.lastStatus = lastStatus
        self.lastMessage = lastMessage
    }
}
