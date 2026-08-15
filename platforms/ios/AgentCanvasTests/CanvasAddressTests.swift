import XCTest
@testable import AgentCanvas

final class CanvasAddressTests: XCTestCase {
    func testCanonicalAndAliases() {
        XCTAssertEqual(CanvasAddress.parse("one"), .one)
        XCTAssertEqual(CanvasAddress.parse("twelve"), .twelve)
        XCTAssertEqual(CanvasAddress.parse("12"), .twelve)
        XCTAssertEqual(CanvasAddress.parse("sm-one"), .one)
        XCTAssertEqual(CanvasAddress.parse("md-two"), .two)
        XCTAssertEqual(CanvasAddress.parseFull("lg-three")?.aliasSize, .lg)
        XCTAssertNil(CanvasAddress.parse("sm-four"))
        XCTAssertNil(CanvasAddress.parse("twelve-md"))
        XCTAssertEqual(CanvasAddress.one.widgetKind, "AgentCanvas.one")
        XCTAssertEqual(CanvasAddress.twelve.widgetKind, "AgentCanvas.twelve")
        XCTAssertEqual(CanvasAddress.one.displayName, "One")
        XCTAssertEqual(CanvasAddress.allCases.count, 12)
    }
}
