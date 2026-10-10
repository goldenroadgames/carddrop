import Foundation
import Supabase

enum AccountDeleteService {

    private struct DeleteRequestBody: Encodable {
        let appleAuthorizationCode: String?
    }

    /// Asks the server to delete the signed-in account and everything tied to
    /// it. `appleAuthorizationCode` is a fresh Sign in with Apple code (Apple
    /// accounts only) so the server can revoke the grant. Returns true once the
    /// server confirms; the server call is safe to repeat after a failure.
    static func delete(appleAuthorizationCode: String?) async -> Bool {
        do {
            try await supabase.functions.invoke(
                "delete-account",
                options: FunctionInvokeOptions(body: DeleteRequestBody(appleAuthorizationCode: appleAuthorizationCode))
            )
            return true
        } catch {
            return false
        }
    }
}
