import Foundation

struct LocalAccount: Codable, Identifiable {
    var id: String { userID }
    let userID: String
    let displayName: String  // email address
}

/// Persists a record of every named (non-anonymous) account that has ever signed in on this device.
/// Used to offer merge targets when an anonymous user signs out.
class AccountRegistry {
    static let shared = AccountRegistry()
    private init() {}

    private var storageURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("account_registry.json")
    }

    func register(userID: String, displayName: String) {
        var accounts = all()
        guard !accounts.contains(where: { $0.userID == userID }) else { return }
        accounts.append(LocalAccount(userID: userID, displayName: displayName))
        save(accounts)
    }

    func all() -> [LocalAccount] {
        guard let data = try? Data(contentsOf: storageURL),
              let accounts = try? JSONDecoder().decode([LocalAccount].self, from: data)
        else { return [] }
        return accounts
    }

    private func save(_ accounts: [LocalAccount]) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
