import SwiftUI

// Explicitly-styled toolbar/nav-bar button — deliberately avoids the system's
// default bar-button appearance (which iOS reshapes per-version, e.g. iOS 26's
// Liquid Glass auto-wraps plain toolbar buttons in translucent capsule chrome).
// Use this anywhere a Cancel/Done/Close/Save-style control sits in a toolbar,
// so it renders identically across iOS versions.
struct ToolbarPillButton: View {
    enum Emphasis {
        case neutral   // Cancel / Close / Skip
        case primary   // Done / Save / confirmation actions
    }

    // .pill: the usual gray-capsule chrome. .bare: plain brandBlue text with
    // no background at all, for spots that want a truly unadorned control
    // (still routed through toolbarPillItem so it's immune to iOS 26's
    // shared Liquid Glass background).
    enum Style {
        case pill
        case bare
    }

    let title: String
    var emphasis: Emphasis = .neutral
    var style: Style = .pill
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            switch style {
            case .pill:
                Text(title)
                    .font(.system(size: 16, weight: emphasis == .primary ? .semibold : .regular))
                    .foregroundColor(isDisabled ? .secondary.opacity(0.4) : (emphasis == .primary ? .brandBlue : .primary))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            case .bare:
                Text(title)
                    .font(.system(size: 16, weight: emphasis == .primary ? .semibold : .medium))
                    .foregroundColor(isDisabled ? .brandBlue.opacity(0.4) : .brandBlue)
                    // Bare (no background/padding to naturally reserve
                    // space) can get squeezed and truncated by how little
                    // width the system proposes to a leading toolbar item
                    // next to a wide centered title — force it to lay out
                    // at its full intrinsic width instead of shrinking.
                    .fixedSize()
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

// Wraps a ToolbarPillButton in a ToolbarItem at the given placement and, on
// iOS 26+, hides the shared Liquid Glass background the OS otherwise draws
// around that toolbar item regardless of the button's own explicit styling
// (ToolbarPillButton alone isn't enough to opt out — sharedBackgroundVisibility
// is a ToolbarContent-level modifier, not something the button view itself
// can apply). Use this instead of a bare `ToolbarItem { ToolbarPillButton(...) }`
// everywhere a Cancel/Done/Send-style toolbar button appears.
@ToolbarContentBuilder
func toolbarPillItem(
    _ title: String,
    placement: ToolbarItemPlacement,
    emphasis: ToolbarPillButton.Emphasis = .neutral,
    style: ToolbarPillButton.Style = .pill,
    isDisabled: Bool = false,
    action: @escaping () -> Void
) -> some ToolbarContent {
    if #available(iOS 26.0, *) {
        ToolbarItem(placement: placement) {
            ToolbarPillButton(title: title, emphasis: emphasis, style: style, isDisabled: isDisabled, action: action)
        }
        .sharedBackgroundVisibility(.hidden)
    } else {
        ToolbarItem(placement: placement) {
            ToolbarPillButton(title: title, emphasis: emphasis, style: style, isDisabled: isDisabled, action: action)
        }
    }
}
