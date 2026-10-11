import SwiftUI
import Supabase
import CoreText
import StripePaymentSheet

@main
struct CardDropApp: App {
    @StateObject private var authManager = AuthManager()
    @StateObject private var addressBook = AddressBookManager()
    @StateObject private var draftManager = DraftManager()
    @StateObject private var appSettings = AppSettings()
    @State private var didSkipAuth = false
    @State private var isSuspended = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        registerCustomFonts()
        clearKeychainOnFreshInstall()
        StripeAPI.defaultPublishableKey = StripeConfig.publishableKey

        // Semi-bold titles on every segmented picker (Sent/Drafts/Rings,
        // Postcards/Profile, Canvas Setup). SwiftUI ignores .fontWeight on
        // these, so it has to go through UIKit's appearance proxy. Delete
        // this block to revert.
        let segmentFont: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13, weight: .semibold)]
        UISegmentedControl.appearance().setTitleTextAttributes(segmentFont, for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes(segmentFont, for: .selected)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isSuspended {
                    SuspendedView()
                        .environmentObject(authManager)
                        .environmentObject(draftManager)
                        .environmentObject(addressBook)
                } else if authManager.isAuthenticated && (!authManager.isAnonymous || didSkipAuth) {
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
            // Lock text to the system's standard size app-wide, ignoring the user's
            // accessibility "Larger Text" setting — this app's layouts are pixel-tuned
            // and don't tolerate Dynamic Type scaling.
            .dynamicTypeSize(.large)
            // A suspension can land while the app is backgrounded (the 3rd complaint),
            // so recheck whenever it comes back to the foreground.
            .onChange(of: scenePhase) {
                guard scenePhase == .active else { return }
                Task {
                    if let suspended = await SuspensionService.isSuspended() {
                        isSuspended = suspended
                    }
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
                        await CardRestoreService.refreshReported(userID: idString, draftManager: draftManager)
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
                    if let suspended = await SuspensionService.isSuspended() {
                        isSuspended = suspended
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

// MARK: - Custom font registration
// Registers bundled TTFs (burst captions + Greetings overlay script) so Font.custom() can find them.
// The font files must be added to the Xcode project target (Build Phases > Copy Bundle Resources).
// Typical Xcode bundle paths: root of bundle, or inside "fonts" or "Assets/fonts" subfolder.

private func registerCustomFonts() {
    let names = ["Bangers-Regular", "Creepster-Regular", "DancingScript-VariableFont_wght", "BowlbyOneSC-Regular", "SpecialElite-Regular", "CourierPrime-Regular"]
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
