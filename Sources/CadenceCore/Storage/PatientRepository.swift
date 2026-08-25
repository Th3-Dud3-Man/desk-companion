import Foundation

extension CadenceStore {

    // MARK: - Reading

    public func allPatients(includeArchived: Bool = false) throws -> [Patient] {
        let sql = includeArchived
            ? "SELECT * FROM patient;"
            : "SELECT * FROM patient WHERE archived = 0;"
        return try database.query(sql)
            .compactMap(Self.decodePatient)
            .sorted { $0.sortKey < $1.sortKey }
    }

    public func patient(id: UUID) throws -> Patient? {
        try database.query("SELECT * FROM patient WHERE id = ?;", [.uuid(id)])
            .first
            .flatMap(Self.decodePatient)
    }

    public func patients(ids: [UUID]) throws -> [UUID: Patient] {
        guard !ids.isEmpty else { return [:] }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
        let rows = try database.query("SELECT * FROM patient WHERE id IN (\(placeholders));", ids.map { .uuid($0) })
        return Dictionary(uniqueKeysWithValues: rows.compactMap(Self.decodePatient).map { ($0.id, $0) })
    }

    /// Fuzzy-free search used by the patient list; the ⌘K palette adds its own ranking.
    public func searchPatients(_ query: String, includeArchived: Bool = false) throws -> [Patient] {
        let all = try allPatients(includeArchived: includeArchived)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        return all.filter {
            TextNormaliser.matches($0.displayName, query: trimmed)
                || TextNormaliser.matchesInitials($0.displayName, query: trimmed)
                || TextNormaliser.matches($0.email ?? "", query: trimmed)
                || TextNormaliser.matches($0.phone ?? "", query: trimmed)
        }
    }

    // MARK: - Writing

    @discardableResult
    public func createPatient(
        displayName: String,
        firstName: String? = nil,
        lastName: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        notes: String? = nil,
        defaultAmountCents: Int? = nil,
        defaultMethodID: String? = nil,
        isDemo: Bool = false
    ) throws -> Patient {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let patient = Patient(
            displayName: trimmed.isEmpty ? "Sans nom" : trimmed,
            firstName: firstName,
            lastName: lastName,
            email: email,
            phone: phone,
            notes: notes,
            defaultAmountCents: defaultAmountCents,
            defaultMethodID: defaultMethodID,
            isDemo: isDemo
        )
        try write {
            try insert(patient)
            try addAlias(patient.displayName, to: patient.id)
            try log(.patientCreated, entityType: "patient", entityID: patient.id, detail: patient.displayName)
        }
        return patient
    }

    /// Inserts or replaces the whole row. Used by undo, import and tests.
    public func upsertPatient(_ patient: Patient) throws {
        var updated = patient
        updated.updatedAt = Date()
        try write {
            try insert(updated)
            try addAlias(updated.displayName, to: updated.id)
        }
    }

    public func updatePatient(_ patient: Patient) throws {
        var updated = patient
        updated.updatedAt = Date()
        try write {
            try insert(updated)
            try addAlias(updated.displayName, to: updated.id)
            try log(.patientUpdated, entityType: "patient", entityID: updated.id, detail: updated.displayName)
        }
    }

    public func setPatientArchived(_ id: UUID, archived: Bool) throws {
        try write {
            try database.run(
                "UPDATE patient SET archived = ?, updated_at = ? WHERE id = ?;",
                [.bool(archived), .date(Date()), .uuid(id)]
            )
            let name = try patient(id: id)?.displayName ?? ""
            try log(.patientArchived, entityType: "patient", entityID: id,
                    detail: archived ? "Archivé · \(name)" : "Réactivé · \(name)")
        }
    }

    /// Hard delete. Payments cascade; consultations keep their title and lose the link.
    public func deletePatient(_ id: UUID) throws {
        try write {
            let name = try patient(id: id)?.displayName ?? ""
            try database.run("DELETE FROM patient WHERE id = ?;", [.uuid(id)])
            try log(.patientDeleted, entityType: "patient", entityID: id, detail: name)
        }
    }

    /// How much would be destroyed by `deletePatient`, so the confirmation can say so.
    public func deletionImpact(forPatient id: UUID) throws -> (consultations: Int, payments: Int) {
        let consultations = try database.scalarInt(
            "SELECT COUNT(*) AS value FROM consultation WHERE patient_id = ?;", [.uuid(id)])
        let payments = try database.scalarInt(
            "SELECT COUNT(*) AS value FROM payment WHERE patient_id = ?;", [.uuid(id)])
        return (consultations, payments)
    }

    // MARK: - Aliases (calendar reconciliation memory)

    public func addAlias(_ alias: String, to patientID: UUID) throws {
        let normalised = TextNormaliser.candidateName(fromEventTitle: alias)
        guard normalised.count >= 3 else { return }
        try database.run(
            "INSERT OR IGNORE INTO patient_alias (patient_id, alias) VALUES (?, ?);",
            [.uuid(patientID), .text(normalised)]
        )
    }

    public func aliases(forPatient id: UUID) throws -> [String] {
        try database.query("SELECT alias FROM patient_alias WHERE patient_id = ?;", [.uuid(id)])
            .compactMap { $0.string("alias") }
    }

    public func patientID(forAlias alias: String) throws -> UUID? {
        let normalised = TextNormaliser.candidateName(fromEventTitle: alias)
        guard !normalised.isEmpty else { return nil }
        return try database.query(
            "SELECT patient_id FROM patient_alias WHERE alias = ? LIMIT 1;", [.text(normalised)]
        ).first?.uuid("patient_id")
    }

    // MARK: - Internals

    private func insert(_ patient: Patient) throws {
        try database.run(
            """
            INSERT INTO patient (id, display_name, first_name, last_name, email, phone, colour_seed,
                                 notes, default_amount_cents, default_method, archived, is_demo,
                                 created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                display_name = excluded.display_name,
                first_name = excluded.first_name,
                last_name = excluded.last_name,
                email = excluded.email,
                phone = excluded.phone,
                colour_seed = excluded.colour_seed,
                notes = excluded.notes,
                default_amount_cents = excluded.default_amount_cents,
                default_method = excluded.default_method,
                archived = excluded.archived,
                is_demo = excluded.is_demo,
                updated_at = excluded.updated_at;
            """,
            [
                .uuid(patient.id),
                .text(patient.displayName),
                .optionalText(patient.firstName),
                .optionalText(patient.lastName),
                .optionalText(patient.email),
                .optionalText(patient.phone),
                .int(patient.colourSeed),
                .optionalText(patient.notes),
                .optionalInt(patient.defaultAmountCents),
                .optionalText(patient.defaultMethodID),
                .bool(patient.isArchived),
                .bool(patient.isDemo),
                .date(patient.createdAt),
                .date(patient.updatedAt),
            ]
        )
    }

    static func decodePatient(_ row: Row) -> Patient? {
        guard let id = row.uuid("id") else { return nil }
        return Patient(
            id: id,
            displayName: row.stringValue("display_name", default: "Sans nom"),
            firstName: row.string("first_name"),
            lastName: row.string("last_name"),
            email: row.string("email"),
            phone: row.string("phone"),
            colourSeed: row.int("colour_seed"),
            notes: row.string("notes"),
            defaultAmountCents: row.int("default_amount_cents"),
            defaultMethodID: row.string("default_method"),
            isArchived: row.bool("archived"),
            isDemo: row.bool("is_demo"),
            createdAt: row.date("created_at") ?? Date(),
            updatedAt: row.date("updated_at") ?? Date()
        )
    }
}
