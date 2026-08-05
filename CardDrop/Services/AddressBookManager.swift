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

    func saveIfNew(name: String, address: String, email: String = "", phone: String = "", role: AddressRole) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddr = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let idx = addresses.firstIndex(where: {
            $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
        }) {
            switch role {
            case .sender:    addresses[idx].usedAsSender = true
            case .recipient: addresses[idx].usedAsRecipient = true
            }
            if !trimmedAddr.isEmpty { addresses[idx].address = trimmedAddr }
            if !email.isEmpty { addresses[idx].email = email }
            if !phone.isEmpty { addresses[idx].phone = phone }
            addresses[idx].lastUsed = Date()
        } else {
            var entry = SavedAddress(name: trimmedName, address: trimmedAddr, email: email, phone: phone)
            switch role {
            case .sender:    entry.usedAsSender = true
            case .recipient: entry.usedAsRecipient = true
            }
            addresses.append(entry)
        }
        persist()
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
