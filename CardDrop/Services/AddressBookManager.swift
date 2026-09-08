import Combine
import Foundation

class AddressBookManager: ObservableObject {
    @Published private(set) var addresses: [SavedAddress] = []

    private var currentUserID: String = "_pending"

    var senderAddresses: [SavedAddress] {
        addresses.filter(\.usedAsSender).sorted { $0.lastUsed > $1.lastUsed }
    }
    var recipientAddresses: [SavedAddress] {
        addresses.filter(\.usedAsRecipient).sorted { $0.lastUsed > $1.lastUsed }
    }

    init() {
        // Intentionally empty — data loads when setUser() is called from CardDropApp.
    }

    // MARK: - User lifecycle

    func setUser(_ userID: String) {
        currentUserID = userID
        load()
    }

    /// Clear in-memory data without touching disk (used on sign-out of named accounts).
    func clearUser() {
        addresses = []
    }

    // MARK: - Public API

    /// Insert or update an address-book entry. Matches an existing entry by phone, then
    /// email, then name (in that order) so a digital-only contact (no name yet, just a
    /// typed phone/email) can later be matched and filled in by a contact lookup.
    ///
    /// `nameIsAuthoritative` distinguishes where the name came from:
    /// - `true` (a Contacts lookup was used for this send): the contact is the source of
    ///   truth, so `name` replaces the stored name outright — even if it's blank (e.g. the
    ///   contact only has a first name).
    /// - `false` (default — the value was typed in manually): `name` is ignored entirely,
    ///   so a manually-entered phone/email on a later send never blanks out a name that
    ///   was already captured from a previous contact lookup.
    ///
    /// Address/email/phone always follow the non-destructive rule: only overwrite a
    /// non-empty existing field when the new value is itself non-empty.
    func saveIfNew(name: String, nickname: String = "", address: String, email: String = "", phone: String = "", role: AddressRole, nameIsAuthoritative: Bool = false) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddr = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty || !trimmedEmail.isEmpty || !trimmedPhone.isEmpty else { return }

        let normalizedPhone = Self.normalizedDigits(trimmedPhone)

        let matchIdx = addresses.firstIndex(where: { existing in
            if !normalizedPhone.isEmpty, Self.normalizedDigits(existing.phone) == normalizedPhone { return true }
            if !trimmedEmail.isEmpty, existing.email.caseInsensitiveCompare(trimmedEmail) == .orderedSame { return true }
            if !trimmedName.isEmpty, existing.name.caseInsensitiveCompare(trimmedName) == .orderedSame { return true }
            return false
        })

        if let idx = matchIdx {
            switch role {
            case .sender:    addresses[idx].usedAsSender = true
            case .recipient: addresses[idx].usedAsRecipient = true
            }
            if nameIsAuthoritative {
                addresses[idx].name = trimmedName
            } else if addresses[idx].name.isEmpty, !trimmedName.isEmpty {
                addresses[idx].name = trimmedName
            }
            if !trimmedNickname.isEmpty { addresses[idx].nickname = trimmedNickname }
            if !trimmedAddr.isEmpty { addresses[idx].address = trimmedAddr }
            if !trimmedEmail.isEmpty { addresses[idx].email = trimmedEmail }
            if !trimmedPhone.isEmpty { addresses[idx].phone = trimmedPhone }
            addresses[idx].lastUsed = Date()
        } else {
            var entry = SavedAddress(name: trimmedName, nickname: trimmedNickname, address: trimmedAddr, email: trimmedEmail, phone: trimmedPhone)
            switch role {
            case .sender:    entry.usedAsSender = true
            case .recipient: entry.usedAsRecipient = true
            }
            addresses.append(entry)
        }
        persist()
    }

    private static func normalizedDigits(_ s: String) -> String {
        let digits = s.filter(\.isNumber)
        return String(digits.suffix(10))
    }

    func delete(_ entry: SavedAddress) {
        addresses.removeAll { $0.id == entry.id }
        persist()
    }

    /// Delete all data for the current user (anonymous sign-out discard path).
    func clearAllData() {
        addresses = []
        try? FileManager.default.removeItem(at: storageURL)
    }

    // MARK: - Merge (anonymous → named account)

    /// Merge the anonymous user's address book into a named account's, then delete the anonymous file.
    func mergeAnonymousData(from anonymousID: String, into targetID: String) {
        let anonURL = AddressBookManager.storageURL(for: anonymousID)
        let targetURL = AddressBookManager.storageURL(for: targetID)

        let anonAddresses = load(from: anonURL)
        var targetAddresses = load(from: targetURL)

        for entry in anonAddresses {
            if !targetAddresses.contains(where: {
                $0.name.caseInsensitiveCompare(entry.name) == .orderedSame
            }) {
                targetAddresses.append(entry)
            }
        }

        if let data = try? JSONEncoder().encode(targetAddresses) {
            try? data.write(to: targetURL, options: .atomic)
        }

        try? FileManager.default.removeItem(at: anonURL)
        addresses = []
    }

    // MARK: - Persistence

    private static func storageURL(for userID: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("address_book_\(userID).json")
    }

    private var storageURL: URL { AddressBookManager.storageURL(for: currentUserID) }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(addresses)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("AddressBookManager: failed to save — \(error)")
        }
    }

    private func load() {
        addresses = load(from: storageURL)
    }

    private func load(from url: URL) -> [SavedAddress] {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode([SavedAddress].self, from: data)
        else { return [] }
        return saved
    }
}
