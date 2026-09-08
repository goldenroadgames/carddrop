import Foundation
import Combine

final class AppSettings: ObservableObject {
    // App UI chrome theme — "Vintage" (today's look) vs "Modern"
    // (glassmorphism). Never affects postcard front/back rendering.
    @Published var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "appTheme") }
    }

    // Toggle removed for now (see [[app_theme_background_gradient]] /
    // memory) — always resolves to Vintage regardless of `theme`'s stored
    // value, so a device that previously had Modern selected doesn't
    // silently keep it. `theme` itself is left in place so the toggle can
    // come back without re-deriving this wiring.
    var uiTheme: UITheme { .vintage }

    init() {
        if let raw = UserDefaults.standard.string(forKey: "appTheme"), let saved = AppTheme(rawValue: raw) {
            theme = saved
        } else {
            theme = .vintage
        }
    }
}
