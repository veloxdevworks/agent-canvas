import XCTest
@testable import AgentCanvas

final class NotificationPrefsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        NotificationPrefs.notificationsEnabled = false
        for address in CanvasAddress.allCases {
            NotificationPrefs.setMuted(address, false)
        }
    }

    func testDefaultsOffAndUnmuted() {
        XCTAssertFalse(NotificationPrefs.notificationsEnabled)
        XCTAssertFalse(NotificationPrefs.isMuted(.one))
    }

    func testMutePersistsPerCanvas() {
        NotificationPrefs.setMuted(.one, true)
        XCTAssertTrue(NotificationPrefs.isMuted(.one))
        XCTAssertFalse(NotificationPrefs.isMuted(.two))
        NotificationPrefs.setMuted(.one, false)
        XCTAssertFalse(NotificationPrefs.isMuted(.one))
    }

    func testDisplayTitleFallsBackToSlotName() {
        let empty = CanvasDocument.empty
        XCTAssertEqual(
            CanvasChangeNotifier.displayTitle(for: empty, address: .one),
            CanvasAddress.one.displayName
        )
        var titled = CanvasDocument.empty
        titled.title = "  Build status  "
        XCTAssertEqual(
            CanvasChangeNotifier.displayTitle(for: titled, address: .one),
            "Build status"
        )
    }
}
