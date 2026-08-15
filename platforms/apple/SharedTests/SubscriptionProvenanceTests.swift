import XCTest
#if canImport(AgentCanvasiOS)
@testable import AgentCanvasiOS
#else
@testable import AgentCanvas
#endif

final class SubscriptionProvenanceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_787_000_000)

    func testLocalSlotHasNoProvenance() {
        XCTAssertNil(SubscriptionProvenance.resolve(subscription: nil, now: now))
    }

    func testSlugFromAPIAndViewerURLs() {
        XCTAssertEqual(
            SubscriptionProvenance.slug(fromURL: "https://canvas.velox.test/api/v1/canvases/standups"),
            "standups"
        )
        XCTAssertEqual(
            SubscriptionProvenance.slug(fromURL: "https://canvas.velox.test/c/standups"),
            "standups"
        )
        XCTAssertEqual(SubscriptionProvenance.slug(fromURL: "standups"), "standups")
    }

    func testFreshPullShowsSlugAndTimeWithoutStale() throws {
        let sub = subscription(
            lastSuccessAt: now.addingTimeInterval(-60),
            lastError: nil
        )
        let provenance = SubscriptionProvenance.resolve(subscription: sub, now: now)
        let got = try XCTUnwrap(provenance)
        XCTAssertEqual(got.slug, "standups")
        XCTAssertEqual(got.lastSyncedAt, now.addingTimeInterval(-60))
        XCTAssertFalse(got.isStale)
        XCTAssertNil(got.staleReason)
        XCTAssertFalse(got.compactLine.contains("outdated"))
        XCTAssertTrue(got.compactLine.hasPrefix("standups · "))
    }

    func testFailedPullIsStaleAndKeepsLastSuccess() throws {
        let synced = now.addingTimeInterval(-120)
        let sub = subscription(
            lastSuccessAt: synced,
            lastError: "HTTP 503"
        )
        let got = try XCTUnwrap(SubscriptionProvenance.resolve(subscription: sub, now: now))
        XCTAssertTrue(got.isStale)
        XCTAssertEqual(got.staleReason, .pullFailed)
        XCTAssertEqual(got.lastSyncedAt, synced)
        XCTAssertTrue(got.compactLine.contains("outdated"))
        XCTAssertTrue(got.compactLine.contains("standups"))
        XCTAssertTrue(got.accessibilityLabel.contains("may be outdated"))
    }

    func testAgedSuccessIsStaleAfterDocumentedThreshold() throws {
        let sub = subscription(
            lastSuccessAt: now.addingTimeInterval(-(SubscriptionProvenance.defaultStaleAfter + 1)),
            lastError: nil,
            poll: 60
        )
        let got = try XCTUnwrap(SubscriptionProvenance.resolve(subscription: sub, now: now))
        XCTAssertTrue(got.isStale)
        XCTAssertEqual(got.staleReason, .lastSyncTooOld)
        XCTAssertEqual(got.staleAfter, SubscriptionProvenance.defaultStaleAfter)
    }

    func testSlowPollerUsesTripleIntervalThreshold() throws {
        let poll = 10 * 60
        let expected = TimeInterval(poll * 3)
        XCTAssertEqual(SubscriptionProvenance.staleAfter(pollIntervalSeconds: poll), expected)
        let sub = subscription(
            lastSuccessAt: now.addingTimeInterval(-(expected - 30)),
            lastError: nil,
            poll: poll
        )
        let got = try XCTUnwrap(SubscriptionProvenance.resolve(subscription: sub, now: now))
        XCTAssertFalse(got.isStale)
    }

    func testLastFetchCountsAsSuccessWhenNoErrorAndNoLastSuccessAt() throws {
        let fetched = now.addingTimeInterval(-30)
        var sub = subscription(lastSuccessAt: nil, lastError: nil)
        sub.lastFetchAt = fetched
        let got = try XCTUnwrap(SubscriptionProvenance.resolve(subscription: sub, now: now))
        XCTAssertEqual(got.lastSyncedAt, fetched)
        XCTAssertFalse(got.isStale)
    }

    func testFailedPullWithoutLastSuccessDoesNotInventASyncTime() throws {
        var sub = subscription(lastSuccessAt: nil, lastError: "Gone (unpublished)")
        sub.lastFetchAt = now
        let got = try XCTUnwrap(SubscriptionProvenance.resolve(subscription: sub, now: now))
        XCTAssertNil(got.lastSyncedAt)
        XCTAssertTrue(got.isStale)
        XCTAssertEqual(got.compactLine, "standups · outdated")
    }

    func testSubscriptionsKeyOffDefinitionIdNotSize() {
        XCTAssertEqual(CloudSubscriptionStore.canonicalCanvasId("one"), "one")
        XCTAssertEqual(CloudSubscriptionStore.canonicalCanvasId("md-one"), "one")
        XCTAssertEqual(CloudSubscriptionStore.canonicalCanvasId("sm-two"), "two")
        XCTAssertEqual(CloudSubscriptionStore.canonicalCanvasId("twelve"), "twelve")
        // Invented size-baked names never existed and must not become four–twelve.
        XCTAssertEqual(CloudSubscriptionStore.canonicalCanvasId("sm-four"), "sm-four")
        XCTAssertTrue(CloudSubscriptionStore.recordsMatch("md-one", "one"))
        XCTAssertTrue(CloudSubscriptionStore.recordsMatch("sm-one", "lg-one"))
        XCTAssertTrue(CloudSubscriptionStore.recordsMatch("one", "one"))
        XCTAssertFalse(CloudSubscriptionStore.recordsMatch("one", "two"))
        XCTAssertFalse(CloudSubscriptionStore.recordsMatch("sm-four", "four"))
    }

    func testSameDefinitionSharesProvenanceAcrossFamilies() throws {
        let sub = subscription(lastSuccessAt: now.addingTimeInterval(-60), lastError: nil)
        let small = try XCTUnwrap(SubscriptionProvenance.resolve(subscription: sub, now: now))
        let large = try XCTUnwrap(SubscriptionProvenance.resolve(subscription: sub, now: now))
        XCTAssertEqual(small, large)
        XCTAssertEqual(CanvasAddress.parse("sm-one"), .one)
        XCTAssertEqual(CanvasAddress.parse("xl-one"), .one)
        XCTAssertEqual(CanvasAddress.one.widgetKind, "AgentCanvas.one")
        XCTAssertEqual(CanvasAddress.allSupportedFamilies.count, 4)
    }

    private func subscription(
        lastSuccessAt: Date?,
        lastError: String?,
        poll: Int = 60
    ) -> CloudSubscription {
        CloudSubscription(
            canvas: "one",
            url: "https://canvas.velox.test/api/v1/canvases/standups",
            pollIntervalSeconds: poll,
            enabled: true,
            etag: "abc",
            lastFetchAt: lastSuccessAt,
            lastError: lastError,
            lastStatusCode: lastError == nil ? 304 : 503,
            lastSuccessAt: lastSuccessAt
        )
    }
}
