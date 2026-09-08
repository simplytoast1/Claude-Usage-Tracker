//
//  NotifySettingsStore.swift
//  Claude Usage
//
//  Where the Notify! link, the surface switches and the surface handles live.
//

import Foundation

/// Defaults for the Notify! integration.
enum NotifyConstants {
    /// Off until the user links a device. The feature sends data to a third
    /// party service, so it can never be on by default.
    static let defaultEnabled = false

    /// Every surface is on once the feature itself is on: a user who linked a
    /// device wants to see their quota, and each can be switched off alone.
    static let defaultLiveActivityEnabled = true
    static let defaultWidgetEnabled = true

    /// The Home Screen widget ships behind a server side kill switch, so a
    /// build that supports it can meet a gateway that is not serving it yet.
    /// On by default anyway: a 503 is handled as "not yet" rather than as an
    /// error, and leaving it off would mean nobody sees the surface on the day
    /// it is switched on.
    static let defaultScreenWidgetEnabled = true
}

/// Settings for publishing usage to a Notify! device.
///
/// Its own store rather than a corner of `SharedDataStore`, because Notify! is
/// not somewhere the app reads usage from, it is somewhere the app writes to,
/// and none of the provider vocabulary applies. The switches and the surface
/// handles live in UserDefaults; the device token is a secret and goes to the
/// Keychain.
final class NotifySettingsStore {
    static let shared = NotifySettingsStore()

    private let defaults: UserDefaults
    private let keychain: KeychainService

    /// Every key this feature owns, all under a `notify.` prefix so they are
    /// obvious in a defaults dump and easy to remove wholesale.
    private enum Keys {
        static let enabled = "notify.enabled"
        static let deviceId = "notify.deviceId"
        static let liveActivityEnabled = "notify.liveActivityEnabled"
        static let widgetEnabled = "notify.widgetEnabled"
        static let screenWidgetEnabled = "notify.screenWidgetEnabled"
        static let gaugeProviderId = "notify.gauge.providerId"
        static let gaugeQuotaKey = "notify.gauge.quotaKey"
        static let activityId = "notify.activityId"
        static let widgetId = "notify.widgetId"
        static let screenWidgetId = "notify.screenWidgetId"
    }

    init(defaults: UserDefaults = .standard, keychain: KeychainService = .shared) {
        self.defaults = defaults
        self.keychain = keychain
    }

    // MARK: - Master switch

    func isEnabled() -> Bool {
        guard defaults.object(forKey: Keys.enabled) != nil else {
            return NotifyConstants.defaultEnabled
        }
        return defaults.bool(forKey: Keys.enabled)
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.enabled)
    }

    // MARK: - Credentials

    func deviceId() -> String {
        defaults.string(forKey: Keys.deviceId) ?? ""
    }

    func setDeviceId(_ deviceId: String) {
        defaults.set(deviceId, forKey: Keys.deviceId)
    }

    /// The token, from the Keychain. A read that throws is treated as no token
    /// rather than as a crash: a locked or refusing Keychain means the app is
    /// not linked right now, which is a state the pane already knows how to
    /// show.
    func deviceToken() -> String? {
        do {
            let token = try keychain.load(for: .notifyDeviceToken)
            guard let token, !token.isEmpty else { return nil }
            return token
        } catch {
            LoggingService.shared.logError("Notify!: could not read the device token from the Keychain", error: error)
            return nil
        }
    }

    @discardableResult
    func saveDeviceToken(_ token: String) -> Bool {
        do {
            try keychain.save(token, for: .notifyDeviceToken)
            return true
        } catch {
            LoggingService.shared.logError("Notify!: could not save the device token to the Keychain", error: error)
            return false
        }
    }

    @discardableResult
    func deleteDeviceToken() -> Bool {
        do {
            try keychain.delete(for: .notifyDeviceToken)
            return true
        } catch {
            LoggingService.shared.logError("Notify!: could not delete the device token from the Keychain", error: error)
            return false
        }
    }

    func hasDeviceToken() -> Bool {
        keychain.exists(for: .notifyDeviceToken)
    }

    /// The saved credentials as one value, or nil when either half is missing
    /// or malformed. The single place the rest of the app asks "are we linked".
    func deviceLink() -> NotifyDeviceLink? {
        guard let token = deviceToken() else { return nil }
        return NotifyDeviceLink(deviceId: deviceId(), token: token)
    }

    /// Stores a link, keeping the surface handles when it names the same device.
    ///
    /// The handles are owned by a device, not by a credential. Pressing Save
    /// twice, or re-saving after rotating a token, names the same phone, and
    /// the tile and the two widgets already standing on it are still ours:
    /// clearing their handles would orphan them and make the next publish
    /// create a second set beside them, which on a Home Screen is a duplicate
    /// the user has to go and remove by hand. Only a different device id
    /// invalidates them, and then they must go, because they name surfaces on a
    /// phone this link can no longer write to.
    func saveDeviceLink(_ link: NotifyDeviceLink) {
        if deviceId() != link.deviceId {
            setActivityId(nil)
            setWidgetId(nil)
            setScreenWidgetId(nil)
        }
        setDeviceId(link.deviceId)
        saveDeviceToken(link.token)
    }

    /// Forgets the link and everything standing on it. The surfaces already on
    /// the phone are left alone: removing them needs a network call at the exact
    /// moment the user said stop, and would fail silently when they are offline.
    func clearDeviceLink() {
        setDeviceId("")
        deleteDeviceToken()
        setActivityId(nil)
        setWidgetId(nil)
        setScreenWidgetId(nil)
    }

    // MARK: - Surfaces

    func isLiveActivityEnabled() -> Bool {
        guard defaults.object(forKey: Keys.liveActivityEnabled) != nil else {
            return NotifyConstants.defaultLiveActivityEnabled
        }
        return defaults.bool(forKey: Keys.liveActivityEnabled)
    }

    func setLiveActivityEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.liveActivityEnabled)
    }

    func isWidgetEnabled() -> Bool {
        guard defaults.object(forKey: Keys.widgetEnabled) != nil else {
            return NotifyConstants.defaultWidgetEnabled
        }
        return defaults.bool(forKey: Keys.widgetEnabled)
    }

    func setWidgetEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.widgetEnabled)
    }

    func isScreenWidgetEnabled() -> Bool {
        guard defaults.object(forKey: Keys.screenWidgetEnabled) != nil else {
            return NotifyConstants.defaultScreenWidgetEnabled
        }
        return defaults.bool(forKey: Keys.screenWidgetEnabled)
    }

    func setScreenWidgetEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.screenWidgetEnabled)
    }

    // MARK: - Gauge selection

    func gaugeProviderId() -> String {
        defaults.string(forKey: Keys.gaugeProviderId) ?? ""
    }

    func setGaugeProviderId(_ providerId: String) {
        defaults.set(providerId, forKey: Keys.gaugeProviderId)
    }

    func gaugeQuotaKey() -> String {
        defaults.string(forKey: Keys.gaugeQuotaKey) ?? ""
    }

    func setGaugeQuotaKey(_ quotaKey: String) {
        defaults.set(quotaKey, forKey: Keys.gaugeQuotaKey)
    }

    /// Which quota window the gauge should show.
    func gaugeSelection() -> NotifyGaugeSelection {
        NotifyGaugeSelection(providerId: gaugeProviderId(), quotaKey: gaugeQuotaKey())
    }

    // MARK: - Surface handles

    /// The handle of the Live Activity we started, so later updates address
    /// that exact tile and never one the user started elsewhere.
    func activityId() -> String? {
        nonEmpty(defaults.string(forKey: Keys.activityId))
    }

    func setActivityId(_ activityId: String?) {
        set(activityId, forKey: Keys.activityId)
    }

    /// The handle of the Lock Screen widget we created, for the same reason.
    func widgetId() -> String? {
        nonEmpty(defaults.string(forKey: Keys.widgetId))
    }

    func setWidgetId(_ widgetId: String?) {
        set(widgetId, forKey: Keys.widgetId)
    }

    /// The handle of the Home Screen widget we created.
    func screenWidgetId() -> String? {
        nonEmpty(defaults.string(forKey: Keys.screenWidgetId))
    }

    func setScreenWidgetId(_ screenWidgetId: String?) {
        set(screenWidgetId, forKey: Keys.screenWidgetId)
    }

    // MARK: - Helpers

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func set(_ value: String?, forKey key: String) {
        if let value, !value.isEmpty {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
