import XCTest
@testable import Claude_Usage

/// The switches, the gauge selection and the surface handles.
///
/// The device token is deliberately not exercised here: it lives in the
/// Keychain, and these assertions are about the defaults-backed half of the
/// store, which is where all the actual rules are.
final class NotifySettingsStoreTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: NotifySettingsStore!

    override func setUp() {
        super.setUp()
        suiteName = "notify.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = NotifySettingsStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        super.tearDown()
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
}
