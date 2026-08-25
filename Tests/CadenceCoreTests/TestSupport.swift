import XCTest
import Foundation
@testable import CadenceCore

/// Shared scaffolding: a fixed time zone so results never depend on the machine, and
/// a temporary on-disk store for the tests that must survive a close and reopen.
class CadenceTestCase: XCTestCase {

    var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        Calendar.cadence.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cadence-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    var databaseURL: URL { temporaryDirectory.appendingPathComponent("cadence.sqlite3") }

    func makeFileStore() throws -> CadenceStore {
        try CadenceStore.open(at: databaseURL)
    }

    func makeMemoryStore() throws -> CadenceStore {
        try CadenceStore.inMemory()
    }

    /// French currency formatting uses a narrow no-break space, and which one it
    /// picks depends on the ICU version underneath. Comparisons collapse them.
    func plainSpaces(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{2009}", with: " ")
    }

    /// A date on a known day, in the pinned time zone.
    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.cadence.date(from: components)!
    }
}
