import SwiftUI

// MARK: - App Theme (chrome only — never the postcard front/back content)
//
// Two named looks the user can switch between: "Vintage" (today's flat
// solid-color chrome) and "Modern" (glassmorphism — translucent material
// backgrounds, soft border, blurred shadow). Applies ONLY to app UI
// (buttons, toggles, nav/list rows) — the postcard's own front/back
// rendering (fonts/colors the user picks for their card) is untouched
// regardless of this setting.

enum AppTheme: String, Codable, CaseIterable {
    case vintage
    case modern

    var displayName: String {
        switch self {
        case .vintage: return "Vintage"
        case .modern:  return "Modern"
        }
    }
}

struct UITheme {
    var accentColor: Color
    // When true, surfaces use a translucent Material (glassmorphism)
    // instead of a solid color — see `.themedSurface(_:cornerRadius:)`.
    var useGlassSurface: Bool
    var surfaceColor: Color
    var cornerRadius: CGFloat
    var borderColor: Color?
    var borderWidth: CGFloat
    var shadowRadius: CGFloat
    var shadowOpacity: Double
    var textOnAccent: Color

    static let vintage = UITheme(
        accentColor: .brandBlue,
        useGlassSurface: false,
        surfaceColor: Color(.secondarySystemBackground),
        cornerRadius: 999,
        borderColor: nil,
        borderWidth: 0,
        shadowRadius: 0,
        shadowOpacity: 0,
        textOnAccent: .white
    )

    // Starts as an exact copy of `.vintage` — tuned incrementally from here
    // to become visually distinct.
    static let modern = UITheme(
        accentColor: .brandBlue,
        useGlassSurface: false,
        surfaceColor: Color(.secondarySystemBackground),
        cornerRadius: 999,
        borderColor: nil,
        borderWidth: 0,
        shadowRadius: 0,
        shadowOpacity: 0,
        textOnAccent: .white
    )

    static func current(for theme: AppTheme) -> UITheme {
        theme == .modern ? .modern : .vintage
    }
}

// MARK: - Themed surface modifier
//
// Applies this theme's surface (glass material or solid color), corner
// radius, optional border, and optional shadow in one call — the standard
// "chrome container" look for buttons/toggles/panels. Use instead of
// hardcoding `.background(Color(.secondarySystemBackground))` etc. so a
// view automatically follows whichever theme is active.
struct ThemedSurface: ViewModifier {
    let theme: UITheme
    var cornerRadius: CGFloat? = nil

    func body(content: Content) -> some View {
        let radius = cornerRadius ?? theme.cornerRadius
        content
            .background {
                Group {
                    if theme.useGlassSurface {
                        RoundedRectangle(cornerRadius: radius).fill(.regularMaterial)
                    } else {
                        RoundedRectangle(cornerRadius: radius).fill(theme.surfaceColor)
                    }
                }
            }
            .overlay {
                if let borderColor = theme.borderColor {
                    RoundedRectangle(cornerRadius: radius).stroke(borderColor, lineWidth: theme.borderWidth)
                }
            }
            .cornerRadius(radius)
            // Always applied (not caller-opt-in) — vintage's shadowOpacity/
            // Radius are both 0, so this is a no-op there. Previously this
            // required each call site to pass `withShadow: true`, which
            // nothing ever did, so Modern's shadow silently never appeared.
            .shadow(
                color: Color.black.opacity(theme.shadowOpacity),
                radius: theme.shadowRadius,
                x: 0, y: theme.shadowOpacity > 0 ? 4 : 0
            )
    }
}

extension View {
    func themedSurface(_ theme: UITheme, cornerRadius: CGFloat? = nil) -> some View {
        modifier(ThemedSurface(theme: theme, cornerRadius: cornerRadius))
    }
}
