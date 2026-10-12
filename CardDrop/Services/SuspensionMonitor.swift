import Foundation
import Combine
import Supabase

/// Shared "is this account suspended?" answer. The app swaps to the Suspended
/// screen whenever it's true. Cheap to call: at most one server check every
/// 5 seconds, so it can be triggered from every navigation point (tab
/// switches, Send a Postcard, the send step) without piling up requests.
@MainActor
final class SuspensionMonitor: ObservableObject {
    static let shared = SuspensionMonitor()

    // Starts from the last answer the server gave on this phone, so a suspended
    // account opens straight onto the Suspended screen instead of flashing the
    // gallery for the second or two the first server check takes. The server
    // answer always overrides it; a signed-out phone clears it.
    private static let lastKnownKey = "suspension.lastKnown"
    @Published private(set) var isSuspended = UserDefaults.standard.bool(forKey: "suspension.lastKnown")

    // The last answer about whether the suspension is FINAL (no appeal left),
    // remembered so a final account opens straight onto the minimal Account
    // Disabled screen. The Suspended screen re-verifies it with the server and
    // corrects it if it changed; reinstatement clears it.
    private static let knownFinalKey = "suspension.knownFinal"
    @Published private(set) var knownFinal = UserDefaults.standard.bool(forKey: "suspension.knownFinal")

    func setKnownFinal(_ value: Bool) {
        knownFinal = value
        UserDefaults.standard.set(value, forKey: Self.knownFinalKey)
    }

    // True when this phone is permanently disabled (a final suspension happened
    // on it). Remembered across launches like isSuspended, but only the server's
    // answer clears it.
    private static let devicePermanentKey = "suspension.devicePermanent"
    @Published private(set) var devicePermanent = UserDefaults.standard.bool(forKey: "suspension.devicePermanent")

    /// Works signed out: asks the server about the phone itself.
    func recheckDevice() async {
        if let permanent = await SuspensionService.isDevicePermanent() {
            devicePermanent = permanent
            UserDefaults.standard.set(permanent, forKey: Self.devicePermanentKey)
        }
        hasChecked = true
    }

    // False until the first suspension answer of this launch (or the app's
    // 2-second cap), so the app can hold a spinner instead of flashing the
    // gallery of a suspended account.
    @Published private(set) var hasChecked = false

    func markChecked() { hasChecked = true }

    private var lastCheck = Date.distantPast
    private var inFlight = false

    /// Throttled unless `force` (launch, sign-in and foreground always check).
    func recheck(force: Bool = false) async {
        if inFlight { return }
        if !force && Date().timeIntervalSince(lastCheck) < 5 { return }
        inFlight = true
        defer { inFlight = false; hasChecked = true }
        // nil = couldn't ask (offline, signed out): keep the previous answer.
        if let suspended = await SuspensionService.isSuspended() {
            isSuspended = suspended
            UserDefaults.standard.set(suspended, forKey: Self.lastKnownKey)
            if !suspended { setKnownFinal(false) }
            lastCheck = Date()
        } else if supabase.auth.currentSession == nil {
            // Signed out (e.g. the account was deleted): nothing to be suspended
            // as, and a stale "suspended" must not follow the phone around.
            isSuspended = false
            UserDefaults.standard.set(false, forKey: Self.lastKnownKey)
            await recheckDevice()
        }
    }

    /// Fire-and-forget version for button taps and onChange handlers.
    nonisolated static func trigger() {
        Task { @MainActor in await SuspensionMonitor.shared.recheck() }
    }
}
