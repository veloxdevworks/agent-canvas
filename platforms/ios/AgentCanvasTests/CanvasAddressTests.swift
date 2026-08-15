import XCTest
@testable import AgentCanvas

final class CanvasAddressTests: XCTestCase {
    func testCanonicalAndAliases() {
        XCTAssertEqual(CanvasAddress.parse("one"), .one)
        XCTAssertEqual(CanvasAddress.parse("sm-one"), .one)
        XCTAssertEqual(CanvasAddress.parse("md-two"), .two)
        XCTAssertEqual(CanvasAddress.parseFull("lg-three")?.aliasSize, .lg)
        XCTAssertEqual(CanvasAddress.one.widgetKind, "AgentCanvas.one")
        XCTAssertEqual(CanvasAddress.one.displayName, "One")
    }
}
