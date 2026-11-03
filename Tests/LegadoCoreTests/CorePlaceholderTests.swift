import XCTest
@testable import LegadoCore

final class CorePlaceholderTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertFalse(RulePatterns.jsPatternSource.isEmpty)
    }
}
