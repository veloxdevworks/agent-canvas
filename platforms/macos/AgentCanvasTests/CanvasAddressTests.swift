import XCTest
@testable import AgentCanvas

final class CanvasAddressTests: XCTestCase {
    func testCanonicalIds() {
        XCTAssertEqual(CanvasAddress.parse("one"), .one)
        XCTAssertEqual(CanvasAddress.parse("TWO"), .two)
        XCTAssertEqual(CanvasAddress.parse("3"), .three)
        XCTAssertEqual(CanvasAddress.parse("twelve"), .twelve)
        XCTAssertEqual(CanvasAddress.parse("12"), .twelve)
        XCTAssertEqual(CanvasAddress.parse("4"), .four)
        XCTAssertEqual(CanvasAddress.allCases.map(\.rawValue), [
            "one", "two", "three", "four", "five", "six",
            "seven", "eight", "nine", "ten", "eleven", "twelve",
        ])
        XCTAssertEqual(CanvasAddress.one.widgetKind, "AgentCanvas.one")
        XCTAssertEqual(CanvasAddress.twelve.widgetKind, "AgentCanvas.twelve")
        XCTAssertEqual(CanvasAddress.one.displayName, "One")
        XCTAssertEqual(CanvasAddress.twelve.displayName, "Twelve")
        XCTAssertEqual(CanvasAddress.twelve.fileName, "twelve.json")
    }

    func testLegacyAliasesOnlyForFirstThree() {
        XCTAssertEqual(CanvasAddress.parse("sm-one"), .one)
        XCTAssertEqual(CanvasAddress.parse("md-two"), .two)
        XCTAssertEqual(CanvasAddress.parse("xl-three"), .three)
        XCTAssertEqual(CanvasAddress.parse("one-sm"), .one)
        XCTAssertEqual(CanvasAddress.parseFull("sm-one")?.aliasSize, .sm)
        XCTAssertEqual(CanvasAddress.parseFull("lg-two")?.aliasSize, .lg)
        XCTAssertNil(CanvasAddress.parseFull("one")?.aliasSize)
        XCTAssertNil(CanvasAddress.parse("sm-four"))
        XCTAssertNil(CanvasAddress.parse("md-twelve"))
        XCTAssertNil(CanvasAddress.parse("four-sm"))
        XCTAssertNil(CanvasAddress.parse("twelve-xl"))
        XCTAssertTrue(CanvasAddress.one.legacyFileNames.contains("md-one.json"))
        XCTAssertTrue(CanvasAddress.twelve.legacyFileNames.isEmpty)
    }

    func testWidgetKindParse() {
        XCTAssertEqual(CanvasAddress.from(widgetKind: "AgentCanvas.one"), .one)
        XCTAssertEqual(CanvasAddress.from(widgetKind: "AgentCanvas.twelve"), .twelve)
        XCTAssertEqual(CanvasAddress.from(widgetKind: "AgentCanvas.md-one"), .one)
        XCTAssertNil(CanvasAddress.from(widgetKind: "AgentCanvas.sm-four"))
        XCTAssertNil(CanvasAddress.from(widgetKind: "Other.one"))
    }

    func testFamilyFromWidgetFamily() {
        XCTAssertEqual(CanvasSize(widgetFamily: .systemSmall), .sm)
        XCTAssertEqual(CanvasSize(widgetFamily: .systemMedium), .md)
        XCTAssertEqual(CanvasSize(widgetFamily: .systemLarge), .lg)
        XCTAssertEqual(CanvasSize(widgetFamily: .systemExtraLarge), .xl)
    }
}
