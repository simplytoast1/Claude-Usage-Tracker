import XCTest
@testable import Claude_Usage

/// The switches, the gauge selection and the surface handles.
///
/// The device token is deliberately not exercised here: it lives in the
/// Keychain, and these assertions are about the defaults-backed half of the
/// store, which is where all the actual rules are.
///
/// `@MainActor` because the app target builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so everything under test is
/// main-actor isolated while the test target's own default is not. Same
/// reason `NotchHUDCoreTests` and `NotchHookServerTests` carry it.
@MainActor
final class NotifySettingsStoreTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: NotifySettingsStore!

    /// The token this machine had linked before the suite ran, if any.
    ///
    /// The switches and handles live in a throwaway defaults suite, but the
    /// token store is app-wide on a build with a reachable Keychain. Running
    /// these tests must never cost a developer the device they had linked, so
    /// whatever was there is put back in tearDown.
    private var preexistingToken: String?

    // The `async throws` overrides rather than the synchronous ones: this class
    // is `@MainActor`, and only the async variants can carry isolation an
    // override adds on top of XCTestCase's own. Same shape as
    // `NotchHookServerTests`.
    override func setUp() async throws {
        suiteName = "notify.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = NotifySettingsStore(defaults: defaults)
        preexistingToken = store.deviceToken()
    }

    override func tearDown() async throws {
        store.deleteDeviceToken()
        if let preexistingToken {
            store.saveDeviceToken(preexistingToken)
        }
        preexistingToken = nil
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
    }

    // MARK: - Defaults

    /// A feature that talks to someone else's server cannot ship enabled.
    func testPublishingIsOffUntilTheUserTurnsItOn() {
        XCTAssertFalse(store.isEnabled())
    }

    /// Every surface is on once the feature itself is on: a user who linked a
    /// device wants to see their usage.
    func testEverySurfaceIsOnByDefault() {
        XCTAssertTrue(store.isLiveActivityEnabled())
        XCTAssertTrue(store.isWidgetEnabled())
        XCTAssertTrue(store.isScreenWidgetEnabled())
    }

    func testTheGaugeStartsAutomatic() {
        XCTAssertTrue(store.gaugeSelection().isAutomatic)
    }

    // MARK: - Round trips

    func testTheSwitchesRoundTrip() {
        store.setEnabled(true)
        store.setLiveActivityEnabled(false)
        store.setWidgetEnabled(false)
        store.setScreenWidgetEnabled(false)

        XCTAssertTrue(store.isEnabled())
        XCTAssertFalse(store.isLiveActivityEnabled())
        XCTAssertFalse(store.isWidgetEnabled())
        XCTAssertFalse(store.isScreenWidgetEnabled())
    }

    func testTheGaugeSelectionRoundTrips() {
        store.setGaugeProviderId("anthropic")
        store.setGaugeQuotaKey("opus_weekly")

        let selection = store.gaugeSelection()
        XCTAssertFalse(selection.isAutomatic)
        XCTAssertEqual(selection.providerId, "anthropic")
        XCTAssertEqual(selection.quotaKey, "opus_weekly")
    }

    /// Half a selection is no selection: the builder falls back to the worst
    /// window rather than looking for a provider with no window named.
    func testHalfASelectionReadsAsAutomatic() {
        store.setGaugeProviderId("anthropic")
        XCTAssertTrue(store.gaugeSelection().isAutomatic)
    }

    // MARK: - Handles

    func testTheHandlesRoundTripAndClear() {
        store.setActivityId("LA123456")
        store.setWidgetId("WG123456")
        store.setScreenWidgetId("SW123456")

        XCTAssertEqual(store.activityId(), "LA123456")
        XCTAssertEqual(store.widgetId(), "WG123456")
        XCTAssertEqual(store.screenWidgetId(), "SW123456")

        store.setActivityId(nil)
        store.setWidgetId(nil)
        store.setScreenWidgetId(nil)

        XCTAssertNil(store.activityId())
        XCTAssertNil(store.widgetId())
        XCTAssertNil(store.screenWidgetId())
    }

    /// An empty string is not a handle. Storing one would make the next publish
    /// address `/live-activity/?token=`, which is not a route.
    func testAnEmptyHandleReadsAsNoHandle() {
        store.setActivityId("")
        XCTAssertNil(store.activityId())
    }

    func testTheDeviceIdRoundTrips() {
        store.setDeviceId("IO12345678901234")
        XCTAssertEqual(store.deviceId(), "IO12345678901234")
    }

    // MARK: - The token

    /// The regression this file exists for. A token that reports itself saved
    /// and then cannot be read back leaves the pane saying "linked" while every
    /// publish answers "add your device ID and token". Which store actually
    /// took it is not the assertion — that it comes back is.
    func testASavedTokenAlwaysReadsBackAgain() {
        XCTAssertTrue(store.saveDeviceToken("s3cret-token"))
        XCTAssertEqual(store.deviceToken(), "s3cret-token")
    }

    func testSavingALinkReportsThatItLandedAndTheLinkIsReadable() {
        let link = NotifyDeviceLink(deviceId: "493F9D2A", token: "s3cret-token")!

        XCTAssertTrue(store.saveDeviceLink(link))
        XCTAssertEqual(store.deviceLink(), link)
        XCTAssertTrue(store.hasDeviceToken())
    }

    func testDeletingTheTokenLeavesNothingLinked() {
        XCTAssertTrue(store.saveDeviceToken("s3cret-token"))
        store.deleteDeviceToken()

        XCTAssertNil(store.deviceToken())
        XCTAssertNil(store.deviceLink())
    }

    /// The handles name surfaces standing on a particular phone, so a link
    /// pointing somewhere else invalidates them.
    func testLinkingADifferentDeviceClearsTheSurfaceHandles() {
        store.setActivityId("LA123456")
        store.setWidgetId("WG123456")
        store.setScreenWidgetId("SW123456")

        store.saveDeviceLink(NotifyDeviceLink(deviceId: "493F9D2A", token: "s3cret")!)

        XCTAssertNil(store.activityId())
        XCTAssertNil(store.widgetId())
        XCTAssertNil(store.screenWidgetId())
    }

    /// A rotated token is the same phone, and the tile and widgets already
    /// standing on it are still ours. Clearing their handles would orphan them
    /// and put a duplicate beside each on the next publish.
    func testRotatingTheTokenForTheSameDeviceKeepsTheHandles() {
        store.saveDeviceLink(NotifyDeviceLink(deviceId: "493F9D2A", token: "old")!)
        store.setActivityId("LA123456")
        store.setWidgetId("WG123456")
        store.setScreenWidgetId("SW123456")

        store.saveDeviceLink(NotifyDeviceLink(deviceId: "493F9D2A", token: "new")!)

        XCTAssertEqual(store.activityId(), "LA123456")
        XCTAssertEqual(store.widgetId(), "WG123456")
        XCTAssertEqual(store.screenWidgetId(), "SW123456")
    }
}
