import SwiftUI
import Combine
import UserNotifications
import Supabase

/// Push notifications for replies and emoji reactions (see
/// carddrop/push_notifications_plan.md). The server sends the pushes
/// (`_shared/push.ts`); this class asks permission, registers the device token
/// with the `register-push-token` function, keeps the user's single
/// "Replies and reactions" switch (users.notify_replies), and remembers which
/// card a tapped push is about.
@MainActor
final class PushNotificationManager: ObservableObject {
    static let shared = PushNotificationManager()

    /// Card id from a tapped push; PostcardsView opens its Sent Card sheet and clears it.
    @Published var pendingCardID: UUID?
    /// Drives the short explanation shown before the system permission prompt.
    @Published var showPrePrompt = false
    @Published private(set) var notifyReplies = true
    @Published private(set) var systemStatus: UNAuthorizationStatus = .notDetermined

    enum SwitchResult { case ok, failed, needsSystemSettings }

    private let promptedKey = "push.promptedAfterFirstSend"
    private let tokenKey = "push.deviceToken"

    // Debug builds run from Xcode get sandbox tokens; TestFlight and App Store
    // builds get production tokens.
    private var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    private nonisolated struct RegisterBody: Encodable {
        let action: String
        let token: String?
        let environment: String?
        let notifyReplies: Bool?
    }

    // MARK: - Permission

    func refreshSystemStatus() async {
        systemStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Called once the user has sent a card and is back on the gallery: shows
    /// the explanation, once ever, and only if iOS hasn't been asked yet.
    func offerPermissionIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: promptedKey) else { return }
        Task {
            await refreshSystemStatus()
            guard systemStatus == .notDetermined else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            showPrePrompt = true
        }
    }

    /// "Not Now" on the explanation: don't ask again automatically.
    func declinePrePrompt() {
        UserDefaults.standard.set(true, forKey: promptedKey)
    }

    /// Shows the iOS permission prompt and, if allowed, registers for pushes.
    @discardableResult
    func requestPermission() async -> Bool {
        UserDefaults.standard.set(true, forKey: promptedKey)
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        await refreshSystemStatus()
        if granted { UIApplication.shared.registerForRemoteNotifications() }
        return granted
    }

    // MARK: - Session / token

    /// Called whenever a signed-in session starts or resumes.
    func sessionDidStart(userID: UUID) {
        Task {
            await refreshSystemStatus()
            if systemStatus == .authorized || systemStatus == .provisional {
                UIApplication.shared.registerForRemoteNotifications()
            }
            await loadSwitch(userID)
        }
    }

    func didRegister(token: String) {
        UserDefaults.standard.set(token, forKey: tokenKey)
        Task { await syncToken() }
    }

    private func syncToken() async {
        guard let token = UserDefaults.standard.string(forKey: tokenKey) else { return }
        _ = try? await supabase.functions.invoke(
            "register-push-token",
            options: FunctionInvokeOptions(body: RegisterBody(action: "register", token: token, environment: environment, notifyReplies: nil))
        )
    }

    /// Sign-out: stop pushes for this device (must run before the session ends).
    func unregister() async {
        guard let token = UserDefaults.standard.string(forKey: tokenKey) else { return }
        _ = try? await supabase.functions.invoke(
            "register-push-token",
            options: FunctionInvokeOptions(body: RegisterBody(action: "unregister", token: token, environment: nil, notifyReplies: nil))
        )
        UserDefaults.standard.removeObject(forKey: tokenKey)
        notifyReplies = true
    }

    // MARK: - The "Replies and reactions" switch

    private func loadSwitch(_ userID: UUID) async {
        nonisolated struct Row: Decodable { let notify_replies: Bool? }
        let row = try? await supabase
            .from("users")
            .select("notify_replies")
            .eq("id", value: userID.uuidString)
            .single()
            .execute()
            .value as Row
        notifyReplies = row?.notify_replies ?? true
    }

    /// Profile > Settings checkbox. Turning on asks iOS for permission first if
    /// it hasn't been asked; if the user already refused in iOS Settings, returns
    /// .needsSystemSettings so the screen can point them there.
    func setNotifyReplies(_ on: Bool) async -> SwitchResult {
        if on {
            await refreshSystemStatus()
            if systemStatus == .notDetermined { await requestPermission() }
            if systemStatus == .denied { return .needsSystemSettings }
        }
        do {
            try await supabase.functions.invoke(
                "register-push-token",
                options: FunctionInvokeOptions(body: RegisterBody(action: "settings", token: nil, environment: nil, notifyReplies: on))
            )
            notifyReplies = on
            return .ok
        } catch {
            return .failed
        }
    }
}

/// Receives the system push callbacks (SwiftUI has no direct hook for them).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in PushNotificationManager.shared.didRegister(token: hex) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Push registration failed: \(error)")
    }

    // Show the banner even while the app is open.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // Tapping a push opens that card's Sent Card sheet.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let idString = response.notification.request.content.userInfo["cardID"] as? String
        await MainActor.run {
            PushNotificationManager.shared.pendingCardID = idString.flatMap { UUID(uuidString: $0) }
        }
    }
}
