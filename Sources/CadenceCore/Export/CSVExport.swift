import Foundation

/// CSV writer tuned for the tool these files actually end up in: Excel, in French.
///
/// That means a semicolon separator, a UTF-8 byte-order mark so accents survive the
/// double-click, CRLF line endings, and comma decimal marks. A comma-separated,
/// BOM-less file opens as a single mangled column and is worse than no export.
public struct CSVWriter {
    public private(set) var rows: [[String]] = []

    public init() {}

    public mutating func addRow(_ values: [String]) { rows.append(values) }

    public func encoded() -> String {
        rows.map { row in
            row.map(Self.escape).joined(separator: ";")
        }.joined(separator: "\r\n") + "\r\n"
    }

    /// UTF-8 bytes including the BOM.
    public func data() -> Data {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(encoded().data(using: .utf8) ?? Data())
        return data
    }

    static func escape(_ field: String) -> String {
        let needsQuoting = field.contains(";") || field.contains("\"") || field.contains("\n") || field.contains("\r")
        guard needsQuoting else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// What a given export produces.
public enum ExportKind: String, CaseIterable, Sendable {
    case consultations
    case payments
    case patients

    public var label: String {
        switch self {
        case .consultations: return "Consultations"
        case .payments: return "Paiements"
        case .patients: return "Patients"
        }
    }

    public var fileStem: String {
        switch self {
        case .consultations: return "cadence-consultations"
        case .payments: return "cadence-paiements"
        case .patients: return "cadence-patients"
        }
    }
}

extension CadenceStore {

    /// CSV of every consultation in `range`, with the payment attached to each.
    public func exportConsultationsCSV(range: DateRange, settings: PracticeSettings? = nil) throws -> Data {
        let settings = try settings ?? self.settings()
        let consultations = try consultations(in: range)
        let patients = try patients(ids: Array(Set(consultations.compactMap(\.patientID))))
        let paymentsByConsultation = try paymentsByConsultation(in: range)

        var writer = CSVWriter()
        writer.addRow([
            "Date", "Début prévu", "Fin prévue", "Patient", "Statut",
            "Début réel", "Fin réelle", "Durée réelle (min)",
            "Montant", "Devise", "Moyen de paiement", "Règlement", "Payé le",
            "Source", "Lieu", "Notes",
        ])

        for consultation in consultations {
            let patientName = consultation.patientID
                .flatMap { patients[$0]?.displayName }
                ?? consultation.title
            let payment = paymentsByConsultation[consultation.id]?.first
            let realMinutes = consultation.actualDuration.map { String(Int(($0 / 60).rounded())) } ?? ""

            writer.addRow([
                CadenceFormat.numericDate(consultation.scheduledStart),
                CadenceFormat.time(consultation.scheduledStart),
                CadenceFormat.time(consultation.scheduledEnd),
                patientName,
                consultation.status.label,
                consultation.actualStart.map(CadenceFormat.time) ?? "",
                consultation.actualEnd.map(CadenceFormat.time) ?? "",
                realMinutes,
                payment?.money.csvValue ?? "",
                payment?.currencyCode ?? "",
                payment.map { settings.methodLabel($0.methodID) } ?? "",
                payment.map { $0.isPending ? "En attente" : "Reçu" } ?? "",
                payment.map { CadenceFormat.numericDateTime($0.paidAt) } ?? "",
                consultation.source == .calendar ? "Agenda" : "Cadence",
                consultation.location ?? "",
                consultation.notes ?? "",
            ])
        }
        return writer.data()
    }

    /// CSV of the money actually received in `range` — the one an accountant wants.
    public func exportPaymentsCSV(range: DateRange, settings: PracticeSettings? = nil) throws -> Data {
        let settings = try settings ?? self.settings()
        let payments = try payments(in: range)
        let patients = try patients(ids: Array(Set(payments.map(\.patientID))))

        var writer = CSVWriter()
        writer.addRow([
            "Date", "Heure", "Patient", "Montant", "Devise", "Moyen de paiement",
            "Règlement", "Date de règlement", "Date de la consultation", "Note",
        ])

        for payment in payments {
            let linked = try payment.consultationID.flatMap { try self.consultation(id: $0) }
            writer.addRow([
                CadenceFormat.numericDate(payment.paidAt),
                CadenceFormat.time(payment.paidAt),
                patients[payment.patientID]?.displayName ?? "Patient supprimé",
                payment.money.csvValue,
                payment.currencyCode,
                settings.methodLabel(payment.methodID),
                payment.isPending ? "En attente" : "Reçu",
                payment.settledAt.map(CadenceFormat.numericDate) ?? "",
                linked.map { CadenceFormat.numericDate($0.scheduledStart) } ?? "",
                payment.note ?? "",
            ])
        }
        return writer.data()
    }

    /// CSV of the patient list with each one's totals and usual payment.
    public func exportPatientsCSV(settings: PracticeSettings? = nil, now: Date = Date()) throws -> Data {
        let settings = try settings ?? self.settings()
        let patients = try allPatients(includeArchived: true)

        var writer = CSVWriter()
        writer.addRow([
            "Nom", "E-mail", "Téléphone", "Archivé",
            "Consultations", "Présences", "Absences", "Taux de présence",
            "Total encaissé", "En attente", "Montant habituel", "Moyen habituel", "Habitude établie",
            "Première consultation", "Dernière consultation", "Rythme", "Notes",
        ])

        for patient in patients {
            guard let profile = try profile(forPatient: patient.id, settings: settings, now: now) else { continue }
            let rate = profile.attendanceRate.map { "\(Int(($0 * 100).rounded())) %" } ?? ""
            writer.addRow([
                patient.displayName,
                patient.email ?? "",
                patient.phone ?? "",
                patient.isArchived ? "oui" : "non",
                String(profile.totalConsultations),
                String(profile.attended),
                String(profile.absent),
                rate,
                Money(cents: profile.totalCollectedCents, currencyCode: settings.currencyCode).csvValue,
                Money(cents: profile.outstandingCents, currencyCode: settings.currencyCode).csvValue,
                profile.advice.primary.money.csvValue,
                settings.methodLabel(profile.advice.primary.methodID),
                profile.advice.isHabit ? "oui" : "non",
                profile.firstSeen.map(CadenceFormat.numericDate) ?? "",
                profile.lastSeen.map(CadenceFormat.numericDate) ?? "",
                profile.rhythm.label,
                patient.notes?.replacingOccurrences(of: "\n", with: " ") ?? "",
            ])
        }
        return writer.data()
    }

    public func exportCSV(_ kind: ExportKind, range: DateRange, settings: PracticeSettings? = nil) throws -> Data {
        switch kind {
        case .consultations: return try exportConsultationsCSV(range: range, settings: settings)
        case .payments: return try exportPaymentsCSV(range: range, settings: settings)
        case .patients: return try exportPatientsCSV(settings: settings)
        }
    }
}
