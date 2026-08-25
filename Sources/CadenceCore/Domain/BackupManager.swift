import Foundation

public struct BackupFile: Identifiable, Hashable, Sendable {
    public let url: URL
    public let createdAt: Date
    public let byteCount: Int

    public var id: URL { url }
    public var name: String { url.lastPathComponent }

    public var sizeDescription: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB]
        return formatter.string(fromByteCount: Int64(byteCount))
    }
}

/// Keeps a rolling set of local snapshots so a bad day never costs the whole history.
///
/// Snapshots are taken with SQLite's online backup API rather than by copying the
/// file: in WAL mode a plain copy can capture a database missing its most recent
/// committed pages.
public final class BackupManager {
    public let directory: URL
    private let store: CadenceStore
    private let fileManager = FileManager.default

    /// How many daily snapshots to keep.
    public static let retention = 14

    public init(store: CadenceStore, directory: URL? = nil) {
        self.store = store
        self.directory = directory
            ?? (store.fileURL?.deletingLastPathComponent() ?? CadenceStore.defaultDirectory())
                .appendingPathComponent("Backups", isDirectory: true)
    }

    /// Takes at most one snapshot per calendar day, on launch. Cheap and invisible.
    @discardableResult
    public func createDailySnapshotIfNeeded(now: Date = Date(), calendar: Calendar = .cadence) throws -> BackupFile? {
        let today = Self.dayStamp(now, calendar: calendar)
        if let last = try store.rawSetting(CadenceStore.SettingKey.lastBackupDay), last == today {
            return nil
        }
        let file = try createSnapshot(named: "cadence-\(today).sqlite3")
        try store.setRawSetting(CadenceStore.SettingKey.lastBackupDay, today)
        try prune()
        return file
    }

    @discardableResult
    public func createSnapshot(named name: String? = nil, now: Date = Date()) throws -> BackupFile {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = name ?? "cadence-\(Self.timestamp(now)).sqlite3"
        let destination = directory.appendingPathComponent(filename)

        // The backup API refuses to overwrite a populated destination cleanly, so
        // start from a clean slate.
        try? fileManager.removeItem(at: destination)
        try store.database.backup(to: destination.path)

        let attributes = try? fileManager.attributesOfItem(atPath: destination.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        try? store.log(.backupCreated, entityType: "backup", entityID: nil, detail: filename)
        return BackupFile(url: destination, createdAt: now, byteCount: size)
    }

    public func snapshots() throws -> [BackupFile] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        return contents
            .filter { $0.pathExtension == "sqlite3" }
            .compactMap { url in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                return BackupFile(
                    url: url,
                    createdAt: values?.contentModificationDate ?? Date.distantPast,
                    byteCount: values?.fileSize ?? 0
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func prune(keeping count: Int = BackupManager.retention) throws {
        let all = try snapshots()
        guard all.count > count else { return }
        for file in all.dropFirst(count) {
            try? fileManager.removeItem(at: file.url)
        }
    }

    /// Replaces the live database with a snapshot.
    ///
    /// The caller must have closed the store first, and must open a fresh one
    /// afterwards — which in practice means the application restarts itself.
    /// A safety copy of the database being replaced is written next to it.
    public static func restore(from snapshot: URL, replacing liveDatabase: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: snapshot.path) else {
            throw CocoaError(.fileNoSuchFile)
        }

        if fileManager.fileExists(atPath: liveDatabase.path) {
            let safety = liveDatabase.deletingLastPathComponent()
                .appendingPathComponent("cadence-avant-restauration.sqlite3")
            try? fileManager.removeItem(at: safety)
            try? fileManager.copyItem(at: liveDatabase, to: safety)
        }

        // The write-ahead log and shared-memory files belong to the database being
        // replaced; leaving them behind would corrupt the restored copy.
        for suffix in ["", "-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: liveDatabase.path + suffix)
            try? fileManager.removeItem(at: sidecar)
        }
        try fileManager.copyItem(at: snapshot, to: liveDatabase)
    }

    static func dayStamp(_ date: Date, calendar: Calendar = .cadence) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func timestamp(_ date: Date, calendar: Calendar = .cadence) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d-%02d-%02d-%02d%02d%02d",
            components.year ?? 0, components.month ?? 0, components.day ?? 0,
            components.hour ?? 0, components.minute ?? 0, components.second ?? 0
        )
    }
}
