import XCTest
@testable import AgentCanvas

final class CanvasAddressTests: XCTestCase {
    func testCanonicalIds() {
        XCTAssertEqual(CanvasAddress.parse("one"), .one)
        XCTAssertEqual(CanvasAddress.parse("TWO"), .two)
        XCTAssertEqual(CanvasAddress.parse("3"), .three)
        XCTAssertEqual(CanvasAddress.allCases.map(\.rawValue), ["one", "two", "three"])
        XCTAssertEqual(CanvasAddress.one.widgetKind, "AgentCanvas.one")
        XCTAssertEqual(CanvasAddress.one.displayName, "One")
        XCTAssertEqual(CanvasAddress.one.fileName, "one.json")
    }

    func testLegacyAliases() {
        XCTAssertEqual(CanvasAddress.parse("sm-one"), .one)
        XCTAssertEqual(CanvasAddress.parse("md-two"), .two)
        XCTAssertEqual(CanvasAddress.parse("xl-three"), .three)
        XCTAssertEqual(CanvasAddress.parse("one-sm"), .one)
        XCTAssertEqual(CanvasAddress.parseFull("sm-one")?.aliasSize, .sm)
        XCTAssertEqual(CanvasAddress.parseFull("lg-two")?.aliasSize, .lg)
        XCTAssertNil(CanvasAddress.parseFull("one")?.aliasSize)
    }

    func testWidgetKindParse() {
        XCTAssertEqual(CanvasAddress.from(widgetKind: "AgentCanvas.one"), .one)
        XCTAssertEqual(CanvasAddress.from(widgetKind: "AgentCanvas.md-one"), .one)
        XCTAssertNil(CanvasAddress.from(widgetKind: "Other.one"))
    }

    func testFamilyFromWidgetFamily() {
        XCTAssertEqual(CanvasSize(widgetFamily: .systemSmall), .sm)
        XCTAssertEqual(CanvasSize(widgetFamily: .systemMedium), .md)
        XCTAssertEqual(CanvasSize(widgetFamily: .systemLarge), .lg)
        XCTAssertEqual(CanvasSize(widgetFamily: .systemExtraLarge), .xl)
    }
}
