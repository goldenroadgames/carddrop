import Foundation
import Combine

/// Shared "is this account suspended?" answer. The app swaps to the Suspended
/// screen whenever it's true. Cheap to call: at most one server check every
/// 5 seconds, so it can be triggered from every navigation point (tab
/// switches, Send a Postcard, the send step) without piling up requests.
@MainActor
final class SuspensionMonitor: ObservableObject {
    static let shared = SuspensionMonitor()

    @Published private(set) var isSuspended = false

    private var lastCheck = Date.distantPast
    private var inFlight = false

    /// Throttled unless `force` (launch, sign-in and foreground always check).
    func recheck(force: Bool = false) async {
        if inFlight { return }
        if !force && Date().timeIntervalSince(lastCheck) < 5 { return }
        inFlight = true
        defer { inFlight = false }
        // nil = couldn't ask (offline, signed out): keep the previous answer.
        if let suspended = await SuspensionService.isSuspended() {
            isSuspended = suspended
            lastCheck = Date()
        }
    }

    /// Fire-and-forget version for button taps and onChange handlers.
    nonisolated static func trigger() {
        Task { @MainActor in await SuspensionMonitor.shared.recheck() }
    }
}
