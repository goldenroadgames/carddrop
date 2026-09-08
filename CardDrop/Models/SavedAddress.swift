import Foundation

enum AddressRole {
    case sender, recipient
}

struct SavedAddress: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var nickname: String = ""    // informal name from the Names step, e.g. "Mom"
    var address: String          // multiline, formatted
    var email: String = ""
    var phone: String = ""
    var usedAsSender: Bool = false
    var usedAsRecipient: Bool = false
    var lastUsed: Date = Date()
}
