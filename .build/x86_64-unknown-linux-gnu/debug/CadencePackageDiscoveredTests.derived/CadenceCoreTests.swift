import XCTest
@testable import CadenceCoreTests

fileprivate extension PlaceholderTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__PlaceholderTests = [
        ("testStoreOpens", testStoreOpens)
    ]
}
@available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
func __CadenceCoreTests__allTests() -> [XCTestCaseEntry] {
    return [
        testCase(PlaceholderTests.__allTests__PlaceholderTests)
    ]
}