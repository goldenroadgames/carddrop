import SwiftUI
import Supabase
import CoreText

@main
struct CardDropApp: App {
    @StateObject private var authManager = AuthManager()
    @StateObject private var addressBook = AddressBookManager()
    @StateObject private var draftManager = DraftManager()
    @StateObject private var appSettings = AppSettings()
    @State private var didSkipAuth = false

    init() {
        registerBurstFonts()
        clearKeychainOnFreshInstall()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated && (!authManager.isAnonymous || didSkipAuth) {
                    MainTabView()
                        .environmentObject(authManager)
                        .environmentObject(addressBook)
                        .environmentObject(draftManager)
                        .environmentObject(appSettings)
                } else {
                    AuthView(onSkip: { didSkipAuth = true })
                        .environmentObject(authManager)
                        .environmentObject(draftManager)
                        .environmentObject(addressBook)
                }
            }
            .dynamicTypeSize(.medium ... .xxxLarge)
            .onOpenURL { url in
                Task {
                    // User tapped the confirmation link in their email.
                    // Set send_unlocked = true — this is what opens the send/IAP gates.
                    try? await supabase.auth.session(from: url)
                    try? await supabase.auth.update(
                        user: UserAttributes(data: ["send_unlocked": .bool(true)])
                    )
                }
            }
            .task(id: authManager.currentUserID) {
                if let idString = authManager.currentUserID,
                   let id = UUID(uuidString: idString) {
                    if authManager.isAnonymous {
                        UserService.handleNewAnonymousSession(newID: idString)
                    }
                    draftManager.setUser(idString)
                    addressBook.setUser(idString)
                    if !authManager.isAnonymous {
                        await CardRestoreService.syncIfNeeded(userID: idString, draftManager: draftManager)
                    }
                    let sessionValid = await UserService.upsertUser(id: id)
                    if !sessionValid {
                        try? await supabase.auth.signOut()
                        return
                    }
                    if !authManager.isAnonymous && !authManager.isEmailVerified {
                        await authManager.refreshSessionAsync()
                    }
                } else {
                    draftManager.clearUser()
                    addressBook.clearUser()
                }
            }
        }
    }
}

// MARK: - Fresh install Keychain wipe

private func clearKeychainOnFreshInstall() {
    let key = "hasLaunchedBefore"
    guard !UserDefaults.standard.bool(forKey: key) else { return }
    UserDefaults.standard.set(true, forKey: key)
    Task { try? await supabase.auth.signOut() }
}

// MARK: - Burst font registration
// Registers Bangers.ttf and Creepster.ttf from the app bundle so Font.custom() can find them.
// The font files must be added to the Xcode project target (Build Phases > Copy Bundle Resources).
// Typical Xcode bundle paths: root of bundle, or inside "fonts" or "Assets/fonts" subfolder.

private func registerBurstFonts() {
    let names = ["Bangers-Regular", "Creepster-Regular"]
    let subdirs: [String?] = [nil, "fonts", "Assets/fonts"]
    for name in names {
        for subdir in subdirs {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: subdir) {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
                break
            }
        }
    }
}
