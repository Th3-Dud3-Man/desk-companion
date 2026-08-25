import Foundation

/// The application's single door to persisted state.
///
/// Everything the user does goes through here, always inside a transaction, so the
/// interface can confirm an action only once it is durably on disk.
public final class CadenceStore {
    public let database: SQLiteDatabase
    public let fileURL: URL?

    public init(database: SQLiteDatabase, fileURL: URL? = nil) throws {
        self.database = database
        self.fileURL = fileURL
        try Schema.migrate(database)
        try seedDefaultSettingsIfNeeded()
    }

    /// Opens (creating if needed) the database at `url`, making parent folders.
    public static func open(at url: URL) throws -> CadenceStore {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let database = try SQLiteDatabase(path: url.path)
        return try CadenceStore(database: database, fileURL: url)
    }

    /// The standard location: `~/Library/Application Support/Cadence/cadence.sqlite3`.
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cadence")
        return base.appendingPathComponent("Cadence", isDirectory: true)
    }

    public static func defaultFileURL() -> URL {
        defaultDirectory().appendingPathComponent("cadence.sqlite3")
    }

    public static func inMemory() throws -> CadenceStore {
        try CadenceStore(database: try SQLiteDatabase.inMemory())
    }

    public func close() { database.close() }

    /// Runs `body` in one transaction; nothing is visible until it returns.
    @discardableResult
    public func write<T>(_ body: () throws -> T) throws -> T {
        try database.transaction(body)
    }

    // MARK: - Bookkeeping

    /// Appends to the audit trail. Called by every mutating operation.
    func log(_ kind: ActionKind, entityType: String, entityID: UUID?, detail: String, at: Date = Date()) throws {
        try database.run(
            """
            INSERT INTO action_log (id, entity_type, entity_id, kind, detail, at)
            VALUES (?, ?, ?, ?, ?, ?);
            """,
            [.uuid(UUID()), .text(entityType), .optionalUUID(entityID), .text(kind.rawValue), .text(detail), .date(at)]
        )
    }

    public func recentActions(limit: Int = 50) throws -> [ActionLogEntry] {
        try database.query(
            "SELECT * FROM action_log ORDER BY at DESC, rowid DESC LIMIT ?;",
            [.int(limit)]
        ).compactMap(Self.decodeAction)
    }

    public func actions(forEntity id: UUID, limit: Int = 100) throws -> [ActionLogEntry] {
        try database.query(
            "SELECT * FROM action_log WHERE entity_id = ? ORDER BY at DESC, rowid DESC LIMIT ?;",
            [.uuid(id), .int(limit)]
        ).compactMap(Self.decodeAction)
    }

    static func decodeAction(_ row: Row) -> ActionLogEntry? {
        guard let id = row.uuid("id"),
              let kind = ActionKind(rawValue: row.stringValue("kind")),
              let at = row.date("at") else { return nil }
        return ActionLogEntry(
            id: id,
            entityType: row.stringValue("entity_type"),
            entityID: row.uuid("entity_id"),
            kind: kind,
            detail: row.stringValue("detail"),
            at: at
        )
    }
}
