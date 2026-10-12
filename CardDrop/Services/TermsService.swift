import Foundation
import Supabase

// Terms of Service / Privacy Policy acceptance. The server is the authority:
// send-card and create-postcard-payment-intent refuse ("terms_required") until
// users.terms_version >= zz_config.terms_required_version, and accept-terms is
// the only thing that writes users.terms_version. This type just lets the app
// ask the question first, so the sheet appears before an upload starts.
enum TermsService {
    private struct UserRow: Decodable { let terms_version: String? }
    private struct ConfigRow: Decodable { let value: String }
    private struct AcceptResponse: Decodable { let status: String? }

    /// True when accepted, and also when it can't be determined (offline,
    /// lookup failed): the server enforces the rule anyway.
    static func isAccepted() async -> Bool {
        guard let userID = try? await supabase.auth.session.user.id else { return true }
        do {
            let required: [ConfigRow] = try await supabase
                .from("zz_config")
                .select("value")
                .eq("key", value: "terms_required_version")
                .execute()
                .value
            guard let need = required.first?.value.trimmingCharacters(in: .whitespaces), !need.isEmpty else {
                return true
            }
            let rows: [UserRow] = try await supabase
                .from("users")
                .select("terms_version")
                .eq("id", value: userID.uuidString)
                .execute()
                .value
            // YYYY-MM-DD strings compare correctly as text.
            return (rows.first?.terms_version ?? "") >= need
        } catch {
            return true
        }
    }

    /// Records the agreement (server stamps the time and the live Terms date).
    static func accept() async throws {
        let _: AcceptResponse = try await supabase.functions
            .invoke("accept-terms", options: FunctionInvokeOptions())
    }
}
