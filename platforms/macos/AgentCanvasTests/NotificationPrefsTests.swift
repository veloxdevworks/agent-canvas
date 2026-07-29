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
        XCTAssertFalse(NotificationPrefs.isMuted(.mdOne))
    }

    func testMutePersistsPerCanvas() {
        NotificationPrefs.setMuted(.mdOne, true)
        XCTAssertTrue(NotificationPrefs.isMuted(.mdOne))
        XCTAssertFalse(NotificationPrefs.isMuted(.mdTwo))
        NotificationPrefs.setMuted(.mdOne, false)
        XCTAssertFalse(NotificationPrefs.isMuted(.mdOne))
    }

    func testDisplayTitleFallsBackToSlotName() {
        let empty = CanvasDocument.empty
        XCTAssertEqual(
            CanvasChangeNotifier.displayTitle(for: empty, address: .smOne),
            CanvasAddress.smOne.displayName
        )
        var titled = CanvasDocument.empty
        titled.title = "  Build status  "
        XCTAssertEqual(
            CanvasChangeNotifier.displayTitle(for: titled, address: .smOne),
            "Build status"
        )
    }
}
