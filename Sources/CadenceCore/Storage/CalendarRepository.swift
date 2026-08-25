import Foundation

extension CadenceStore {

    public func calendarSubscriptions() throws -> [CalendarSubscription] {
        try database.query("SELECT * FROM calendar_subscription ORDER BY account_name, title;")
            .compactMap(Self.decodeSubscription)
    }

    public func enabledCalendarIDs() throws -> [String] {
        try database.query("SELECT id FROM calendar_subscription WHERE enabled = 1;")
            .compactMap { $0.string("id") }
    }

    /// Merges the calendars macOS currently reports with what we already knew,
    /// preserving the user's enabled/disabled choices and dropping calendars that
    /// no longer exist.
    public func reconcileCalendars(_ discovered: [CalendarSubscription]) throws {
        try write {
            let existing = try calendarSubscriptions()
            let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

            for calendar in discovered {
                let previous = existingByID[calendar.id]
                try database.run(
                    """
                    INSERT INTO calendar_subscription (id, title, colour_hex, account_name, enabled,
                                                       last_sync_at, last_status, last_message)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        title = excluded.title,
                        colour_hex = excluded.colour_hex,
                        account_name = excluded.account_name;
                    """,
                    [
                        .text(calendar.id),
                        .text(calendar.title),
                        .optionalText(calendar.colourHex),
                        .optionalText(calendar.accountName),
                        .bool(previous?.isEnabled ?? calendar.isEnabled),
                        .optionalDate(previous?.lastSyncAt),
                        .text((previous?.lastStatus ?? .never).rawValue),
                        .optionalText(previous?.lastMessage),
                    ]
                )
            }

            let discoveredIDs = Set(discovered.map(\.id))
            for stale in existing where !discoveredIDs.contains(stale.id) {
                try database.run("DELETE FROM calendar_subscription WHERE id = ?;", [.text(stale.id)])
            }
        }
    }

    public func setCalendarEnabled(_ id: String, enabled: Bool) throws {
        try database.run("UPDATE calendar_subscription SET enabled = ? WHERE id = ?;", [.bool(enabled), .text(id)])
    }

    public func updateCalendarStatus(
        _ id: String,
        status: CalendarSyncStatus,
        message: String? = nil,
        syncedAt: Date? = nil
    ) throws {
        try database.run(
            """
            UPDATE calendar_subscription
            SET last_status = ?, last_message = ?, last_sync_at = COALESCE(?, last_sync_at)
            WHERE id = ?;
            """,
            [.text(status.rawValue), .optionalText(message), .optionalDate(syncedAt), .text(id)]
        )
    }

    static func decodeSubscription(_ row: Row) -> CalendarSubscription? {
        guard let id = row.string("id") else { return nil }
        return CalendarSubscription(
            id: id,
            title: row.stringValue("title", default: "Calendrier"),
            colourHex: row.string("colour_hex"),
            accountName: row.string("account_name"),
            isEnabled: row.bool("enabled"),
            lastSyncAt: row.date("last_sync_at"),
            lastStatus: CalendarSyncStatus(rawValue: row.stringValue("last_status", default: "never")) ?? .never,
            lastMessage: row.string("last_message")
        )
    }
}
