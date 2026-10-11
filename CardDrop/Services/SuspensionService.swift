import Foundation
import Supabase

/// Asks the server whether this account or device is suspended (a banned
/// account, its verified email, this device, or a device linked to it).
enum SuspensionService {

    private nonisolated struct Params: Encodable {
        let p_device: String
    }

    /// nil when the check couldn't complete (offline, signed out) so callers
    /// can keep their previous answer instead of flipping on a network blip.
    static func isSuspended() async -> Bool? {
        do {
            let suspended: Bool = try await supabase
                .rpc("is_suspended", params: Params(p_device: UserService.deviceUUID.uuidString))
                .execute()
                .value
            return suspended
        } catch {
            return nil
        }
    }
}
