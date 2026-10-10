import Foundation
import Supabase

enum CardDeleteService {

    private struct DeleteRequestBody: Encodable {
        let cardID: String
    }

    /// Asks the server to delete a card: the shared link dies immediately and
    /// the server removes every file and child row (retrying on its own if
    /// part of it fails). Returns true once the server confirms, false if the
    /// call failed (offline, signed out, server error).
    static func delete(cardID: UUID) async -> Bool {
        do {
            try await supabase.functions.invoke(
                "delete-card",
                options: FunctionInvokeOptions(body: DeleteRequestBody(cardID: cardID.uuidString))
            )
            return true
        } catch {
            return false
        }
    }
}
