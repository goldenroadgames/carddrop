import Foundation
import Supabase

// A server-side, structured mailing address saved for reuse across physical
// (LOB) sends — distinct from AddressBookManager/SavedAddress, which is a
// local-only, freeform-string address book used for contact autofill on
// Choose Photo/Write Card. This one backs the "Mailing Addresses" screen
// and, later, physical_orders' recipient/sender address pickers.
// What role a saved address plays for its owner. At most one "profile" row
// exists per user (enforced by a DB partial unique index); when it's
// replaced, the old row is reassigned to "sender" rather than deleted.
enum MailingAddressType: String, Codable {
    case profile, sender, recipient
}

struct SavedMailingAddress: Codable, Identifiable, Equatable {
    let id: UUID
    var nickname: String?
    var firstName: String?
    var lastName: String?
    var street: String?
    var city: String?
    var state: String?
    var zip: String?
    var country: String?
    var email: String?
    var phone: String?
    var addressType: MailingAddressType
    var isVerified: Bool
    var verifiedAt: Date?
    var lobVerificationID: String?
    var lastUsedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, nickname, email, phone, street, city, state, zip, country
        case firstName = "first_name"
        case lastName = "last_name"
        case addressType = "address_type"
        case isVerified = "is_verified"
        case verifiedAt = "verified_at"
        case lobVerificationID = "lob_verification_id"
        case lastUsedAt = "last_used_at"
    }

    var displayName: String {
        let name = [firstName, lastName].compactMap { $0 }.joined(separator: " ")
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        return nickname ?? "Address"
    }

    var formattedAddress: String {
        PostcardDraft.formatAddress(street: street ?? "", city: city ?? "", state: state ?? "", zip: zip ?? "", country: country ?? "")
    }

    /// True once street/city/state/zip are all present — required before verification can be attempted.
    var isComplete: Bool {
        !(street ?? "").trimmingCharacters(in: .whitespaces).isEmpty &&
        !(city ?? "").trimmingCharacters(in: .whitespaces).isEmpty &&
        !(state ?? "").trimmingCharacters(in: .whitespaces).isEmpty &&
        !(zip ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }
}

enum AddressBookServiceError: LocalizedError {
    case notSignedIn
    case verificationFailed(String)
    case other(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "You need to be signed in to manage mailing addresses."
        case .verificationFailed(let message): return message
        case .other(let message): return message
        }
    }
}

enum AddressBookService {

    static func fetch() async throws -> [SavedMailingAddress] {
        guard let userID = try? await supabase.auth.session.user.id else {
            throw AddressBookServiceError.notSignedIn
        }
        do {
            let rows: [SavedMailingAddress] = try await supabase
                .from("user_address_book")
                .select()
                .eq("user_id", value: userID.uuidString)
                .order("last_used_at", ascending: false)
                .execute()
                .value
            return rows
        } catch {
            throw AddressBookServiceError.other(error.localizedDescription)
        }
    }

    /// Two addresses are "the same" (within one address_type bucket) when
    /// their name and mailing-address fields all match — the same street
    /// address under a different name is a distinct row (e.g. roommates).
    private static func matches(_ a: SavedMailingAddress, _ b: SavedMailingAddress) -> Bool {
        func norm(_ s: String?) -> String {
            (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        return norm(a.firstName) == norm(b.firstName) &&
            norm(a.lastName) == norm(b.lastName) &&
            norm(a.street)    == norm(b.street) &&
            norm(a.city)      == norm(b.city) &&
            norm(a.state)     == norm(b.state) &&
            norm(a.zip)       == norm(b.zip) &&
            norm(a.country)   == norm(b.country)
    }

    private static func mailingFieldsDiffer(_ address: SavedMailingAddress, _ existing: SavedMailingAddress) -> Bool {
        existing.street  != address.street  ||
        existing.city    != address.city    ||
        existing.state   != address.state   ||
        existing.zip     != address.zip     ||
        existing.country != address.country
    }

    /// Inserts a new address, or updates an existing one (matched by `address.id`).
    ///
    /// Editing an existing row is a plain upsert-by-id. A brand-new row goes
    /// through two extra steps first:
    /// - If it's the new "profile" address, the user's current profile row
    ///   (if any, and if actually different) is reassigned to "sender" so
    ///   it's preserved rather than lost.
    /// - It's deduped against other rows of the same address_type: a
    ///   name+address match reuses that row (bumping last_used_at, merging
    ///   in any newly-supplied nickname/email/phone) instead of creating a
    ///   duplicate.
    @discardableResult
    static func save(_ address: SavedMailingAddress, existing: SavedMailingAddress?) async throws -> SavedMailingAddress {
        if let existing {
            return try await upsert(address, addressChanged: mailingFieldsDiffer(address, existing))
        }

        let current = try await fetch()

        if address.addressType == .profile,
           let currentProfile = current.first(where: { $0.addressType == .profile }),
           !matches(currentProfile, address) {
            var demoted = currentProfile
            demoted.addressType = .sender
            _ = try await upsert(demoted, addressChanged: false)
        }

        if let duplicate = current.first(where: { $0.addressType == address.addressType && matches($0, address) }) {
            var merged = duplicate
            merged.nickname = address.nickname ?? duplicate.nickname
            merged.email = address.email ?? duplicate.email
            merged.phone = address.phone ?? duplicate.phone
            return try await upsert(merged, addressChanged: false)
        }

        return try await upsert(address, addressChanged: true)
    }

    /// Whenever the mailing-address fields differ from what's already stored, resets
    /// the verification cache — the writer, not a DB trigger, owns that invalidation
    /// (see project_lob plan: Phase 1 decision).
    @discardableResult
    private static func upsert(_ address: SavedMailingAddress, addressChanged: Bool) async throws -> SavedMailingAddress {
        guard let userID = try? await supabase.auth.session.user.id else {
            throw AddressBookServiceError.notSignedIn
        }

        var row: [String: AnyJSON] = [
            "id":          .string(address.id.uuidString),
            "user_id":     .string(userID.uuidString),
            "nickname":    address.nickname.map(AnyJSON.string) ?? .null,
            "first_name":  address.firstName.map(AnyJSON.string) ?? .null,
            "last_name":   address.lastName.map(AnyJSON.string) ?? .null,
            "street":      address.street.map(AnyJSON.string) ?? .null,
            "city":        address.city.map(AnyJSON.string) ?? .null,
            "state":       address.state.map(AnyJSON.string) ?? .null,
            "zip":         address.zip.map(AnyJSON.string) ?? .null,
            "country":     address.country.map(AnyJSON.string) ?? .null,
            "email":       address.email.map(AnyJSON.string) ?? .null,
            "phone":       address.phone.map(AnyJSON.string) ?? .null,
            "address_type": .string(address.addressType.rawValue),
            "last_used_at": .string(ISO8601DateFormatter().string(from: Date())),
        ]

        if addressChanged {
            row["is_verified"] = .bool(false)
            row["verified_at"] = .null
            row["lob_verification_id"] = .null
        }

        do {
            let saved: SavedMailingAddress = try await supabase
                .from("user_address_book")
                .upsert(row, onConflict: "id")
                .select()
                .single()
                .execute()
                .value
            return saved
        } catch {
            throw AddressBookServiceError.other(error.localizedDescription)
        }
    }

    static func delete(id: UUID) async throws {
        do {
            try await supabase
                .from("user_address_book")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
        } catch {
            throw AddressBookServiceError.other(error.localizedDescription)
        }
    }

    static func touchLastUsed(id: UUID) async {
        try? await supabase
            .from("user_address_book")
            .update(["last_used_at": AnyJSON.string(ISO8601DateFormatter().string(from: Date()))])
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: - Verification

    private struct VerifyRequestBody: Encodable {
        let addressID: String
    }

    private struct VerifyResponseBody: Decodable {
        let verified: Bool?
        let deliverability: String?
        let message: String?
        let address: SavedMailingAddress?
        let error: String?
        let detail: String?
    }

    /// Calls the `verify-address` edge function for a saved address. Returns the
    /// updated (possibly standardized) address on success; throws with a
    /// user-facing message when the address can't be verified as deliverable.
    static func verify(id: UUID) async throws -> SavedMailingAddress {
        let body = VerifyRequestBody(addressID: id.uuidString)
        do {
            let response: VerifyResponseBody = try await supabase.functions
                .invoke("verify-address", options: FunctionInvokeOptions(body: body))

            if let errorCode = response.error {
                throw AddressBookServiceError.other(response.detail ?? errorCode)
            }
            if response.verified == true, let address = response.address {
                return address
            }
            throw AddressBookServiceError.verificationFailed(
                response.message ?? "This address couldn't be verified as deliverable."
            )
        } catch let error as AddressBookServiceError {
            throw error
        } catch let fnError as FunctionsError {
            if case .httpError(_, let data) = fnError,
               let body = try? JSONDecoder().decode(VerifyResponseBody.self, from: data) {
                throw AddressBookServiceError.other(body.detail ?? body.error ?? fnError.localizedDescription)
            }
            throw AddressBookServiceError.other(fnError.localizedDescription)
        } catch {
            throw AddressBookServiceError.other(error.localizedDescription)
        }
    }
}
