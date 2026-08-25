import Foundation

/// A calendar event, reduced to the parts Cadence cares about.
///
/// The platform layer converts `EKEvent` into this; everything that follows —
/// matching, de-duplication, updates, deletions, conflicts — is pure code in the
/// core and is covered by tests. Synchronisation bugs are the classic source of
/// duplicated and silently destroyed appointments, so none of that logic lives in
/// a place that cannot be tested.
public struct CalendarImportEvent: Hashable, Sendable {
    public let eventIdentifier: String
    public let calendarIdentifier: String
    public let title: String
    public let start: Date
    public let end: Date
    public let location: String?
    /// The occurrence's *original* date. For a recurring event every occurrence
    /// shares one identifier, so this is what makes each week a distinct row — and
    /// because it does not move when an occurrence is rescheduled, moving an
    /// appointment updates it instead of duplicating it.
    public let occurrenceDate: Date

    public init(
        eventIdentifier: String,
        calendarIdentifier: String,
        title: String,
        start: Date,
        end: Date,
        location: String? = nil,
        occurrenceDate: Date? = nil
    ) {
        self.eventIdentifier = eventIdentifier
        self.calendarIdentifier = calendarIdentifier
        self.title = title
        self.start = start
        self.end = max(end, start)
        self.location = location
        self.occurrenceDate = occurrenceDate ?? start
    }

    public var occurrenceKey: String {
        "\(eventIdentifier)|\(Int(occurrenceDate.timeIntervalSince1970.rounded()))"
    }
}

/// What a synchronisation pass did, so the interface can say so precisely.
public struct CalendarSyncOutcome: Hashable, Sendable {
    public var inserted = 0
    public var updated = 0
    public var removed = 0
    public var conflicted = 0
    /// Imported but not attached to a patient — shown as "à rattacher".
    public var unmatched = 0
    /// Attached automatically, either from a remembered spelling or a clear name match.
    public var linked = 0

    public var changeCount: Int { inserted + updated + removed + conflicted }

    public var summary: String {
        guard changeCount > 0 else { return "Aucun changement" }
        var parts: [String] = []
        if inserted > 0 { parts.append("\(inserted) ajouté\(inserted > 1 ? "s" : "")") }
        if updated > 0 { parts.append("\(updated) mis à jour") }
        if removed > 0 { parts.append("\(removed) retiré\(removed > 1 ? "s" : "")") }
        if conflicted > 0 { parts.append("\(conflicted) en conflit") }
        return parts.joined(separator: ", ")
    }
}

extension CadenceStore {

    /// Reconciles imported events with what is already stored, for one window and
    /// one set of calendars.
    ///
    /// The rules, in order of importance:
    ///
    /// 1. **Nothing the user recorded is ever destroyed by synchronisation.** A
    ///    consultation that has been marked present or absent, or that carries a
    ///    payment, is never silently rewritten or deleted — it is flagged instead.
    /// 2. An event seen before is matched by occurrence, so a weekly appointment
    ///    updates in place rather than piling up copies.
    /// 3. An untouched appointment whose event has gone is removed quietly; there is
    ///    nothing to preserve and leaving it would be noise.
    @discardableResult
    public func applyCalendarSync(
        events: [CalendarImportEvent],
        calendarIDs: Set<String>,
        window: DateRange,
        now: Date = Date()
    ) throws -> CalendarSyncOutcome {
        var outcome = CalendarSyncOutcome()
        let roster = try allPatients(includeArchived: true)

        try write {
            let existing = try consultations(in: window)
            let existingByKey = Dictionary(
                existing.compactMap { consultation -> (String, Consultation)? in
                    guard let key = consultation.occurrenceKey else { return nil }
                    return (key, consultation)
                },
                uniquingKeysWith: { first, _ in first }
            )

            var seenKeys: Set<String> = []

            for event in events where calendarIDs.contains(event.calendarIdentifier) {
                seenKeys.insert(event.occurrenceKey)

                if let current = existingByKey[event.occurrenceKey] {
                    try reconcile(current, with: event, outcome: &outcome)
                } else {
                    try insert(event, roster: roster, outcome: &outcome)
                }
            }

            // Anything that came from one of these calendars and is no longer there.
            for consultation in existing {
                guard consultation.source == .calendar,
                      let calendarID = consultation.externalCalendarID,
                      calendarIDs.contains(calendarID),
                      let key = consultation.occurrenceKey,
                      !seenKeys.contains(key) else { continue }
                try retire(consultation, outcome: &outcome)
            }

            try log(.calendarSynchronised, entityType: "calendar", entityID: nil,
                    detail: outcome.summary, at: now)
        }
        return outcome
    }

    private func insert(_ event: CalendarImportEvent, roster: [Patient], outcome: inout CalendarSyncOutcome) throws {
        let match = try matchPatient(forTitle: event.title, among: roster)
        let consultation = Consultation(
            patientID: match.patientID,
            title: event.title,
            source: .calendar,
            externalEventID: event.eventIdentifier,
            externalCalendarID: event.calendarIdentifier,
            occurrenceKey: event.occurrenceKey,
            scheduledStart: event.start,
            scheduledEnd: event.end,
            location: event.location,
            syncState: .synced
        )
        try upsertConsultationRow(consultation)
        outcome.inserted += 1
        if match.patientID != nil { outcome.linked += 1 } else { outcome.unmatched += 1 }
    }

    private func reconcile(
        _ current: Consultation,
        with event: CalendarImportEvent,
        outcome: inout CalendarSyncOutcome
    ) throws {
        let timesChanged = current.scheduledStart != event.start || current.scheduledEnd != event.end
        let detailsChanged = current.title != event.title || current.location != event.location
        guard timesChanged || detailsChanged || current.syncState == .orphaned else { return }

        let hasPayment = try !payments(forConsultation: current.id).isEmpty
        let isProtected = current.status.isLockedAgainstSync || hasPayment

        if timesChanged && isProtected {
            // The user has already recorded something against this slot. Rewriting it
            // would rewrite history, so Cadence flags it and lets them decide.
            if current.syncState != .conflict {
                try setSyncState(.conflict, forConsultation: current.id)
                outcome.conflicted += 1
            }
            return
        }

        var updated = current
        updated.scheduledStart = event.start
        updated.scheduledEnd = event.end
        updated.title = event.title
        updated.location = event.location
        updated.externalCalendarID = event.calendarIdentifier
        updated.externalEventID = event.eventIdentifier
        updated.syncState = .synced
        updated.updatedAt = Date()
        try upsertConsultationRow(updated)
        outcome.updated += 1
    }

    private func retire(_ consultation: Consultation, outcome: inout CalendarSyncOutcome) throws {
        let hasPayment = try !payments(forConsultation: consultation.id).isEmpty
        let isUntouched = !consultation.status.isResolved
            && consultation.status != .inProgress
            && !hasPayment
            && consultation.notes == nil

        if isUntouched {
            try database.run("DELETE FROM consultation WHERE id = ?;", [.uuid(consultation.id)])
            outcome.removed += 1
        } else if consultation.syncState != .orphaned {
            try setSyncState(.orphaned, forConsultation: consultation.id)
            outcome.conflicted += 1
        }
    }

    /// Called when the user switches a calendar off: untouched appointments from it
    /// disappear, anything they worked on is kept and marked.
    @discardableResult
    public func purgeCalendar(_ calendarID: String) throws -> Int {
        var removed = 0
        try write {
            let rows = try database.query(
                "SELECT * FROM consultation WHERE external_calendar_id = ?;", [.text(calendarID)]
            ).compactMap(Self.decodeConsultation)

            for consultation in rows {
                let hasPayment = try !payments(forConsultation: consultation.id).isEmpty
                if !consultation.status.isResolved && !hasPayment && consultation.status != .inProgress {
                    try database.run("DELETE FROM consultation WHERE id = ?;", [.uuid(consultation.id)])
                    removed += 1
                } else {
                    try setSyncState(.orphaned, forConsultation: consultation.id)
                }
            }
        }
        return removed
    }

    /// Accepts a flagged change: the consultation stops being in conflict and takes
    /// the calendar's version. Only the user can ask for this.
    public func resolveConflict(_ consultationID: UUID, keepingCalendarVersion: Bool) throws {
        guard let consultation = try consultation(id: consultationID) else { return }
        if keepingCalendarVersion {
            try setSyncState(.synced, forConsultation: consultationID)
        } else {
            // Keep what is on screen and stop treating the event as authoritative.
            var updated = consultation
            updated.syncState = .local
            updated.occurrenceKey = nil
            updated.source = .manual
            updated.updatedAt = Date()
            try upsertConsultationSilently(updated)
        }
    }
}
