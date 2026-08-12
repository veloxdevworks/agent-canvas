import XCTest
@testable import AgentCanvas

final class LaunchAtLoginTests: XCTestCase {
    func testStatusNoteRequiresApproval() {
        let note = LaunchAtLogin.statusNote(for: .requiresApproval)
        XCTAssertTrue(note.contains("Login Items"))
    }

    func testStatusNoteClearWhenEnabledOrNotRegistered() {
        XCTAssertEqual(LaunchAtLogin.statusNote(for: .enabled), "")
        XCTAssertEqual(LaunchAtLogin.statusNote(for: .notRegistered), "")
    }

    func testStatusNoteIncludesErrorDescription() {
        struct SampleError: LocalizedError {
            var errorDescription: String? { "sample failure" }
        }
        let note = LaunchAtLogin.statusNote(for: .notRegistered, error: SampleError())
        XCTAssertTrue(note.contains("sample failure"))
    }
}
