import Foundation
import Combine

final class AppSettings: ObservableObject {
    @Published var familyMode: Bool {
        didSet { UserDefaults.standard.set(familyMode, forKey: "familyMode") }
    }

    init() {
        // Default to true (Family Mode on) if never explicitly set
        if UserDefaults.standard.object(forKey: "familyMode") != nil {
            familyMode = UserDefaults.standard.bool(forKey: "familyMode")
        } else {
            familyMode = true
        }
    }
}
