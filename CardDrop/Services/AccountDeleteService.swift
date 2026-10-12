import Foundation
import Supabase

enum AccountDeleteService {

    private struct DeleteRequestBody: Encodable {
        let appleAuthorizationCode: String?
    }

    /// Asks the server to delete the signed-in account and everything tied to
    /// it. `appleAuthorizationCode` is a fresh Sign in with Apple code (Apple
    /// accounts only) so the server can revoke the grant. Returns true once the
    /// server confirms (or says the account no longer exists); the server call is
    /// safe to repeat after a failure.
    static func delete(appleAuthorizationCode: String?) async -> Bool {
        do {
            try await supabase.functions.invoke(
                "delete-account",
                options: FunctionInvokeOptions(body: DeleteRequestBody(appleAuthorizationCode: appleAuthorizationCode))
            )
            return true
        } catch let fnError as FunctionsError {
            // 401 = the server has no valid user for this login (the account was
            // already deleted, for example by the final-suspension cleanup). That
            // counts as deleted: the caller clears the local data and signs out.
            if case .httpError(let code, _) = fnError, code == 401 { return true }
            return false
        } catch {
            return false
        }
    }
}
