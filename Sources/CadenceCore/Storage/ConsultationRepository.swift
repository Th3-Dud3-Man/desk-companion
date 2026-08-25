import Foundation

extension CadenceStore {

    // MARK: - Reading

    public func consultations(in range: DateRange, includeCancelled: Bool = true) throws -> [Consultation] {
        let sql = """
        SELECT * FROM consultation
        WHERE scheduled_start >= ? AND scheduled_start < ?
        \(includeCancelled ? "" : "AND status != 'cancelled'")
        ORDER BY scheduled_start ASC, rowid ASC;
        """
        return try database.query(sql, [.int(range.startEpoch), .int(range.endEpoch)])
            .compactMap(Self.decodeConsultation)
    }

    public func consultations(onDay day: Date, calendar: Calendar = .cadence) throws -> [Consultation] {
        try consultations(in: .day(containing: day, calendar: calendar))
    }

    public func consultation(id: UUID) throws -> Consultation? {
        try database.query("SELECT * FROM consultation WHERE id = ?;", [.uuid(id)])
            .first
            .flatMap(Self.decodeConsultation)
    }

    public func consultation(occurrenceKey: String) throws -> Consultation? {
        try database.query("SELECT * FROM consultation WHERE occurrence_key = ?;", [.text(occurrenceKey)])
            .first
            .flatMap(Self.decodeConsultation)
    }

    public func consultations(forPatient patientID: UUID, limit: Int = 200) throws -> [Consultation] {
        try database.query(
            """
            SELECT * FROM consultation WHERE patient_id = ?
            ORDER BY scheduled_start DESC LIMIT ?;
            """,
            [.uuid(patientID), .int(limit)]
        ).compactMap(Self.decodeConsultation)
    }

    public func nextConsultation(forPatient patientID: UUID, after date: Date = Date()) throws -> Consultation? {
        try database.query(
            """
            SELECT * FROM consultation
            WHERE patient_id = ? AND scheduled_start >= ? AND status NOT IN ('cancelled', 'absent', 'attended')
            ORDER BY scheduled_start ASC LIMIT 1;
            """,
            [.uuid(patientID), .date(date)]
        ).first.flatMap(Self.decodeConsultation)
    }

    /// Calendar events Cadence could not attach to a patient — surfaced in the UI so
    /// they can be reconciled in one click rather than silently ignored.
    public func unassignedConsultations(in range: DateRange) throws -> [Consultation] {
        try database.query(
            """
            SELECT * FROM consultation
            WHERE patient_id IS NULL AND scheduled_start >= ? AND scheduled_start < ?
              AND status != 'cancelled'
            ORDER BY scheduled_start ASC;
            """,
            [.int(range.startEpoch), .int(range.endEpoch)]
        ).compactMap(Self.decodeConsultation)
    }

    public func consultationsNeedingAttention(in range: DateRange) throws -> [Consultation] {
        try consultations(in: range, includeCancelled: false).filter { !$0.status.isResolved }
    }

    public func consultationsWithSyncIssues() throws -> [Consultation] {
        try database.query(
            "SELECT * FROM consultation WHERE sync_state IN ('conflict', 'orphaned') ORDER BY scheduled_start DESC;"
        ).compactMap(Self.decodeConsultation)
    }

    /// Earliest and latest scheduled consultation, used to bound the agenda navigation.
    public func consultationDateBounds() throws -> (first: Date, last: Date)? {
        guard let row = try database.query(
            "SELECT MIN(scheduled_start) AS first_start, MAX(scheduled_start) AS last_start FROM consultation;"
        ).first, let first = row.date("first_start"), let last = row.date("last_start") else { return nil }
        return (first, last)
    }

    /// Days in `range` that hold at least one consultation — lets the agenda mark
    /// busy days without loading every consultation.
    public func busyDayStarts(in range: DateRange, calendar: Calendar = .cadence) throws -> Set<Date> {
        let rows = try database.query(
            """
            SELECT scheduled_start FROM consultation
            WHERE scheduled_start >= ? AND scheduled_start < ? AND status != 'cancelled';
            """,
            [.int(range.startEpoch), .int(range.endEpoch)]
        )
        var days: Set<Date> = []
        for row in rows {
            if let date = row.date("scheduled_start") {
                days.insert(calendar.startOfDay(for: date))
            }
        }
        return days
    }

    // MARK: - Writing

    @discardableResult
    public func createConsultation(
        patientID: UUID?,
        title: String,
        start: Date,
        end: Date,
        location: String? = nil,
        notes: String? = nil,
        source: ConsultationSource = .manual,
        isDemo: Bool = false
    ) throws -> Consultation {
        let consultation = Consultation(
            patientID: patientID,
            title: title,
            source: source,
            scheduledStart: start,
            scheduledEnd: end,
            location: location,
            notes: notes,
            syncState: .local,
            isDemo: isDemo
        )
        try write {
            try upsertConsultationRow(consultation)
            try log(.consultationCreated, entityType: "consultation", entityID: consultation.id,
                    detail: "\(CadenceFormat.numericDateTime(start)) · \(title)")
        }
        return consultation
    }

    /// Writes the row exactly as given, without touching the audit trail.
    /// Used by synchronisation and by undo, which manage their own logging.
    public func upsertConsultationSilently(_ consultation: Consultation) throws {
        try write { try upsertConsultationRow(consultation) }
    }

    public func updateConsultation(_ consultation: Consultation, detail: String? = nil) throws {
        var updated = consultation
        updated.updatedAt = Date()
        try write {
            try upsertConsultationRow(updated)
            try log(.consultationUpdated, entityType: "consultation", entityID: updated.id,
                    detail: detail ?? updated.title)
        }
    }

    /// The one-gesture action behind [Présent] / [Absent].
    ///
    /// Deliberately does **not** invent `actual_start`: if the user marks presence at
    /// the end of the day, a fabricated arrival time would poison the history.
    public func setStatus(_ status: ConsultationStatus, forConsultation id: UUID, at now: Date = Date()) throws {
        try write {
            guard var consultation = try consultation(id: id) else { return }
            let previous = consultation.status
            consultation.status = status
            consultation.updatedAt = now

            // Starting or ending a session is the only path that records real times.
            if status == .inProgress && consultation.actualStart == nil {
                consultation.actualStart = now
            }
            if status == .attended, consultation.actualStart != nil, consultation.actualEnd == nil {
                consultation.actualEnd = now
            }

            try upsertConsultationRow(consultation)
            try log(.consultationStatusChanged, entityType: "consultation", entityID: id,
                    detail: "\(previous.label) → \(status.label)")
        }
    }

    /// Explicit "Démarrer" — records a real start time.
    public func startConsultation(_ id: UUID, at now: Date = Date()) throws {
        try write {
            guard var consultation = try consultation(id: id) else { return }
            consultation.actualStart = now
            consultation.actualEnd = nil
            consultation.status = .inProgress
            consultation.updatedAt = now
            try upsertConsultationRow(consultation)
            try log(.consultationStarted, entityType: "consultation", entityID: id,
                    detail: "Démarrée à \(CadenceFormat.time(now))")
        }
    }

    /// Explicit "Terminer" — records a real end time and marks the patient present.
    public func endConsultation(_ id: UUID, at now: Date = Date()) throws {
        try write {
            guard var consultation = try consultation(id: id) else { return }
            if consultation.actualStart == nil { consultation.actualStart = consultation.scheduledStart }
            consultation.actualEnd = now
            consultation.status = .attended
            consultation.updatedAt = now
            try upsertConsultationRow(consultation)
            let duration = consultation.actualDuration.map { " · " + CadenceFormat.duration($0) } ?? ""
            try log(.consultationEnded, entityType: "consultation", entityID: id,
                    detail: "Terminée à \(CadenceFormat.time(now))\(duration)")
        }
    }

    /// Clears recorded real times, for when the timer was started by mistake.
    public func clearActualTimes(_ id: UUID) throws {
        try write {
            try database.run(
                "UPDATE consultation SET actual_start = NULL, actual_end = NULL, updated_at = ? WHERE id = ?;",
                [.date(Date()), .uuid(id)]
            )
            try log(.consultationUpdated, entityType: "consultation", entityID: id, detail: "Horaires réels effacés")
        }
    }

    public func assignPatient(_ patientID: UUID?, toConsultation id: UUID, rememberAlias: Bool = true) throws {
        try write {
            guard let consultation = try consultation(id: id) else { return }
            try database.run(
                "UPDATE consultation SET patient_id = ?, updated_at = ? WHERE id = ?;",
                [.optionalUUID(patientID), .date(Date()), .uuid(id)]
            )
            if rememberAlias, let patientID, consultation.source == .calendar {
                // Remember this calendar wording so the next occurrence matches by itself.
                try addAlias(consultation.title, to: patientID)
            }
            let name = try patientID.flatMap { try patient(id: $0)?.displayName } ?? "aucun patient"
            try log(.consultationUpdated, entityType: "consultation", entityID: id, detail: "Patient : \(name)")
        }
    }

    public func deleteConsultation(_ id: UUID) throws {
        try write {
            let consultation = try consultation(id: id)
            try database.run("DELETE FROM consultation WHERE id = ?;", [.uuid(id)])
            try log(.consultationDeleted, entityType: "consultation", entityID: id,
                    detail: consultation.map { "\(CadenceFormat.numericDateTime($0.scheduledStart)) · \($0.title)" } ?? "")
        }
    }

    public func setSyncState(_ state: ConsultationSyncState, forConsultation id: UUID) throws {
        try database.run(
            "UPDATE consultation SET sync_state = ?, updated_at = ? WHERE id = ?;",
            [.text(state.rawValue), .date(Date()), .uuid(id)]
        )
    }

    // MARK: - Internals

    func upsertConsultationRow(_ consultation: Consultation) throws {
        try database.run(
            """
            INSERT INTO consultation (id, patient_id, title, source, external_event_id, external_calendar_id,
                                      occurrence_key, scheduled_start, scheduled_end, actual_start, actual_end,
                                      status, location, notes, sync_state, is_demo, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                patient_id = excluded.patient_id,
                title = excluded.title,
                source = excluded.source,
                external_event_id = excluded.external_event_id,
                external_calendar_id = excluded.external_calendar_id,
                occurrence_key = excluded.occurrence_key,
                scheduled_start = excluded.scheduled_start,
                scheduled_end = excluded.scheduled_end,
                actual_start = excluded.actual_start,
                actual_end = excluded.actual_end,
                status = excluded.status,
                location = excluded.location,
                notes = excluded.notes,
                sync_state = excluded.sync_state,
                is_demo = excluded.is_demo,
                updated_at = excluded.updated_at;
            """,
            [
                .uuid(consultation.id),
                .optionalUUID(consultation.patientID),
                .text(consultation.title),
                .text(consultation.source.rawValue),
                .optionalText(consultation.externalEventID),
                .optionalText(consultation.externalCalendarID),
                .optionalText(consultation.occurrenceKey),
                .date(consultation.scheduledStart),
                .date(consultation.scheduledEnd),
                .optionalDate(consultation.actualStart),
                .optionalDate(consultation.actualEnd),
                .text(consultation.status.rawValue),
                .optionalText(consultation.location),
                .optionalText(consultation.notes),
                .text(consultation.syncState.rawValue),
                .bool(consultation.isDemo),
                .date(consultation.createdAt),
                .date(consultation.updatedAt),
            ]
        )
    }

    static func decodeConsultation(_ row: Row) -> Consultation? {
        guard let id = row.uuid("id"),
              let start = row.date("scheduled_start"),
              let end = row.date("scheduled_end") else { return nil }
        return Consultation(
            id: id,
            patientID: row.uuid("patient_id"),
            title: row.stringValue("title"),
            source: ConsultationSource(rawValue: row.stringValue("source")) ?? .manual,
            externalEventID: row.string("external_event_id"),
            externalCalendarID: row.string("external_calendar_id"),
            occurrenceKey: row.string("occurrence_key"),
            scheduledStart: start,
            scheduledEnd: end,
            actualStart: row.date("actual_start"),
            actualEnd: row.date("actual_end"),
            status: ConsultationStatus(rawValue: row.stringValue("status")) ?? .scheduled,
            location: row.string("location"),
            notes: row.string("notes"),
            syncState: ConsultationSyncState(rawValue: row.stringValue("sync_state")) ?? .local,
            isDemo: row.bool("is_demo"),
            createdAt: row.date("created_at") ?? start,
            updatedAt: row.date("updated_at") ?? start
        )
    }
}
