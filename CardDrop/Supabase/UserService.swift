import Foundation
import Security
import Supabase

enum UserService {

    // MARK: - Device UUID

    /// A stable UUID tied to this physical device. Stored in Keychain so it
    /// survives app deletion and reinstall. Created once on first launch.
    static var deviceUUID: UUID {
        let service = "com.goldenroadgames.carddrop"
        let account = "device_uuid"

        // Attempt to read existing value from Keychain
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      account,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let string = String(data: data, encoding: .utf8),
           let uuid = UUID(uuidString: string) {
            return uuid
        }

        // First launch — generate and store a new UUID
        let new = UUID()
        let data = new.uuidString.data(using: .utf8)!
        let attributes: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  service,
            kSecAttrAccount:  account,
            kSecValueData:    data
        ]
        SecItemAdd(attributes as CFDictionary, nil)
        return new
    }

    // MARK: - Anonymous session tracking

    /// The UUID of the last known anonymous session, stored in keychain.
    static var storedAnonymousUserID: String? {
        get { readKeychain(account: "anonymous_user_id") }
        set {
            if let value = newValue {
                writeKeychain(account: "anonymous_user_id", value: value)
            } else {
                deleteKeychain(account: "anonymous_user_id")
            }
        }
    }

    /// Call when an anonymous session starts. If the UUID differs from the stored one,
    /// wipes the old anonymous folder and updates the stored UUID.
    static func handleNewAnonymousSession(newID: String) {
        if let oldID = storedAnonymousUserID, oldID != newID {
            let oldFolder = DraftManager.draftsDirectory(for: oldID)
            try? FileManager.default.removeItem(at: oldFolder)
            print("[UserService] Wiped anonymous folder for old session \(oldID)")
        }
        storedAnonymousUserID = newID
    }

    // MARK: - Keychain helpers

    private static let keychainService = "com.goldenroadgames.carddrop"

    private static func readKeychain(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: account,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychain(account: String, value: String) {
        let data = value.data(using: .utf8)!
        // Try update first, then add
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: account
        ]
        let update: [CFString: Any] = [kSecValueData: data]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData] = data
            SecItemAdd(attributes as CFDictionary, nil)
        }
    }

    private static func deleteKeychain(account: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Upsert

    /// Creates the user row on first launch; no-ops on subsequent launches.
    /// Call this whenever currentUserID becomes non-nil.
    /// Returns false if the session is invalid (stale JWT) — caller should sign out.
    @discardableResult
    static func upsertUser(id: UUID) async -> Bool {
        let userRow: [String: AnyJSON] = [
            "id": .string(id.uuidString)
        ]
        let deviceRow: [String: AnyJSON] = [
            "device_uuid": .string(deviceUUID.uuidString),
            "user_id":     .string(id.uuidString)
        ]
        do {
            try await supabase
                .from("users")
                .upsert(userRow, onConflict: "id")
                .execute()

            try await supabase
                .from("user_devices")
                .upsert(deviceRow, onConflict: "device_uuid")
                .execute()

            return true
        } catch {
            let message = error.localizedDescription.lowercased()
            if message.contains("jwt") || message.contains("invalid token") ||
                
                message.contains("not authenticated") {
                print("[UserService] stale session detected — signing out")
                return false
            }
            print("[UserService] upsert failed: \(error)")
            return true
        }
    }

    // MARK: - Sender nickname

    /// Fetches the saved casual sender nickname for the current user, if any.
    static func fetchSenderNickname() async -> String? {
        guard let userID = try? await supabase.auth.session.user.id else { return nil }
        struct Row: Decodable { let sender_nickname: String? }
        guard let row = try? await supabase
            .from("users")
            .select("sender_nickname")
            .eq("id", value: userID.uuidString)
            .single()
            .execute()
            .value as Row
        else { return nil }
        return row.sender_nickname
    }

    /// Silently persists the casual sender nickname whenever the user edits it.
    static func updateSenderNickname(_ nickname: String) async {
        guard let userID = try? await supabase.auth.session.user.id else { return }
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: AnyJSON = trimmed.isEmpty ? .null : .string(trimmed)
        try? await supabase
            .from("users")
            .update(["sender_nickname": value])
            .eq("id", value: userID.uuidString)
            .execute()
    }
}
