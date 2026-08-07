import XCTest
@testable import AgentCanvasiOS

/// Packing goldens shared with Rust (`schema/conformance`).
final class ContentClipConformanceTests: XCTestCase {
    func testConformanceGoldens() throws {
        let root = schemaRoot()
        let dir = root.appendingPathComponent("conformance")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        XCTAssertGreaterThanOrEqual(files.count, 8, "expected conformance goldens")

        for file in files {
            let data = try Data(contentsOf: file)
            let caseFile = try JSONDecoder().decode(ConformanceCase.self, from: data)
            let fixtureURL = root.appendingPathComponent(caseFile.fixture)
            let fixtureData = try Data(contentsOf: fixtureURL)
            let doc = try JSONDecoder.canvas.decode(CanvasDocument.self, from: fixtureData)
            let size = try XCTUnwrap(CanvasSize(rawValue: caseFile.size))
            let got = ContentClip.apply(document: doc, size: size)

            XCTAssertEqual(got.shownIndices, caseFile.expected.shownIndices, file.lastPathComponent)
            XCTAssertEqual(got.droppedTypes, caseFile.expected.droppedTypes, file.lastPathComponent)
            XCTAssertEqual(got.truncated, caseFile.expected.truncated, file.lastPathComponent)
            XCTAssertEqual(got.listItemsShown, caseFile.expected.listItemsShown, file.lastPathComponent)
            XCTAssertEqual(got.listItemsTotal, caseFile.expected.listItemsTotal, file.lastPathComponent)
            XCTAssertEqual(
                got.shownIndices.count,
                caseFile.expected.shownSectionCount,
                file.lastPathComponent
            )
            XCTAssertEqual(
                got.droppedTypes.count,
                caseFile.expected.droppedSectionCount,
                file.lastPathComponent
            )
            XCTAssertEqual(
                got.chartHeightScale,
                CGFloat(caseFile.expected.chartHeightScale),
                accuracy: 0.0001,
                file.lastPathComponent
            )
            XCTAssertEqual(got.cover, caseFile.expected.cover ?? false, file.lastPathComponent)
        }
    }

    private func schemaRoot() -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        // …/platforms/ios/AgentCanvasTests/… → repo root
        return thisFile
            .deletingLastPathComponent() // AgentCanvasTests
            .deletingLastPathComponent() // ios
            .deletingLastPathComponent() // platforms
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("schema")
    }
}

private struct ConformanceCase: Decodable {
    var fixture: String
    var size: String
    var expected: Expected

    struct Expected: Decodable {
        var shownIndices: [Int]
        var droppedTypes: [String]
        var truncated: Bool
        var listItemsShown: Int
        var listItemsTotal: Int
        var shownSectionCount: Int
        var droppedSectionCount: Int
        var chartHeightScale: Double
        var cover: Bool?
    }
}

private extension JSONDecoder {
    static let canvas: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
