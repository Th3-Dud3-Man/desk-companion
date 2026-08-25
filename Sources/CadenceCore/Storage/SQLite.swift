import Foundation
import CSQLite

/// A value that can cross the SQLite boundary.
public enum SQLValue: Equatable, Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    public static func int(_ value: Int) -> SQLValue { .integer(Int64(value)) }
    public static func bool(_ value: Bool) -> SQLValue { .integer(value ? 1 : 0) }
    public static func date(_ value: Date) -> SQLValue { .integer(Int64(value.timeIntervalSince1970.rounded())) }
    public static func uuid(_ value: UUID) -> SQLValue { .text(value.uuidString.lowercased()) }

    public static func optionalText(_ value: String?) -> SQLValue { value.map { .text($0) } ?? .null }
    public static func optionalDate(_ value: Date?) -> SQLValue { value.map { .date($0) } ?? .null }
    public static func optionalUUID(_ value: UUID?) -> SQLValue { value.map { .uuid($0) } ?? .null }
    public static func optionalInt(_ value: Int?) -> SQLValue { value.map { .int($0) } ?? .null }
}

public struct SQLiteError: Error, CustomStringConvertible {
    public let code: Int32
    public let message: String
    public let sql: String?

    public var description: String {
        if let sql, !sql.isEmpty {
            return "SQLite error \(code): \(message) — while running: \(sql)"
        }
        return "SQLite error \(code): \(message)"
    }
}

/// One row of a result set, addressed by column name.
public struct Row {
    private let indexByName: [String: Int]
    private let values: [SQLValue]

    init(indexByName: [String: Int], values: [SQLValue]) {
        self.indexByName = indexByName
        self.values = values
    }

    public func raw(_ column: String) -> SQLValue {
        guard let index = indexByName[column], index < values.count else { return .null }
        return values[index]
    }

    public func isNull(_ column: String) -> Bool { raw(column) == .null }

    public func int64(_ column: String) -> Int64? {
        switch raw(column) {
        case .integer(let value): return value
        case .real(let value): return Int64(value)
        case .text(let value): return Int64(value)
        default: return nil
        }
    }

    public func int(_ column: String) -> Int? { int64(column).map(Int.init) }
    public func intValue(_ column: String, default fallback: Int = 0) -> Int { int(column) ?? fallback }

    public func double(_ column: String) -> Double? {
        switch raw(column) {
        case .real(let value): return value
        case .integer(let value): return Double(value)
        case .text(let value): return Double(value)
        default: return nil
        }
    }

    public func doubleValue(_ column: String, default fallback: Double = 0) -> Double { double(column) ?? fallback }

    public func string(_ column: String) -> String? {
        switch raw(column) {
        case .text(let value): return value
        case .integer(let value): return String(value)
        case .real(let value): return String(value)
        default: return nil
        }
    }

    public func stringValue(_ column: String, default fallback: String = "") -> String { string(column) ?? fallback }

    public func bool(_ column: String) -> Bool { (int64(column) ?? 0) != 0 }

    public func date(_ column: String) -> Date? {
        guard let seconds = int64(column) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    public func uuid(_ column: String) -> UUID? {
        guard let text = string(column) else { return nil }
        return UUID(uuidString: text)
    }

    public func data(_ column: String) -> Data? {
        if case .blob(let value) = raw(column) { return value }
        return nil
    }
}

/// A thin, fully synchronous wrapper around the system SQLite.
///
/// Deliberately small: the application needs prepared statements, typed rows,
/// nested transactions and online backup — nothing more. Every entry point takes
/// a recursive lock so the database can be shared across threads, and the handle
/// is opened with `SQLITE_OPEN_FULLMUTEX` as a second line of defence.
public final class SQLiteDatabase {
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()
    private var savepointDepth = 0
    private var statementCache: [String: OpaquePointer] = [:]

    public let path: String

    /// Passing `SQLITE_TRANSIENT` requires this bit pattern; SQLite copies the buffer.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(path: String) throws {
        self.path = path
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        var handle: OpaquePointer?
        let status = sqlite3_open_v2(path, &handle, flags, nil)
        guard status == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unable to open database"
            sqlite3_close_v2(handle)
            throw SQLiteError(code: status, message: message, sql: nil)
        }
        self.handle = handle
        sqlite3_busy_timeout(handle, 5_000)
    }

    /// In-memory database, used by the test suite.
    public static func inMemory() throws -> SQLiteDatabase {
        try SQLiteDatabase(path: ":memory:")
    }

    deinit {
        for statement in statementCache.values { sqlite3_finalize(statement) }
        if let handle { sqlite3_close_v2(handle) }
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        for statement in statementCache.values { sqlite3_finalize(statement) }
        statementCache.removeAll()
        if let handle { sqlite3_close_v2(handle) }
        handle = nil
    }

    // MARK: - Execution

    /// Runs one or more statements with no parameters and no results.
    public func execute(_ sql: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let handle else { throw SQLiteError(code: SQLITE_MISUSE, message: "database is closed", sql: sql) }
        var errorPointer: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(handle, sql, nil, nil, &errorPointer)
        if status != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(handle))
            sqlite3_free(errorPointer)
            throw SQLiteError(code: status, message: message, sql: sql)
        }
        sqlite3_free(errorPointer)
    }

    /// Runs a parameterised statement that returns no rows.
    @discardableResult
    public func run(_ sql: String, _ parameters: [SQLValue] = []) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        let statement = try cachedStatement(sql)
        defer { sqlite3_reset(statement); sqlite3_clear_bindings(statement) }
        try bind(parameters, to: statement, sql: sql)
        let status = sqlite3_step(statement)
        guard status == SQLITE_DONE || status == SQLITE_ROW else {
            throw error(status, sql: sql)
        }
        return Int(sqlite3_changes(handle))
    }

    /// Runs a parameterised query and materialises every row.
    public func query(_ sql: String, _ parameters: [SQLValue] = []) throws -> [Row] {
        lock.lock()
        defer { lock.unlock() }
        let statement = try cachedStatement(sql)
        defer { sqlite3_reset(statement); sqlite3_clear_bindings(statement) }
        try bind(parameters, to: statement, sql: sql)

        let columnCount = Int(sqlite3_column_count(statement))
        var indexByName: [String: Int] = [:]
        indexByName.reserveCapacity(columnCount)
        for index in 0..<columnCount {
            if let name = sqlite3_column_name(statement, Int32(index)) {
                indexByName[String(cString: name)] = index
            }
        }

        var rows: [Row] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw error(status, sql: sql) }

            var values: [SQLValue] = []
            values.reserveCapacity(columnCount)
            for index in 0..<columnCount {
                values.append(columnValue(statement, Int32(index)))
            }
            rows.append(Row(indexByName: indexByName, values: values))
        }
        return rows
    }

    /// Convenience for aggregate queries that return exactly one scalar.
    public func scalarInt(_ sql: String, _ parameters: [SQLValue] = []) throws -> Int {
        guard let row = try query(sql, parameters).first else { return 0 }
        return row.int64("value").map(Int.init) ?? 0
    }

    // MARK: - Transactions

    /// Executes `body` inside a savepoint. Nesting is supported: only the outermost
    /// scope commits, and any thrown error rolls back exactly its own scope.
    @discardableResult
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }

        let name = "cadence_sp_\(savepointDepth)"
        try execute("SAVEPOINT \(name);")
        savepointDepth += 1
        do {
            let result = try body()
            savepointDepth -= 1
            try execute("RELEASE SAVEPOINT \(name);")
            return result
        } catch {
            savepointDepth -= 1
            // Roll the savepoint back and release it; a failure here would mask the
            // original error, so it is deliberately swallowed.
            try? execute("ROLLBACK TO SAVEPOINT \(name); RELEASE SAVEPOINT \(name);")
            throw error
        }
    }

    // MARK: - Schema version

    public var userVersion: Int32 {
        get {
            (try? query("PRAGMA user_version;").first?.int64("user_version")).flatMap { $0 }.map(Int32.init) ?? 0
        }
        set {
            try? execute("PRAGMA user_version = \(newValue);")
        }
    }

    // MARK: - Online backup

    /// Copies the live database to `destinationPath` using SQLite's backup API.
    ///
    /// A plain file copy is unsafe in WAL mode — it can capture a database whose
    /// committed pages still live in the write-ahead log. This is the supported way.
    public func backup(to destinationPath: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let source = handle else {
            throw SQLiteError(code: SQLITE_MISUSE, message: "database is closed", sql: nil)
        }

        var destination: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let openStatus = sqlite3_open_v2(destinationPath, &destination, flags, nil)
        guard openStatus == SQLITE_OK, let destination else {
            let message = destination.map { String(cString: sqlite3_errmsg($0)) } ?? "unable to open backup destination"
            sqlite3_close_v2(destination)
            throw SQLiteError(code: openStatus, message: message, sql: nil)
        }
        defer { sqlite3_close_v2(destination) }

        guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
            throw SQLiteError(code: sqlite3_errcode(destination),
                              message: String(cString: sqlite3_errmsg(destination)),
                              sql: nil)
        }
        let stepStatus = sqlite3_backup_step(backup, -1)
        let finishStatus = sqlite3_backup_finish(backup)
        guard stepStatus == SQLITE_DONE else {
            throw SQLiteError(code: stepStatus, message: "backup did not complete", sql: nil)
        }
        guard finishStatus == SQLITE_OK else {
            throw SQLiteError(code: finishStatus, message: "backup could not be finalised", sql: nil)
        }
    }

    // MARK: - Internals

    private func cachedStatement(_ sql: String) throws -> OpaquePointer {
        if let cached = statementCache[sql] { return cached }
        guard let handle else { throw SQLiteError(code: SQLITE_MISUSE, message: "database is closed", sql: sql) }
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard status == SQLITE_OK, let statement else {
            throw SQLiteError(code: status, message: String(cString: sqlite3_errmsg(handle)), sql: sql)
        }
        statementCache[sql] = statement
        return statement
    }

    private func bind(_ parameters: [SQLValue], to statement: OpaquePointer, sql: String) throws {
        let expected = Int(sqlite3_bind_parameter_count(statement))
        guard expected == parameters.count else {
            throw SQLiteError(code: SQLITE_MISUSE,
                              message: "expected \(expected) parameter(s), received \(parameters.count)",
                              sql: sql)
        }
        for (offset, value) in parameters.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32
            switch value {
            case .null:
                status = sqlite3_bind_null(statement, index)
            case .integer(let number):
                status = sqlite3_bind_int64(statement, index, number)
            case .real(let number):
                status = sqlite3_bind_double(statement, index, number)
            case .text(let text):
                status = sqlite3_bind_text(statement, index, text, -1, Self.transient)
            case .blob(let data):
                status = data.isEmpty
                    ? sqlite3_bind_zeroblob(statement, index, 0)
                    : data.withUnsafeBytes { buffer in
                        sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), Self.transient)
                    }
            }
            guard status == SQLITE_OK else { throw error(status, sql: sql) }
        }
    }

    private func columnValue(_ statement: OpaquePointer, _ index: Int32) -> SQLValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            guard let pointer = sqlite3_column_text(statement, index) else { return .null }
            return .text(String(cString: pointer))
        case SQLITE_BLOB:
            let length = Int(sqlite3_column_bytes(statement, index))
            guard length > 0, let pointer = sqlite3_column_blob(statement, index) else { return .blob(Data()) }
            return .blob(Data(bytes: pointer, count: length))
        default:
            return .null
        }
    }

    private func error(_ code: Int32, sql: String) -> SQLiteError {
        let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
        return SQLiteError(code: code, message: message, sql: sql)
    }
}
