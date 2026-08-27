import Foundation

/// Ordered schema migrations. Each entry is applied exactly once, inside a
/// transaction, and `PRAGMA user_version` records how far the file has come.
///
/// Never edit a migration that has shipped — append a new one.
enum Schema {

    static let migrations: [(version: Int32, sql: String)] = [
        (1, """
        CREATE TABLE patient (
            id                   TEXT PRIMARY KEY NOT NULL,
            display_name         TEXT NOT NULL,
            first_name           TEXT,
            last_name            TEXT,
            email                TEXT,
            phone                TEXT,
            colour_seed          INTEGER NOT NULL DEFAULT 0,
            notes                TEXT,
            default_amount_cents INTEGER,
            default_method       TEXT,
            archived             INTEGER NOT NULL DEFAULT 0,
            is_demo              INTEGER NOT NULL DEFAULT 0,
            created_at           INTEGER NOT NULL,
            updated_at           INTEGER NOT NULL
        );
        CREATE INDEX patient_by_name ON patient (archived, display_name);

        -- Alternative spellings seen in calendar titles, so a patient is matched
        -- again next week without asking.
        CREATE TABLE patient_alias (
            patient_id TEXT NOT NULL REFERENCES patient (id) ON DELETE CASCADE,
            alias      TEXT NOT NULL,
            PRIMARY KEY (patient_id, alias)
        );
        CREATE INDEX patient_alias_lookup ON patient_alias (alias);

        CREATE TABLE consultation (
            id                   TEXT PRIMARY KEY NOT NULL,
            patient_id           TEXT REFERENCES patient (id) ON DELETE SET NULL,
            title                TEXT NOT NULL,
            source               TEXT NOT NULL,
            external_event_id    TEXT,
            external_calendar_id TEXT,
            occurrence_key       TEXT UNIQUE,
            scheduled_start      INTEGER NOT NULL,
            scheduled_end        INTEGER NOT NULL,
            actual_start         INTEGER,
            actual_end           INTEGER,
            status               TEXT NOT NULL,
            location             TEXT,
            notes                TEXT,
            sync_state           TEXT NOT NULL,
            is_demo              INTEGER NOT NULL DEFAULT 0,
            created_at           INTEGER NOT NULL,
            updated_at           INTEGER NOT NULL
        );
        CREATE INDEX consultation_by_start   ON consultation (scheduled_start);
        CREATE INDEX consultation_by_patient ON consultation (patient_id, scheduled_start);
        CREATE INDEX consultation_by_event   ON consultation (external_event_id);

        CREATE TABLE payment (
            id              TEXT PRIMARY KEY NOT NULL,
            consultation_id TEXT REFERENCES consultation (id) ON DELETE SET NULL,
            patient_id      TEXT NOT NULL REFERENCES patient (id) ON DELETE CASCADE,
            amount_cents    INTEGER NOT NULL,
            currency        TEXT NOT NULL DEFAULT 'EUR',
            method          TEXT NOT NULL,
            paid_at         INTEGER NOT NULL,
            note            TEXT,
            is_demo         INTEGER NOT NULL DEFAULT 0,
            created_at      INTEGER NOT NULL
        );
        CREATE INDEX payment_by_patient      ON payment (patient_id, paid_at DESC);
        CREATE INDEX payment_by_date         ON payment (paid_at);
        CREATE INDEX payment_by_consultation ON payment (consultation_id);

        CREATE TABLE action_log (
            id          TEXT PRIMARY KEY NOT NULL,
            entity_type TEXT NOT NULL,
            entity_id   TEXT,
            kind        TEXT NOT NULL,
            detail      TEXT NOT NULL,
            at          INTEGER NOT NULL
        );
        CREATE INDEX action_log_by_entity ON action_log (entity_id, at DESC);
        CREATE INDEX action_log_by_date   ON action_log (at DESC);

        CREATE TABLE calendar_subscription (
            id           TEXT PRIMARY KEY NOT NULL,
            title        TEXT NOT NULL,
            colour_hex   TEXT,
            account_name TEXT,
            enabled      INTEGER NOT NULL DEFAULT 0,
            last_sync_at INTEGER,
            last_status  TEXT NOT NULL DEFAULT 'never',
            last_message TEXT
        );

        CREATE TABLE setting (
            key   TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL
        );
        """),

        // A payment can be recorded before the money arrives — a transfer announced
        // in the session, a cheque waiting to be paid in. `settled_at` is null until
        // it actually lands. Everything recorded before this migration existed is
        // treated as received, which is what it meant at the time.
        (2, """
        ALTER TABLE payment ADD COLUMN settled_at INTEGER;
        UPDATE payment SET settled_at = paid_at;
        CREATE INDEX payment_pending ON payment (paid_at) WHERE settled_at IS NULL;
        """)
    ]

    static var currentVersion: Int32 { migrations.last?.version ?? 0 }

    /// Brings `database` up to `currentVersion`, applying only what is missing.
    static func migrate(_ database: SQLiteDatabase) throws {
        // Pragmas first: foreign keys must be on before any statement that relies
        // on them, and WAL has to be set outside a transaction.
        try database.execute("PRAGMA journal_mode = WAL;")
        try database.execute("PRAGMA synchronous = FULL;")
        try database.execute("PRAGMA foreign_keys = ON;")

        let installed = database.userVersion
        for migration in migrations where migration.version > installed {
            try database.transaction {
                try database.execute(migration.sql)
            }
            database.userVersion = migration.version
        }
    }
}
