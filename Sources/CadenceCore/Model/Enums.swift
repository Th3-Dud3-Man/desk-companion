import Foundation

/// Where a consultation came from.
public enum ConsultationSource: String, Codable, CaseIterable, Sendable {
    /// Imported from a calendar the user subscribed to (Apple, iCloud, Google, CalDAV…).
    case calendar
    /// Created inside Cadence.
    case manual
}

/// Lifecycle of a consultation.
///
/// The ordering below is the natural progression, not a constraint: any status can
/// be reached from any other in one gesture. The user is never blocked by a state
/// machine when reality disagrees with it.
public enum ConsultationStatus: String, Codable, CaseIterable, Sendable {
    case scheduled      // planned, nothing recorded yet
    case confirmed      // patient confirmed they are coming
    case inProgress     // session started with the explicit "Démarrer" action
    case attended       // the patient came
    case absent         // the patient did not come
    case cancelled      // the appointment was cancelled

    public var label: String {
        switch self {
        case .scheduled: return "Planifié"
        case .confirmed: return "Confirmé"
        case .inProgress: return "En cours"
        case .attended: return "Présent"
        case .absent: return "Absent"
        case .cancelled: return "Annulé"
        }
    }

    /// Statuses the user has explicitly resolved — they no longer need attention.
    public var isResolved: Bool {
        switch self {
        case .attended, .absent, .cancelled: return true
        case .scheduled, .confirmed, .inProgress: return false
        }
    }

    /// Only an attended consultation invites a payment. An absence never does.
    public var invitesPayment: Bool { self == .attended }

    /// Whether calendar synchronisation may silently overwrite this consultation.
    public var isLockedAgainstSync: Bool {
        switch self {
        case .attended, .absent, .inProgress: return true
        case .scheduled, .confirmed, .cancelled: return false
        }
    }
}

/// Relationship between a consultation and its source calendar event.
public enum ConsultationSyncState: String, Codable, CaseIterable, Sendable {
    /// Matches the calendar event as of the last synchronisation.
    case synced
    /// Lives only in Cadence.
    case local
    /// The calendar event moved or changed after the consultation was resolved.
    /// Cadence never resolves this on the user's behalf.
    case conflict
    /// The calendar event disappeared but the consultation carries real data
    /// (a status or a payment) so it was kept rather than deleted.
    case orphaned

    public var label: String {
        switch self {
        case .synced: return "Synchronisé"
        case .local: return "Local"
        case .conflict: return "Conflit"
        case .orphaned: return "Retiré de l'agenda"
        }
    }
}

/// A configurable way of paying. Not an enum: the practice must be able to add,
/// rename and reorder these without a code change (§ 8 of the brief).
public struct PaymentMethod: Hashable, Codable, Identifiable, Sendable {
    public var id: String
    public var label: String
    /// SF Symbol name used by the macOS layer. Kept here so the catalogue is one object.
    public var symbol: String
    public var isEnabled: Bool

    public init(id: String, label: String, symbol: String, isEnabled: Bool = true) {
        self.id = id
        self.label = label
        self.symbol = symbol
        self.isEnabled = isEnabled
    }

    public static let cash = PaymentMethod(id: "cash", label: "Espèces", symbol: "banknote")
    public static let card = PaymentMethod(id: "card", label: "Carte", symbol: "creditcard")
    public static let cheque = PaymentMethod(id: "cheque", label: "Chèque", symbol: "doc.text")
    public static let transfer = PaymentMethod(id: "transfer", label: "Virement", symbol: "arrow.left.arrow.right")
    public static let other = PaymentMethod(id: "other", label: "Autre", symbol: "ellipsis.circle")

    /// The catalogue a fresh install starts with.
    public static let builtIn: [PaymentMethod] = [.cash, .card, .cheque, .transfer, .other]
}

/// Actions recorded in the audit trail. Also the vocabulary of the undo stack.
public enum ActionKind: String, Codable, CaseIterable, Sendable {
    case patientCreated
    case patientUpdated
    case patientArchived
    case patientDeleted
    case consultationCreated
    case consultationUpdated
    case consultationStatusChanged
    case consultationStarted
    case consultationEnded
    case consultationDeleted
    case paymentRecorded
    case paymentUpdated
    case paymentDeleted
    case calendarSynchronised
    case demoDataInstalled
    case demoDataRemoved
    case backupCreated
    case backupRestored

    public var label: String {
        switch self {
        case .patientCreated: return "Patient créé"
        case .patientUpdated: return "Patient modifié"
        case .patientArchived: return "Patient archivé"
        case .patientDeleted: return "Patient supprimé"
        case .consultationCreated: return "Consultation créée"
        case .consultationUpdated: return "Consultation modifiée"
        case .consultationStatusChanged: return "Statut modifié"
        case .consultationStarted: return "Séance démarrée"
        case .consultationEnded: return "Séance terminée"
        case .consultationDeleted: return "Consultation supprimée"
        case .paymentRecorded: return "Paiement enregistré"
        case .paymentUpdated: return "Paiement modifié"
        case .paymentDeleted: return "Paiement supprimé"
        case .calendarSynchronised: return "Agenda synchronisé"
        case .demoDataInstalled: return "Données de démonstration installées"
        case .demoDataRemoved: return "Données de démonstration supprimées"
        case .backupCreated: return "Sauvegarde créée"
        case .backupRestored: return "Sauvegarde restaurée"
        }
    }
}
