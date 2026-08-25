import XCTest
@testable import CadenceCore

final class PlaceholderTests: XCTestCase {
    func testStoreOpens() throws {
        let store = try CadenceStore.inMemory()
        XCTAssertEqual(try store.allPatients().count, 0)
        _ = store
    }
}
