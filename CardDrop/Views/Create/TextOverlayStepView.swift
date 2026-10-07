import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

// MARK: - Step View

// Publishes the canvas's current imgSize up to the top-level body, which
// needs it in the .safeAreaInset closure (outside the GeometryReader that
// computes it) to seed a newly-added text overlay's default width.
private struct ImgSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

// Returns the first SF Symbol name that exists on the running iOS version
// (UIImage(systemName:) is nil for unknown names); falls back to the last.
private func firstAvailableSymbol(_ names: String...) -> String {
    names.first { UIImage(systemName: $0) != nil } ?? names.last!
}

// The "Save" pill, exactly as the Greetings edit panel has always drawn it
// (apply it to a plain Button): shared so all the edit panels and quick sheets
// use literally the same code and can't drift apart.
extension View {
    func savePill() -> some View {
        self
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(999)
    }
}

// A canned font/background color pair for the Caption add sheet. Only the
// black-font presets get a (black) border; the rest start with none (the user
// can still turn one on, or set it to Match, in the full panel).
private struct CaptionColorPreset: Identifiable {
    let id: Int
    let font: Color
    let background: Color
    let border: Bool
    var borderUsesFontColor: Bool = false

    // First is the default.
    static let all: [CaptionColorPreset] = [
        CaptionColorPreset(id: 0, font: .black,         background: .white,          border: true),
        CaptionColorPreset(id: 1, font: .black,         background: .standardYellow, border: true),
        CaptionColorPreset(id: 2, font: .greetingsRed,  background: .white,          border: false),
        CaptionColorPreset(id: 3, font: .brandBlue,     background: .white,          border: false),
        CaptionColorPreset(id: 4, font: .white,         background: .black,          border: false),
        CaptionColorPreset(id: 5, font: .white,         background: .greetingsRed,   border: false),
        CaptionColorPreset(id: 6, font: .white,         background: .brandBlue,      border: false),
    ]
}

extension CaptionColorPreset {
    // The preset whose font + background match this caption's colors, or nil if
    // they were customized (in the full panel). Compared as RGBA with a small
    // tolerance since SwiftUI Color's == isn't reliable across color spaces.
    static func matching(font: Color, background: Color) -> CaptionColorPreset? {
        func rgba(_ c: Color) -> [CGFloat] {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
            return [r, g, b, a]
        }
        func same(_ x: Color, _ y: Color) -> Bool {
            zip(rgba(x), rgba(y)).allSatisfy { abs($0 - $1) < 0.01 }
        }
        return all.first { same($0.font, font) && same($0.background, background) }
    }
}

// What the Caption sheet does to an EXISTING caption when opened from a tap on
// the card: each control edits the caption live, and Delete removes it.
private struct CaptionEditActions {
    let setText: (String) -> Void
    let setStyle: (TextBgStyle) -> Void
    let setColors: (CaptionColorPreset) -> Void
    let delete: () -> Void
}

// Small sheet shown when Caption is tapped: enter the phrase (may be left
// blank), pick a container style and a color preset, then Save creates the
// overlay (the trash icon closes without adding one). "More fonts
// and colors" adds it and opens the full edit panel. Tapping an existing caption
// on the card opens this same sheet in edit mode (`edit` set): changes apply
// live and the trash icon deletes the caption.
private struct CaptionQuickAddSheet: View {
    let edit: CaptionEditActions?
    let onAdd: (String, TextBgStyle, CaptionColorPreset) -> Void
    // New: add the caption, then open the full panel. Edit: just open the panel.
    let onMore: (String, TextBgStyle, CaptionColorPreset) -> Void
    let onClose: () -> Void   // hides the panel (the step owns the show flag)
    @State private var text: String
    @State private var style: TextBgStyle
    // nil = an existing caption whose colors don't match any preset.
    @State private var colors: CaptionColorPreset?

    init(edit: CaptionEditActions? = nil,
         initialText: String = "",
         initialStyle: TextBgStyle = .speech,
         initialColors: CaptionColorPreset? = CaptionColorPreset.all[0],
         onAdd: @escaping (String, TextBgStyle, CaptionColorPreset) -> Void,
         onMore: @escaping (String, TextBgStyle, CaptionColorPreset) -> Void,
         onClose: @escaping () -> Void) {
        self.onClose = onClose
        self.edit = edit
        self.onAdd = onAdd
        self.onMore = onMore
        _text = State(initialValue: initialText)
        _style = State(initialValue: initialStyle)
        _colors = State(initialValue: initialColors)
    }
    @FocusState private var textFocused: Bool
    private let charLimit = 40
    private let styleOrder = TextBgStyle.displayOrder
    private let labelGap: CGFloat = 6       // label → its control (was 16)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: labelGap) {
            Text(edit == nil ? "Enter Caption" : "Caption")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.brandBlue)
            // Vertical axis: wraps, and Return inserts a line break. Reserves
            // exactly 3 rows of height.
            TextField("Your caption", text: $text, axis: .vertical)
                .lineLimit(3, reservesSpace: true)
                .textFieldStyle(.roundedBorder)
                .focused($textFocused)
                .onChange(of: text) { _, new in
                    if new.count > charLimit { text = String(new.prefix(charLimit)) }
                    edit?.setText(text)
                }
            }

            VStack(alignment: .leading, spacing: labelGap) {
            Text("Style")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.brandBlue)
            HStack(spacing: 8) {
                ForEach(styleOrder, id: \.self) { s in
                    Button(action: { style = s; edit?.setStyle(s) }) {
                        Image(systemName: s.systemImage)
                            .font(.system(size: 18))
                            .accessibilityLabel(s.displayName)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(style == s ? Color.accentColor : Color(.secondarySystemBackground))
                        .foregroundColor(style == s ? .white : .primary)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            }

            VStack(alignment: .leading, spacing: labelGap) {
            Text("Color")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.brandBlue)
            // Each swatch: the preset's background color as a circle, with an
            // "A" in its font color.
            HStack(spacing: 8) {
                ForEach(CaptionColorPreset.all) { preset in
                    Button(action: { colors = preset; edit?.setColors(preset) }) {
                        Text("A")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(preset.font)
                            .frame(width: 36, height: 36)
                            .background(preset.background)
                            .clipShape(Circle())
                            // The preset's real border (black, or the font color),
                            // drawn inside the circle so the swatch previews the
                            // finished look — and a white border stays visible
                            // against the sheet's white background.
                            .overlay(Circle().strokeBorder(
                                preset.borderUsesFontColor ? preset.font : Color.black,
                                lineWidth: 3)
                                .opacity(preset.border ? 1 : 0))
                            .overlay(
                                Circle()
                                    .stroke(Color.accentColor, lineWidth: 2.5)
                                    .padding(-3)
                                    .opacity(colors?.id == preset.id ? 1 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 3)
            }

            // Same order as the full panels' last row: Save, trash.
            HStack(spacing: 8) {
                // Same pill as the "Save" button in the full caption panel.
                Button("Save") {
                    // Edit mode has already applied every change live.
                    if edit == nil { onAdd(text, style, colors ?? CaptionColorPreset.all[0]) }
                    onClose()
                }
                .savePill()
                // Same trash button as the full edit panels. On a new caption
                // (nothing added yet) it just closes without adding one.
                Button(action: { edit?.delete(); onClose() }) {
                    Image(systemName: "trash").foregroundColor(.red)
                }
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
                Spacer()
                Button("More fonts and colors") {
                    onMore(text, style, colors ?? CaptionColorPreset.all[0])
                    onClose()
                }
                .font(.subheadline.weight(.semibold))   // same as the Save pill
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
        // Same padding + opaque background as the full edit panels; the step's
        // bottom overlay supplies the material, corners, margins and shadow.
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        // Edit mode doesn't auto-focus: the keyboard would cover the card.
        .onAppear { textFocused = edit == nil }
    }
}

// Small sheet shown when Greetings is tapped and the card has no badge yet:
// Intro (top script line, prefilled "greetings from"), Marquee (the big word,
// prefilled "CardDrop"; if the user clears it, it stays blank — nothing refills
// it), and Position. Colors/halo/background use defaults; the
// full panel (tap the badge) has everything else.
private struct GreetingsQuickAddSheet: View {
    // Starting values (the parent has already put a badge with these on the
    // card); `onChange` fires on every edit so the card's badge updates live.
    let initialIntro: String
    let initialMarquee: String
    let initialPosition: GreetingsFixedPosition
    let initialColor: GreetingsBadgeColor
    let onChange: (String, String, GreetingsFixedPosition, GreetingsBadgeColor) -> Void
    let onAdd: () -> Void
    // Non-nil = editing the badge already on the card (trash deletes it);
    // nil = a new badge (trash closes without adding).
    let onDelete: (() -> Void)?
    // New: confirms the add and opens the full panel. Edit: just opens the panel.
    let onMore: () -> Void
    let onClose: () -> Void   // hides the panel (the step owns the show flag)
    @State private var intro: String
    @State private var marquee: String
    @State private var position: GreetingsFixedPosition
    @State private var badgeColor: GreetingsBadgeColor
    @FocusState private var focusedField: Field?
    private enum Field { case intro, marquee }
    private let introLimit = 25
    private let marqueeLimit = 20
    private let labelWidth: CGFloat = 104   // wide enough for "Background" at 17pt semibold

    init(initialIntro: String, initialMarquee: String, initialPosition: GreetingsFixedPosition,
         initialColor: GreetingsBadgeColor,
         onChange: @escaping (String, String, GreetingsFixedPosition, GreetingsBadgeColor) -> Void,
         onAdd: @escaping () -> Void,
         onDelete: (() -> Void)? = nil,
         onMore: @escaping () -> Void,
         onClose: @escaping () -> Void) {
        self.onClose = onClose
        self.initialIntro = initialIntro
        self.initialMarquee = initialMarquee
        self.initialPosition = initialPosition
        self.initialColor = initialColor
        self.onChange = onChange
        self.onAdd = onAdd
        self.onDelete = onDelete
        self.onMore = onMore
        _intro = State(initialValue: initialIntro)
        _marquee = State(initialValue: initialMarquee)
        _position = State(initialValue: initialPosition)
        _badgeColor = State(initialValue: initialColor)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.brandBlue)
            .frame(width: labelWidth, alignment: .leading)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                label("Intro")
                TextField("greetings from", text: $intro)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .intro)
                    .onChange(of: intro) { _, new in
                        if new.count > introLimit { intro = String(new.prefix(introLimit)) }
                    }
            }

            HStack(spacing: 8) {
                label("Marquee")
                TextField("Mom, Missouri, Buddy…", text: $marquee)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .marquee)
                    .onChange(of: marquee) { _, new in
                        if new.count > marqueeLimit { marquee = String(new.prefix(marqueeLimit)) }
                    }
            }

            HStack(spacing: 8) {
                label("Position")
                // Same segmented control the Write step's phrase filter uses.
                CompactSegmentedControl(
                    options: GreetingsFixedPosition.allCases.map { $0.displayName },
                    selection: Binding(
                        get: { position.displayName },
                        set: { name in
                            if let p = GreetingsFixedPosition.allCases.first(where: { $0.displayName == name }) {
                                position = p
                            }
                        }
                    )
                )
            }

            // Badge background color (no opacity here — that's in the full panel).
            HStack(spacing: 8) {
                label("Background")
                ForEach(GreetingsBadgeColor.allCases) { choice in
                    Group {
                        if choice == .transparent {
                            Image(systemName: "circle.slash")
                                .font(.system(size: 26))
                                .foregroundColor(.secondary)
                                .frame(width: 28, height: 28)
                        } else {
                            Circle().fill(choice.color)
                                .frame(width: 28, height: 28)
                        }
                    }
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(badgeColor == choice ? 0.8 : 0.15),
                                    lineWidth: badgeColor == choice ? 2.5 : 1)
                    )
                    .frame(maxWidth: .infinity)
                    .onTapGesture { badgeColor = choice }
                }
            }

            // Same order as the full panels' last row: Save, trash.
            HStack(spacing: 8) {
                Button("Save") {
                    onAdd()
                    onClose()
                }
                .savePill()
                // Same trash button as the full edit panels. On a new badge
                // (not confirmed yet) the sheet closes unconfirmed and the
                // preview badge is removed.
                Button(action: { onDelete?(); onClose() }) {
                    Image(systemName: "trash").foregroundColor(.red)
                }
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
                Spacer()
                Button("More fonts and colors") {
                    onMore()
                    onClose()
                }
                .font(.subheadline.weight(.semibold))   // same as the Save pill
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
        // Same padding + opaque background as the full edit panels; the step's
        // bottom overlay supplies the material, corners, margins and shadow.
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        // (No auto-focus here, unlike the Caption sheet: the keyboard would
        // cover the card, and the point is to see the default badge on open.)
        // Live: push every edit to the badge already sitting on the card.
        .onChange(of: intro)      { _, _ in onChange(intro, marquee, position, badgeColor) }
        .onChange(of: marquee)    { _, _ in onChange(intro, marquee, position, badgeColor) }
        .onChange(of: position)   { _, _ in onChange(intro, marquee, position, badgeColor) }
        .onChange(of: badgeColor) { _, _ in onChange(intro, marquee, position, badgeColor) }
    }
}

struct TextOverlayStepView: View {
    @ObservedObject var draft: PostcardDraft
    var onNext: () -> Void
    // Back to the Photo step (no picker opened) — the "Alter Photo" link.
    var onAlterPhoto: () -> Void = {}

    @EnvironmentObject private var appSettings: AppSettings

    @State private var selectedIndex: Int? = nil
    @State private var selectedQRIndex: Int? = nil
    @State private var selectedBurstIndex: Int? = nil
    @State private var selectedGreetingsIndex: Int? = nil
    // Renders the photo with whatever filter was already chosen back on
    // Choose Photo — this step doesn't offer a filter picker of its own.
    @State private var cachedFilteredImage: UIImage? = nil
    @State private var lastImgSize: CGSize = .zero
    @State private var keyboardHeight: CGFloat = 0
    @State private var isGeneratingSubjectCutout = false
    @State private var showingCaptionSheet = false
    @State private var showingGreetingsSheet = false
    // Live-preview state for the Greetings quick-add sheet: a real badge is put
    // on the card when the sheet opens and edited as the user types. If the
    // sheet closes without Save, it's removed and the photo/cutout put back.
    @State private var pendingGreetingsImgSize: CGSize = .zero
    @State private var greetingsPreviewID: UUID?
    @State private var greetingsAddConfirmed = false
    @State private var greetingsRestoreScale: CGFloat = 1
    @State private var greetingsRestoreOffset: CGSize = .zero
    @State private var greetingsStartedCutout = false
    // Quick sheets reopened on an EXISTING object (tap on the card): which
    // caption / whether the badge is being edited, what to do once the sheet has
    // closed ("More options" → select the object so the full panel opens;
    // Delete → remove the badge).
    @State private var captionEditID: UUID?
    @State private var pendingFullCaptionID: UUID?
    @State private var greetingsEditing = false
    @State private var greetingsOpenFullPanel = false
    @State private var greetingsDeleteRequested = false
    // Canvas width captured when the Caption button is tapped, since the sheet's
    // onAdd closure runs after the button row's imgSize is out of scope.
    @State private var pendingCaptionCanvasWidth: CGFloat = 0

    private var isEditing: Bool {
        selectedIndex != nil || selectedQRIndex != nil || selectedBurstIndex != nil || selectedGreetingsIndex != nil
    }

    // Live pinch-to-zoom / drag-to-reposition deltas, applied on top of the
    // raw photo (draft.image) before committing into draft.imageScale/
    // imageOffset and re-baking draft.composedImage on gesture end.
    @GestureState private var gestureScale: CGFloat = 1.0
    @GestureState private var gestureDrag: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            // The canvas frame is sized the same whether or not an editor is
            // open — the edit panel floats on top of the canvas (and the
            // "Next" row below) as its own overlay instead of reserving
            // space for itself, so the frame never resizes out from under a
            // text overlay's normalized position mid-edit.
            let frameSize = postcardFrameSize(availableSize: geo.size)
            let imgSize   = imageAreaSize(in: frameSize)

            Group {
            if draft.image == nil {
                emptyPhotoState
            } else {
                mainContent(isEditing: isEditing, frameSize: frameSize, imgSize: imgSize)
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.clear.preference(key: ImgSizeKey.self, value: imgSize))
        }
        .onPreferenceChange(ImgSizeKey.self) { lastImgSize = $0 }
        // Everything below the header down to here is the step's safe
        // content area; the row below is reserved bottom chrome — nothing
        // above should ever render behind or scroll behind it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if draft.image != nil {
                VStack(spacing: 0) {
                    // Kept in the layout (never removed) even while editing —
                    // just hidden — so this inset's measured height, and
                    // therefore the GeometryReader's available size above,
                    // never changes. Previously this row was conditionally
                    // removed via `if !isEditing`, which shrank this inset
                    // and handed the canvas more height right as editing
                    // began, growing the card frame out from under any text
                    // overlay's normalized position/size (very visible in
                    // portrait, where height is usually the binding
                    // constraint) — then shrinking it back on Done.
                    Divider()
                        .opacity(isCoveringControlsOpen ? 0 : 1)
                    addOverlayButtonsRow(imgSize: lastImgSize)
                        .opacity(isCoveringControlsOpen ? 0 : 1)
                        .allowsHitTesting(!isCoveringControlsOpen)
                    Button(action: onNext) {
                        Text("Next: Write Card")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.brandBlue)
                            .foregroundColor(.white)
                            .cornerRadius(999)
                    }
                    .allowsHitTesting(!isCoveringControlsOpen)
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .background(Color(uiColor: .systemBackground))
            }
        }
        // Floats on top of everything above, including the "Next" row in
        // the safeAreaInset — it's sized to its own content and starts low,
        // so it only covers as much of the canvas/"Next" row as it actually
        // needs to. "Next" is intentionally unreachable while this is up;
        // the user backs out via Done or the </> nav to get to it. Lifted
        // by `keyboardHeight` so it rises above the keyboard (covering more
        // of the preview underneath) instead of being covered by it.
        .overlay(alignment: .bottom) {
            // The Caption / Greetings quick panels are the same floating panel
            // as the full edit panels (identical material, corners, margins,
            // shadow), shown in the same spot.
            if isEditing {
                editPanelChrome { editPanel(imgSize: lastImgSize) }
            } else if showingCaptionSheet {
                editPanelChrome { captionSheetContent() }
            } else if showingGreetingsSheet {
                editPanelChrome { greetingsSheetContent() }
            }
        }
        .onChange(of: showingCaptionSheet) { was, now in
            if was && !now { finishCaptionSheet() }
        }
        .onChange(of: showingGreetingsSheet) { was, now in
            if was && !now { finishGreetingsPreview() }
        }
        .animation(.easeInOut(duration: 0.2), value: isEditing)
        .animation(.easeInOut(duration: 0.2), value: showingCaptionSheet)
        .animation(.easeInOut(duration: 0.2), value: showingGreetingsSheet)
        .animation(.easeOut(duration: 0.25), value: keyboardHeight)
        .onAppear {
            updateCachedFilteredImage()
            // DraftManager.load(_:) restores imageScale/imageOffset from the
            // saved snapshot but always reconstructs composedImage as nil
            // (it isn't persisted to disk) — so on every reopen, without
            // this, composedImage stays nil until the user does a NEW
            // pinch/drag, and everything downstream (Preview, print) that
            // reads draft.composedImage falls back to the raw, unzoomed
            // draft.image in the meantime. Re-bake immediately from the
            // restored imageScale/imageOffset so a reopened draft's
            // Preview/print matches its Style It position right away, not
            // only after the user re-adjusts the photo.
            // Also re-clamps to the safe zone — covers drafts saved before
            // this constraint existed, or with a Greetings badge added/
            // repositioned since the photo was last adjusted.
            clampPhotoToSafeZone(imgSize: lastImgSize)
            rerenderComposedImage()
        }
        .onChange(of: draft.filter) { _, _ in updateCachedFilteredImage() }
        .onReceive(draft.$image) { newImage in
            // @Published's publisher fires from willSet — draft.image itself
            // hasn't been updated to the new value yet at this point, so use
            // the value the publisher actually delivers instead of
            // re-reading (stale) draft.image.
            updateCachedFilteredImage(newImage)
        }
        // Without this, the keyboard opening (e.g. typing in the Caption
        // panel) shrinks the whole step's available height by the
        // keyboard's height, on top of the fixed 240pt reserve
        // `postcardFrameSize` already subtracts — easily driving maxHeight
        // to zero/negative and collapsing the canvas to nothing (matches
        // MessageStepView's own fix for the same failure mode — applied as
        // the LAST modifier so it covers the fully composed view, not just
        // the inner GeometryReader). The floating edit panel above still
        // needs to dodge the keyboard (it has the actual TextField), which
        // is why it separately tracks `keyboardHeight` instead of relying on
        // this modifier for that.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            if let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                keyboardHeight = frame.height
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
    }

    private func editPanelChrome<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .background(.regularMaterial)
            .cornerRadius(12)
            .padding(.horizontal, 4)
            .padding(.bottom, 2 + keyboardHeight)
            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: -3)
    }

    // True while anything is open over the bottom of the screen: the edit panel
    // (caption / Greetings / QR / burst) or one of the quick-add sheets.
    private var isCoveringControlsOpen: Bool {
        isEditing || showingCaptionSheet || showingGreetingsSheet
    }

    @ViewBuilder
    private func mainContent(isEditing: Bool, frameSize: CGSize, imgSize: CGSize) -> some View {
            // The card group below sits in the vertical center of this section
            // (a Spacer above and below it). While any control/dialog is open
            // the top Spacer is dropped, so the group moves to the TOP of the
            // section — out from under the panel/sheet/keyboard — and returns
            // to the center when it closes (the step's .animation modifiers
            // animate the move).
            VStack(spacing: 0) {
                if !isCoveringControlsOpen {
                    Spacer(minLength: 0)
                }

                // Pinch hint stays anchored directly above the canvas (with
                // its existing padding).
                VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Text("Pinch to zoom · Drag to reposition")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.brandBlue)
                    Button {
                        draft.imageScale = 1.0
                        draft.imageOffset = .zero
                        rerenderComposedImage()
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle")
                            .foregroundColor(.brandBlue)
                    }
                    .buttonStyle(.plain)
                }
                // Pulled up into the empty lower part of the navigation bar
                // (the inline title only fills its middle) to tighten the gap
                // under "Style It".
                .padding(.top, -15)

                // Canvas
                ZStack {
                    (draft.border == .whiteBorder || draft.border == .decorative) ? Color.white : Color.black

                    ZStack {
                        if let img = cachedFilteredImage {
                            // Back layer: same photo, floored at "just
                            // covers the canvas" — zooms in together with
                            // the front layer past that floor, but never
                            // lets it zoom out below full coverage.
                            // Guarantees every corner (e.g. the top-left,
                            // under a tilted Greetings badge) always shows
                            // real photo content instead of the plain
                            // background color, no matter how the front
                            // layer is panned/zoomed. X position is locked
                            // to the front layer's own horizontal pan (moves
                            // in unison) so wherever the back layer peeks
                            // through, it's horizontally aligned with the
                            // front layer's content rather than showing a
                            // different part of the photo — Y stays fixed/
                            // centered regardless of vertical pan, since
                            // that's what guarantees top/bottom coverage
                            // under the banner. Matches PostcardDraft.
                            // rendered(at:)'s baked output.
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: imgSize.width, height: imgSize.height)
                                .scaleEffect(max(1.0, draft.imageScale * gestureScale))
                                .offset(x: draft.imageOffset.width * imgSize.width + gestureDrag.width, y: 0)
                                .clipped()
                                .allowsHitTesting(false)
                        }

                        if draft.photoMirrorEnabled, let img = cachedFilteredImage, let imageSize = draft.image?.size,
                           imageSize.width > 0, imageSize.height > 0, imgSize.width > 0, imgSize.height > 0 {
                            // Mirror layer (user-toggleable): a vertically-flipped duplicate of
                            // the front layer's own content, anchored so its
                            // bottom edge touches the front layer's actual
                            // top edge — continues the photo as a seamless
                            // reflection into the gap above, instead of the
                            // back layer's independently-cropped (different
                            // part of the photo) view. Same scale/X-offset
                            // as the front layer, so it lines up exactly at
                            // the seam; only the flip and Y position differ.
                            // The back layer above still shows through
                            // beyond the mirror's own extent (a real edge
                            // case only, in extreme zoom-out).
                            let fillScale = max(imgSize.width / imageSize.width, imgSize.height / imageSize.height)
                            let totalScale = fillScale * draft.imageScale * gestureScale
                            let scaledHeight = imageSize.height * totalScale
                            let frontOffsetY = draft.imageOffset.height * imgSize.height + gestureDrag.height
                            let offsetX = draft.imageOffset.width * imgSize.width + gestureDrag.width
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: imgSize.width, height: imgSize.height)
                                .scaleEffect(x: draft.imageScale * gestureScale, y: -(draft.imageScale * gestureScale))
                                .offset(x: offsetX, y: frontOffsetY - scaledHeight)
                                .clipped()
                                .allowsHitTesting(false)
                        }

                        // Directly in front of the back photo layer — if a
                        // drag/zoom leaves part of imgSize uncovered, this
                        // fills that gap with the user's chosen solid color
                        // instead (default .transparent, leaving the back
                        // photo layer above visible as-is), matching
                        // PostcardDraft.rendered(at:)'s baked output exactly.
                        // Any translucent overlay drawn later (e.g. a
                        // Greetings badge) blends with whichever of these
                        // two is actually showing through.
                        draft.canvasBackgroundColor.color
                            .frame(width: imgSize.width, height: imgSize.height)
                            .allowsHitTesting(false)

                        if let img = cachedFilteredImage {
                            // Live pinch/drag preview — full absolute
                            // transform on the raw (filtered) photo, exactly
                            // as the old Choose Photo step did. Committed to
                            // draft.imageScale/imageOffset and re-baked into
                            // draft.composedImage on gesture end.
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: imgSize.width, height: imgSize.height)
                                .scaleEffect(draft.imageScale * gestureScale)
                                .offset(
                                    // draft.imageOffset is stored NORMALIZED
                                    // (fraction of canvas width/height) — see
                                    // PostcardDraft.rendered(at:)'s comment —
                                    // so it must be scaled back up by this
                                    // canvas's own current imgSize to get raw
                                    // points for display here. gestureDrag
                                    // (the live, uncommitted delta) is already
                                    // in this canvas's raw points, added as-is.
                                    x: draft.imageOffset.width * imgSize.width + gestureDrag.width,
                                    y: draft.imageOffset.height * imgSize.height + gestureDrag.height
                                )
                                .clipped()
                                // The photo never needs to handle touches
                                // itself (the dedicated Color.clear layer
                                // below does all gesture recognition) — but
                                // `.scaleEffect` is a geometry effect, so
                                // SwiftUI's hit-testing still follows the
                                // SCALED bounds, not the clipped visual
                                // ones. Without this, a zoomed-in photo's
                                // tappable region can extend past its clip
                                // into whatever's above the canvas (e.g. the
                                // Undo button), intercepting taps there
                                // depending on exactly how it's scaled/panned.
                                .allowsHitTesting(false)
                        }

                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: imgSize.width, height: imgSize.height)
                            // `.simultaneousGesture` rather than `.gesture` —
                            // a pure pinch (MagnificationGesture) with no
                            // panning component, attached via `.gesture`, can
                            // leave the multi-touch session in a state where
                            // the very next single tap ANYWHERE (even the
                            // unrelated Undo button above) gets swallowed,
                            // since `.gesture` claims exclusive priority over
                            // gesture resolution. `.simultaneousGesture`
                            // doesn't claim that exclusivity.
                            .simultaneousGesture(
                                SimultaneousGesture(
                                    MagnificationGesture()
                                        .updating($gestureScale) { value, state, _ in state = value }
                                        .onEnded { value in
                                            // No fixed lower clamp at 1.0 —
                                            // zooming out smaller than "fill"
                                            // is allowed in general (the
                                            // back photo layer + backdrop
                                            // fill handle any resulting gap)
                                            // but clampPhotoToSafeZone below
                                            // still enforces the front layer
                                            // can't leave a gap anywhere
                                            // except behind the Greetings
                                            // banner (if present).
                                            draft.imageScale = max(0.1, draft.imageScale * value)
                                            clampPhotoToSafeZone(imgSize: imgSize)
                                            rerenderComposedImage()
                                        },
                                    DragGesture()
                                        .updating($gestureDrag) { value, state, _ in state = value.translation }
                                        .onEnded { value in
                                            // Normalize the raw-point drag delta by THIS canvas's
                                            // own current size before accumulating, so the stored
                                            // draft.imageOffset stays canvas-size-independent.
                                            draft.imageOffset.width += value.translation.width / imgSize.width
                                            draft.imageOffset.height += value.translation.height / imgSize.height
                                            clampPhotoToSafeZone(imgSize: imgSize)
                                            rerenderComposedImage()
                                        }
                                )
                            )
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    selectedIndex = nil; selectedQRIndex = nil; selectedBurstIndex = nil; selectedGreetingsIndex = nil
                                }
                            )

                        // Z-order (bottom to top): Greetings, Text, Burst
                        // (hidden feature), Invisible Ink — so Invisible Ink
                        // paints highest, Text above Greetings, per user spec.
                        ForEach(draft.greetingsOverlays) { overlay in
                            GreetingsCaptionItemView(
                                overlay: Binding(
                                    get: { draft.greetingsOverlays.first(where: { $0.id == overlay.id }) ?? overlay },
                                    set: { newVal in
                                        if let i = draft.greetingsOverlays.firstIndex(where: { $0.id == overlay.id }) {
                                            draft.greetingsOverlays[i] = newVal
                                        }
                                    }
                                ),
                                canvasSize: imgSize,
                                isSelected: selectedGreetingsIndex == draft.greetingsOverlays.firstIndex(where: { $0.id == overlay.id }),
                                onSelect: {
                                    // Tapping the badge opens the quick sheet in
                                    // edit mode; its "More options" opens the
                                    // full panel.
                                    guard !showingGreetingsSheet, !showingCaptionSheet else { return }
                                    selectedIndex = nil
                                    selectedQRIndex = nil
                                    selectedBurstIndex = nil
                                    startGreetingsEdit(imgSize: imgSize)
                                }
                            )
                        }

                        // "Put subject in front" layer — drawn directly
                        // above the Greetings banner, below Text/Burst/QR
                        // (see Z-order comment above). Uses the exact same
                        // scaleEffect/offset as the front photo layer above
                        // (lines ~269-305) so it tracks pan/zoom in lockstep
                        // with the photo it was cut from — it has no drag/
                        // resize/rotate gesture of its own; there's nothing
                        // to attach one to.
                        if let cutout = draft.subjectCutoutImage {
                            Image(uiImage: cutout)
                                .resizable()
                                .scaledToFill()
                                .frame(width: imgSize.width, height: imgSize.height)
                                .scaleEffect(draft.imageScale * gestureScale)
                                .offset(
                                    x: draft.imageOffset.width * imgSize.width + gestureDrag.width,
                                    y: draft.imageOffset.height * imgSize.height + gestureDrag.height
                                )
                                .clipped()
                                .allowsHitTesting(false)
                        }

                        ForEach(draft.textOverlays) { overlay in
                            TextOverlayItemView(
                                overlay: Binding(
                                    get: { draft.textOverlays.first(where: { $0.id == overlay.id }) ?? overlay },
                                    set: { newVal in
                                        if let i = draft.textOverlays.firstIndex(where: { $0.id == overlay.id }) {
                                            draft.textOverlays[i] = newVal
                                        }
                                    }
                                ),
                                canvasSize: imgSize,
                                printCanvasSize: printCanvasSize,
                                onSelect: {
                                    // Tapping a caption opens the quick sheet in
                                    // edit mode; its "More options" opens the
                                    // full panel.
                                    guard !showingGreetingsSheet, !showingCaptionSheet else { return }
                                    selectedIndex = nil
                                    selectedQRIndex = nil
                                    selectedBurstIndex = nil
                                    selectedGreetingsIndex = nil
                                    captionEditID = overlay.id
                                    showingCaptionSheet = true
                                }
                            )
                        }

                        ForEach(draft.burstOverlays) { overlay in
                            BurstCaptionItemView(
                                overlay: Binding(
                                    get: { draft.burstOverlays.first(where: { $0.id == overlay.id }) ?? overlay },
                                    set: { newVal in
                                        if let i = draft.burstOverlays.firstIndex(where: { $0.id == overlay.id }) {
                                            draft.burstOverlays[i] = newVal
                                        }
                                    }
                                ),
                                canvasSize: imgSize,
                                isSelected: selectedBurstIndex == draft.burstOverlays.firstIndex(where: { $0.id == overlay.id }),
                                onSelect: {
                                    selectedBurstIndex = draft.burstOverlays.firstIndex(where: { $0.id == overlay.id })
                                    selectedIndex = nil
                                    selectedQRIndex = nil
                                    selectedGreetingsIndex = nil
                                }
                            )
                        }

                        ForEach(draft.qrOverlays) { overlay in
                            QROverlayItemView(
                                overlay: Binding(
                                    get: { draft.qrOverlays.first(where: { $0.id == overlay.id }) ?? overlay },
                                    set: { newVal in
                                        if let i = draft.qrOverlays.firstIndex(where: { $0.id == overlay.id }) {
                                            draft.qrOverlays[i] = newVal
                                        }
                                    }
                                ),
                                canvasSize: imgSize,
                                printCanvasSize: printCanvasSize,
                                isSelected: selectedQRIndex == draft.qrOverlays.firstIndex(where: { $0.id == overlay.id }),
                                onSelect: {
                                    selectedQRIndex = draft.qrOverlays.firstIndex(where: { $0.id == overlay.id })
                                    selectedIndex = nil
                                    selectedBurstIndex = nil
                                    selectedGreetingsIndex = nil
                                }
                            )
                        }
                    }
                    .frame(width: imgSize.width, height: imgSize.height)
                    .clipped()
                }
                .frame(width: frameSize.width, height: frameSize.height)
                .compositingGroup()
                .shadow(radius: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

                if !isCoveringControlsOpen {
                    Button(action: onAlterPhoto) {
                        Text("Alter Photo")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.brandBlue)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
                }

                // Any leftover space above/below the canvas (e.g. a short
                // landscape card) is absorbed by these two Spacers rather
                // than pushing content around — the Add-buttons/Invisible-
                // Ink rows and "Next" button live in the .safeAreaInset
                // below, which reserves their real measured height itself
                // instead of guessing, so they can never be squeezed/
                // overlapped.
                Spacer(minLength: 0)
            }
    }

    // Add-buttons row + Invisible Ink row, shown below the canvas when
    // nothing is selected. Lives in the bottom .safeAreaInset (alongside
    // "Next") rather than in mainContent's VStack so its real height is
    // always fully reserved by SwiftUI — previously it sat inside the
    // flexible canvas area sized off a hand-tuned constant, which could
    // undershoot on some devices and let this row overlap "Next".
    @ViewBuilder
    private func addOverlayButtonsRow(imgSize: CGSize) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Button(action: {
                    pendingCaptionCanvasWidth = imgSize.width
                    showingCaptionSheet = true
                }) {
                    Label("Caption", systemImage: firstAvailableSymbol("text.bubble.badge.sparkles", "ellipsis.message"))
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundColor(.primary)
                        .themedSurface(appSettings.uiTheme, cornerRadius: 999)
                }
                Button(action: {
                    if draft.greetingsOverlays.isEmpty {
                        startGreetingsPreview(imgSize: imgSize)
                    } else {
                        // Only one badge per card — edit the existing one.
                        startGreetingsEdit(imgSize: imgSize)
                    }
                }) {
                    Label("Greetings", systemImage: firstAvailableSymbol("rectangle.badge.sparkles", "text.rectangle"))
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundColor(.primary)
                        .themedSurface(appSettings.uiTheme, cornerRadius: 999)
                }
                // Burst feature hidden — code intact, re-enable by restoring this button
                // Button(action: { addBurstOverlay(canvasHeight: imgSize.height) }) {
                //     Label("Burst", systemImage: "star.circle")
                //         .frame(maxWidth: .infinity)
                //         .padding(.vertical, 10)
                //         .background(Color(.secondarySystemBackground))
                //         .foregroundColor(.primary)
                //         .cornerRadius(10)
                // }
            }
            Button(action: {
                if draft.qrOverlays.isEmpty {
                    addQROverlay()
                } else {
                    selectedQRIndex = 0
                    selectedIndex = nil
                    selectedBurstIndex = nil
                    selectedGreetingsIndex = nil
                }
            }) {
                Label("Invisible Ink", systemImage: "eye.slash")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .foregroundColor(.primary)
                    .themedSurface(appSettings.uiTheme, cornerRadius: 999)
            }
        }
        .padding(.horizontal)
        .padding(.top, 6)
    }

    // Style It is never reached without a photo already chosen on Choose
    // Photo (step 0 gates "Next" on it) — this is just a defensive fallback,
    // not a reachable empty state.
    @ViewBuilder
    private var emptyPhotoState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No photo yet")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    // Bakes composedImage at the CANONICAL print resolution (2700x1800 /
    // 1800x2700), never at this step's own small live-viewport size — see
    // [[feedback_editor_print_sync_bitmap]]. Re-deriving the crop at the
    // small on-screen size and then stretching that low-res bitmap up to
    // print size later is exactly the "same formula at two scales" trap:
    // it's mathematically equivalent in theory but leaves composedImage's
    // correctness dependent on the live viewport's current geometry, and
    // produces a blurry low-res bake regardless. Baking once at a fixed
    // canonical size means every consumer (Preview, print, thumbnails)
    // sees the exact same bytes.
    private func rerenderComposedImage() {
        guard draft.image != nil else { return }
        let referenceSize: CGSize = draft.orientation == .landscape
            ? CGSize(width: CardRenderer.frontLongSideBleed, height: CardRenderer.frontShortSideBleed)
            : CGSize(width: CardRenderer.frontShortSideBleed, height: CardRenderer.frontLongSideBleed)
        draft.renderComposedImage(frameSize: imageAreaSize(in: referenceSize))
        rerenderSubjectCutoutComposedImage()
    }

    // Keeps subjectCutoutComposedImage (used by the print bake / any preview
    // built from PostcardFrontCanvas) baked at the same size/transform as
    // composedImage itself, any time either could have changed.
    private func rerenderSubjectCutoutComposedImage() {
        guard draft.image != nil else { return }
        let referenceSize: CGSize = draft.orientation == .landscape
            ? CGSize(width: CardRenderer.frontLongSideBleed, height: CardRenderer.frontShortSideBleed)
            : CGSize(width: CardRenderer.frontShortSideBleed, height: CardRenderer.frontLongSideBleed)
        draft.renderSubjectCutoutComposedImage(frameSize: imageAreaSize(in: referenceSize))
    }

    // "Put subject in front" toggle: tap once to segment the photo's main
    // subject and insert it as a locked layer above the Greetings banner;
    // tap again to remove it. No undo stack — this IS the undo, per user
    // direction. Silent no-op on segmentation failure (no subject found,
    // Vision error) — leaves the card exactly as it was, no error shown.
    private func toggleSubjectCutout() {
        if draft.subjectCutoutImage != nil {
            draft.subjectCutoutImage = nil
            draft.subjectCutoutComposedImage = nil
            return
        }
        guard !isGeneratingSubjectCutout, let source = draft.image else { return }
        isGeneratingSubjectCutout = true
        let filter = draft.filter
        DispatchQueue.global(qos: .userInitiated).async {
            let rawCutout = SubjectCutoutService.generateCutout(from: source)
            let filteredCutout = rawCutout.map { filter.apply(to: $0) }
            DispatchQueue.main.async {
                isGeneratingSubjectCutout = false
                // No banner (e.g. the quick-add sheet was cancelled while this
                // was still running) → nothing for the cutout to sit above.
                guard let filteredCutout, !draft.greetingsOverlays.isEmpty else { return }
                draft.subjectCutoutImage = filteredCutout
                rerenderSubjectCutoutComposedImage()
            }
        }
    }

    // Guarantees the front photo layer never leaves a gap anywhere except
    // behind the Greetings banner (if present) — full width always, full
    // height from canvas bottom up to either the canvas top (no banner) or
    // the banner's own bottom edge (see GreetingsOverlay.safeZoneTopFraction).
    // Raises imageScale to the minimum needed, then clamps imageOffset so
    // the resulting draw rect actually covers that safe zone. Called at the
    // end of every pinch/drag gesture, whenever a Greetings badge is added
    // (which can shrink the safe zone under an already-positioned photo),
    // and on appear (for drafts saved before this constraint existed).
    private func clampPhotoToSafeZone(imgSize: CGSize) {
        guard let imageSize = draft.image?.size,
              imageSize.width > 0, imageSize.height > 0,
              imgSize.width > 0, imgSize.height > 0
        else { return }

        let isLandscape = draft.orientation == .landscape
        let safeTopFraction = GreetingsOverlay.safeZoneTopFraction(for: draft.greetingsOverlays, isLandscape: isLandscape)
        let safeTopY = safeTopFraction * imgSize.height
        let requiredHeight = imgSize.height - safeTopY

        let fillScale = max(imgSize.width / imageSize.width, imgSize.height / imageSize.height)
        let minTotalScale = max(imgSize.width / imageSize.width, requiredHeight / imageSize.height)
        let minImageScale = minTotalScale / fillScale
        if draft.imageScale < minImageScale {
            draft.imageScale = minImageScale
        }

        let totalScale = fillScale * draft.imageScale
        let scaledWidth = imageSize.width * totalScale
        let scaledHeight = imageSize.height * totalScale

        var originX = (imgSize.width - scaledWidth) / 2 + draft.imageOffset.width * imgSize.width
        var originY = (imgSize.height - scaledHeight) / 2 + draft.imageOffset.height * imgSize.height

        // Left/right: always full canvas width, regardless of the banner.
        originX = min(0, max(imgSize.width - scaledWidth, originX))
        // Top/bottom: full canvas bottom up to the safe zone's top edge —
        // gaps are only tolerated above that line (behind the banner).
        originY = min(safeTopY, max(imgSize.height - scaledHeight, originY))

        draft.imageOffset.width  = (originX - (imgSize.width - scaledWidth) / 2) / imgSize.width
        draft.imageOffset.height = (originY - (imgSize.height - scaledHeight) / 2) / imgSize.height
    }

    private func updateCachedFilteredImage(_ overrideImage: UIImage? = nil) {
        guard let base = overrideImage ?? draft.image else { return }
        cachedFilteredImage = draft.filter.apply(to: base)
    }

    @ViewBuilder
    private func editPanel(imgSize: CGSize) -> some View {
        if let idx = selectedIndex, draft.textOverlays.indices.contains(idx) {
            TextOverlayEditPanel(
                overlay: Binding(
                    get: { draft.textOverlays.indices.contains(idx) ? draft.textOverlays[idx] : TextOverlay() },
                    set: { if draft.textOverlays.indices.contains(idx) { draft.textOverlays[idx] = $0 } }
                ),
                canvasSize: imgSize,
                onDelete: { draft.textOverlays.remove(at: idx); selectedIndex = nil },
                onDone: { selectedIndex = nil }
            )
        } else if let idx = selectedQRIndex, draft.qrOverlays.indices.contains(idx) {
            QROverlayEditPanel(
                overlay: Binding(
                    get: { draft.qrOverlays.indices.contains(idx) ? draft.qrOverlays[idx] : QROverlay() },
                    set: { if draft.qrOverlays.indices.contains(idx) { draft.qrOverlays[idx] = $0 } }
                ),
                canvasSize: imgSize,
                printCanvasSize: printCanvasSize,
                onDelete: { draft.qrOverlays.remove(at: idx); selectedQRIndex = nil },
                onDone: { selectedQRIndex = nil }
            )
        } else if let idx = selectedBurstIndex, draft.burstOverlays.indices.contains(idx) {
            BurstCaptionEditPanel(
                overlay: Binding(
                    get: { draft.burstOverlays.indices.contains(idx) ? draft.burstOverlays[idx] : BurstCaptionOverlay() },
                    set: { if draft.burstOverlays.indices.contains(idx) { draft.burstOverlays[idx] = $0 } }
                ),
                onDelete: { draft.burstOverlays.remove(at: idx); selectedBurstIndex = nil },
                onDone: { selectedBurstIndex = nil }
            )
        } else if let idx = selectedGreetingsIndex, draft.greetingsOverlays.indices.contains(idx) {
            GreetingsCaptionEditPanel(
                overlay: Binding(
                    get: { draft.greetingsOverlays.indices.contains(idx) ? draft.greetingsOverlays[idx] : GreetingsOverlay() },
                    set: { if draft.greetingsOverlays.indices.contains(idx) { draft.greetingsOverlays[idx] = $0 } }
                ),
                photoMirrorEnabled: $draft.photoMirrorEnabled,
                isSubjectCutoutActive: draft.subjectCutoutImage != nil,
                isGeneratingSubjectCutout: isGeneratingSubjectCutout,
                onToggleSubjectCutout: { toggleSubjectCutout() },
                onDelete: { draft.greetingsOverlays.remove(at: idx); selectedGreetingsIndex = nil },
                onDone: { selectedGreetingsIndex = nil }
            )
        }
    }

    @discardableResult
    private func addTextOverlay(canvasWidth: CGFloat, text: String, style: TextBgStyle, colors: CaptionColorPreset) -> UUID {
        let width = canvasWidth > 0
            ? canvasWidth
            : imageAreaSize(in: postcardFrameSize(availableSize: UIScreen.main.bounds.size)).width
        var overlay = TextOverlay(at: CGPoint(x: 0.5, y: 0.2), canvasWidth: width)
        overlay.text = text
        overlay.bgStyle = style
        overlay.textColor = colors.font
        overlay.bgColor = colors.background
        overlay.borderEnabled = colors.border
        overlay.borderUsesFontColor = colors.borderUsesFontColor

        // Fit the width to the entered phrase; stays auto-fit (re-fitting as the
        // text is edited) until the user drags the Width slider. Blank text
        // keeps the default width until something is typed.
        overlay.widthAutoFit = true
        overlay.autoFitWidth()

        // Placed on the card without opening the full edit panel — tapping the
        // caption on the card does that.
        draft.textOverlays.append(overlay)
        return overlay.id
    }

    // MARK: Caption quick sheet (new + edit)

    @ViewBuilder
    private func captionSheetContent() -> some View {
        if let id = captionEditID {
            // (If the caption was just deleted, render nothing while the sheet
            // finishes dismissing rather than flashing the "new" layout.)
            if let o = draft.textOverlays.first(where: { $0.id == id }) {
                CaptionQuickAddSheet(
                    edit: CaptionEditActions(
                        setText: { t in
                            guard let i = draft.textOverlays.firstIndex(where: { $0.id == id }) else { return }
                            draft.textOverlays[i].text = t
                            if draft.textOverlays[i].widthAutoFit { draft.textOverlays[i].autoFitWidth() }
                        },
                        setStyle: { st in
                            guard let i = draft.textOverlays.firstIndex(where: { $0.id == id }) else { return }
                            draft.textOverlays[i].bgStyle = st
                        },
                        setColors: { c in
                            guard let i = draft.textOverlays.firstIndex(where: { $0.id == id }) else { return }
                            draft.textOverlays[i].textColor = c.font
                            draft.textOverlays[i].bgColor = c.background
                            draft.textOverlays[i].borderEnabled = c.border
                            draft.textOverlays[i].borderUsesFontColor = c.borderUsesFontColor
                        },
                        delete: { draft.textOverlays.removeAll { $0.id == id } }
                    ),
                    initialText: o.text,
                    initialStyle: o.bgStyle,
                    initialColors: CaptionColorPreset.matching(font: o.textColor, background: o.bgColor),
                    onAdd: { _, _, _ in },
                    onMore: { _, _, _ in pendingFullCaptionID = id },
                    onClose: { showingCaptionSheet = false }
                )
            }
        } else {
            CaptionQuickAddSheet(
                onAdd: { text, style, colors in
                    addTextOverlay(canvasWidth: pendingCaptionCanvasWidth, text: text, style: style, colors: colors)
                },
                onMore: { text, style, colors in
                    pendingFullCaptionID = addTextOverlay(canvasWidth: pendingCaptionCanvasWidth, text: text, style: style, colors: colors)
                },
                onClose: { showingCaptionSheet = false }
            )
        }
    }

    // Runs when the caption sheet has closed: if "More options" was pressed,
    // select that caption so the full panel comes up.
    private func finishCaptionSheet() {
        captionEditID = nil
        guard let id = pendingFullCaptionID else { return }
        pendingFullCaptionID = nil
        guard let i = draft.textOverlays.firstIndex(where: { $0.id == id }) else { return }
        selectedIndex = i
        selectedQRIndex = nil
        selectedBurstIndex = nil
        selectedGreetingsIndex = nil
    }

    private func addBurstOverlay(canvasHeight: CGFloat) {
        draft.burstOverlays.append(BurstCaptionOverlay(canvasHeight: canvasHeight))
        selectedBurstIndex = draft.burstOverlays.count - 1
        selectedIndex = nil
        selectedQRIndex = nil
        selectedGreetingsIndex = nil
    }

    // Only one Greetings badge is allowed per card — if one already exists,
    // tapping the control edits it instead of creating a second.
    // Existing badge: just selects it (opens the full panel). (A card has at
    // most one badge; a NEW one is created through the quick-add sheet — see
    // startGreetingsPreview.)
    private func addGreetingsOverlay(imgSize: CGSize) {
        if draft.greetingsOverlays.isEmpty {
            var overlay = GreetingsOverlay()
            overlay.word = draft.senderNickname
            draft.greetingsOverlays.append(overlay)
            // A new banner can shrink the safe zone under an
            // already-positioned photo — re-clamp immediately.
            clampPhotoToSafeZone(imgSize: imgSize)
            rerenderComposedImage()
        }
        selectedGreetingsIndex = 0
        selectedIndex = nil
        selectedQRIndex = nil
        selectedBurstIndex = nil
    }

    // MARK: Greetings quick-add (live on the card)

    private static let greetingsDefaultIntro = "greetings from"
    private static let greetingsDefaultMarquee = "CardDrop"

    // Greetings tapped with no badge yet: put the DEFAULT badge on the card
    // right away (yellow script, blue band, halo on, Tilt, "greetings from" /
    // "CardDrop"), start "Put subject in front", then open the sheet — which
    // edits that badge live. The photo's scale/offset are remembered so a
    // cancel can put them back (adding the badge may re-clamp the photo).
    private func startGreetingsPreview(imgSize: CGSize) {
        pendingGreetingsImgSize = imgSize
        greetingsAddConfirmed = false
        greetingsRestoreScale = draft.imageScale
        greetingsRestoreOffset = draft.imageOffset

        var overlay = GreetingsOverlay()
        overlay.word = Self.greetingsDefaultMarquee
        overlay.scriptText = Self.greetingsDefaultIntro
        overlay.fixedPosition = .left
        overlay.scriptColorChoice = .yellow
        overlay.badgeColorChoice = .blue
        overlay.haloEnabled = true
        greetingsPreviewID = overlay.id
        draft.greetingsOverlays.append(overlay)
        clampPhotoToSafeZone(imgSize: imgSize)
        rerenderComposedImage()

        greetingsStartedCutout = false
        if draft.subjectCutoutImage == nil && draft.image != nil {
            greetingsStartedCutout = true
            toggleSubjectCutout()
        }
        showingGreetingsSheet = true
    }

    // The sheet for the badge: NEW (preview already on the card, kept on Save)
    // or EDIT of the existing badge (live; trash deletes).
    @ViewBuilder
    private func greetingsSheetContent() -> some View {
        if greetingsEditing {
            if let o = draft.greetingsOverlays.first(where: { $0.id == greetingsPreviewID }) {
                GreetingsQuickAddSheet(
                    initialIntro: o.scriptText,
                    initialMarquee: o.word,
                    initialPosition: o.fixedPosition,
                    initialColor: o.badgeColorChoice,
                    onChange: { intro, marquee, position, color in
                        updateGreetingsPreview(intro: intro, marquee: marquee, position: position, color: color)
                    },
                    onAdd: { },
                    onDelete: { greetingsDeleteRequested = true },
                    onMore: { greetingsOpenFullPanel = true },
                    onClose: { showingGreetingsSheet = false }
                )
            }
        } else {
            GreetingsQuickAddSheet(
                initialIntro: Self.greetingsDefaultIntro,
                initialMarquee: Self.greetingsDefaultMarquee,
                initialPosition: .left,
                initialColor: .blue,
                onChange: { intro, marquee, position, color in
                    updateGreetingsPreview(intro: intro, marquee: marquee, position: position, color: color)
                },
                onAdd: { greetingsAddConfirmed = true },
                onMore: { greetingsAddConfirmed = true; greetingsOpenFullPanel = true },
                onClose: { showingGreetingsSheet = false }
            )
        }
    }

    // Existing badge tapped (on the card or via the Greetings button): open the
    // sheet editing it live. Changes are kept however the sheet closes.
    private func startGreetingsEdit(imgSize: CGSize) {
        guard let overlay = draft.greetingsOverlays.first else { return }
        pendingGreetingsImgSize = imgSize
        greetingsEditing = true
        greetingsAddConfirmed = true
        greetingsOpenFullPanel = false
        greetingsDeleteRequested = false
        greetingsPreviewID = overlay.id
        showingGreetingsSheet = true
    }

    // Each edit in the sheet updates the badge on the card.
    private func updateGreetingsPreview(intro: String, marquee: String, position: GreetingsFixedPosition, color: GreetingsBadgeColor) {
        guard let id = greetingsPreviewID,
              let i = draft.greetingsOverlays.firstIndex(where: { $0.id == id }) else { return }
        draft.greetingsOverlays[i].scriptText = intro
        draft.greetingsOverlays[i].word = marquee
        draft.greetingsOverlays[i].fixedPosition = position
        draft.greetingsOverlays[i].badgeColorChoice = color
    }

    // Runs whenever the sheet closes. Save → keep the badge (re-clamp the photo
    // for its final text/position, panel stays closed). trash →
    // remove the badge and put the photo and cutout back as they were.
    private func finishGreetingsPreview() {
        defer {
            greetingsPreviewID = nil
            greetingsEditing = false
            if greetingsOpenFullPanel, !draft.greetingsOverlays.isEmpty {
                selectedGreetingsIndex = 0
                selectedIndex = nil
                selectedQRIndex = nil
                selectedBurstIndex = nil
            }
            greetingsOpenFullPanel = false
            greetingsDeleteRequested = false
        }
        guard let id = greetingsPreviewID else { return }
        if greetingsDeleteRequested {
            // Same as the full panel's Delete.
            draft.greetingsOverlays.removeAll { $0.id == id }
            return
        }
        if greetingsAddConfirmed {
            clampPhotoToSafeZone(imgSize: pendingGreetingsImgSize)
            rerenderComposedImage()
            if draft.subjectCutoutImage != nil { rerenderSubjectCutoutComposedImage() }
        } else {
            draft.greetingsOverlays.removeAll { $0.id == id }
            draft.imageScale = greetingsRestoreScale
            draft.imageOffset = greetingsRestoreOffset
            if greetingsStartedCutout {
                draft.subjectCutoutImage = nil
                draft.subjectCutoutComposedImage = nil
            }
            rerenderComposedImage()
        }
    }

    private func addQROverlay() {
        draft.qrOverlays.append(QROverlay())
        selectedQRIndex = draft.qrOverlays.count - 1
        selectedIndex = nil
        selectedBurstIndex = nil
        selectedGreetingsIndex = nil
    }

    // The editor's text bubbles lay themselves out at this same size (see
    // TextOverlayItemView) — the exact border-inset image area CardRenderer
    // will bake at, for the current orientation/border — so the CoreText
    // layout pass measuring/wrapping text is identical in the editor and in
    // the final print, guaranteeing the wrap point can never drift between
    // the two. Mirrors CardRenderer.renderAndSave's frontSize exactly.
    private var printCanvasSize: CGSize {
        let printFrameSize = draft.orientation == .landscape
            ? CGSize(width: CardRenderer.frontLongSideBleed, height: CardRenderer.frontShortSideBleed)
            : CGSize(width: CardRenderer.frontShortSideBleed, height: CardRenderer.frontLongSideBleed)
        return imageAreaSize(in: printFrameSize)
    }

    private func imageAreaSize(in frameSize: CGSize) -> CGSize {
        let fractions: (x: Double, y: Double)
        switch draft.border {
        case .fullBleed:   return frameSize
        case .whiteBorder:
            switch draft.orientation {
            case .landscape: fractions = (0.25/6.0, 0.25/4.0)
            case .portrait:  fractions = (0.25/4.0, 0.25/6.0)
            }
        case .customText, .decorative:
            switch draft.orientation {
            case .landscape: fractions = (3.0/8.0/6.0, 3.0/8.0/4.0)
            case .portrait:  fractions = (3.0/8.0/4.0, 3.0/8.0/6.0)
            }
        }
        let insetX = frameSize.width  * fractions.x
        let insetY = frameSize.height * fractions.y
        return CGSize(width: frameSize.width - 2 * insetX, height: frameSize.height - 2 * insetY)
    }

    private func postcardFrameSize(availableSize: CGSize) -> CGSize {
        guard availableSize.width > 0, availableSize.height > 0 else { return .zero }
        let maxWidth  = availableSize.width  - 32
        // Now that Choose Photo (orientation/border toggles, filters,
        // From/To) is its own earlier step, this GeometryReader only needs
        // to reserve space for its own remaining chrome: the "Pinch to
        // zoom" hint row and the canvas's own top padding — plus headroom
        // for the step header above this view (back/forward arrows, title,
        // Close), which isn't part of this GeometryReader's measured size
        // at all. 120 mirrors the reserve ChoosePhotoStepView uses for the
        // equivalent (now-shared) situation. Not sized differently whether
        // or not an editor is open: the edit panel is a floating overlay
        // (see `body`), not something this frame reserves space for, so the
        // canvas never resizes when editing starts/stops.
        let maxHeight = availableSize.height - 120
        let ratio = draft.orientation.aspectRatio
        if ratio >= 1 {
            let w = min(maxWidth, maxHeight * ratio)
            return CGSize(width: w, height: w / ratio)
        } else {
            // Portrait is height-bound here (maxWidth / ratio is comfortably
            // larger than maxHeight on typical phone screens), so unlike
            // landscape it never benefits from the width side of this
            // min() — it's stuck at the same maxHeight landscape uses even
            // though it doesn't share landscape's width constraint. Boost it
            // 1/3 for portrait specifically so it isn't left needlessly
            // smaller than it has room to be.
            let portraitMaxHeight = maxHeight * 4.0 / 3.0
            let h = min(portraitMaxHeight, maxWidth / ratio)
            return CGSize(width: h * ratio, height: h)
        }
    }
}

// MARK: - Individual Item View

struct TextOverlayItemView: View {
    @Binding var overlay: TextOverlay
    let canvasSize: CGSize
    // The border-inset print-resolution canvas size for the current
    // orientation/border (see TextOverlayStepView.printCanvasSize).
    let printCanvasSize: CGSize
    let onSelect: () -> Void

    @GestureState private var liveDragPosition: CGPoint? = nil

    // Lays the bubble out at the SAME absolute point size the print bake
    // will use (TextOverlayBubbleView), then scales the whole result back
    // down to fit the live editor canvas — this is what guarantees the two
    // can never wrap text differently (see TextOverlayBubbleView's doc
    // comment for why that matters).
    private var fontScale: CGFloat {
        overlay.canvasWidth > 0 ? printCanvasSize.width / overlay.canvasWidth : 1
    }
    private var displayScale: CGFloat {
        printCanvasSize.width > 0 ? canvasSize.width / printCanvasSize.width : 1
    }

    // The front print canvas is always baked at a fixed 300 DPI (see
    // CardRenderer.frontLongSideBleed / frontShortSideBleed), so 3/8" is a
    // constant number of print-canvas points regardless of orientation or
    // border style; converting through displayScale lands it in editor
    // points without needing to know the physical card size here.
    private var safeInset: CGFloat {
        (0.375 * 300) * displayScale
    }

    // The bubble's true footprint (box/speech/thought background + padding,
    // not just the text glyphs), at the same print-canvas scale
    // TextOverlayBubbleView itself lays out at (fontScale/boxWidth). This is
    // computed analytically — mirroring TextOverlayBubbleView's own padding
    // math exactly — rather than measured live via GeometryReader, because a
    // GeometryReader/PreferenceKey round-trip lags a render cycle behind the
    // drag and was leaving the clamp using a stale/zero size, letting the
    // visible box cross the boundary while only the text (near the center
    // point) stayed inside.
    private var containerSize: CGSize {
        let boxWidth = overlay.normalizedWidth * printCanvasSize.width
        let scaledFontSize = min(overlay.fontSize, 48) * fontScale
        let uiFont = UIFont(name: overlay.resolvedFontName, size: scaledFontSize)
            ?? UIFont.systemFont(ofSize: scaledFontSize)

        let basePadH: CGFloat
        let basePadV: CGFloat
        switch overlay.bgStyle {
        case .thought:      basePadH = 2 * fontScale;  basePadV = 2 * fontScale
        case .box, .speech, .rectangle: basePadH = 12 * fontScale; basePadV = 12 * fontScale
        case .none:         basePadH = 5 * fontScale;  basePadV = 4 * fontScale
        }
        let cloudExtra: CGFloat = (overlay.bgStyle == .thought ? 2 : 0) * fontScale
        let tailHeight = overlay.tailReserve(boxWidth: boxWidth, scale: fontScale)

        let displayText = overlay.text.isEmpty ? " " : overlay.text
        let bounding = (displayText as NSString).boundingRect(
            with: CGSize(width: boxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: uiFont],
            context: nil
        )

        // Mirrors TextOverlayBubbleView's proportional oval/cloud padding.
        let extra = overlay.bubbleExtraPadding(boxWidth: boxWidth, scale: fontScale)
        return CGSize(
            width:  boxWidth + 2 * (basePadH + cloudExtra + extra.width),
            height: ceil(bounding.height) + 2 * (basePadV + cloudExtra + extra.height) + tailHeight
        )
    }

    // Hard-stops `proposed` (an absolute center point in canvasSize's
    // coordinate space) so the bubble's true, rotated edge never crosses the
    // 3/8" safe boundary. Called live on every drag frame, not just on
    // release, so the object physically can't be dragged past the line.
    private func clamped(_ proposed: CGPoint) -> CGPoint {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return proposed }

        // containerSize is at print-canvas scale (same space TextOverlayBubbleView
        // itself lays out at), so it must be scaled by displayScale here to
        // get the actual on-screen size.
        let rad = CGFloat(overlay.rotation) * .pi / 180
        let size = containerSize
        let halfW = (size.width  * displayScale) / 2
        let halfH = (size.height * displayScale) / 2
        let boundHalfW = abs(halfW * cos(rad)) + abs(halfH * sin(rad))
        let boundHalfH = abs(halfW * sin(rad)) + abs(halfH * cos(rad))

        let minX = safeInset + boundHalfW
        let maxX = canvasSize.width - safeInset - boundHalfW
        let minY = safeInset + boundHalfH
        let maxY = canvasSize.height - safeInset - boundHalfH

        // If the bubble is too big to fit within the boundary on an axis,
        // just center it on that axis instead of leaving it stuck against
        // one side.
        return CGPoint(
            x: minX <= maxX ? max(minX, min(maxX, proposed.x)) : canvasSize.width / 2,
            y: minY <= maxY ? max(minY, min(maxY, proposed.y)) : canvasSize.height / 2
        )
    }

    var body: some View {
        let displayPosition = liveDragPosition ?? CGPoint(
            x: overlay.normalizedPosition.x * canvasSize.width,
            y: overlay.normalizedPosition.y * canvasSize.height
        )

        TextOverlayBubbleView(
            overlay: overlay,
            scale: fontScale,
            boxWidth: overlay.normalizedWidth * printCanvasSize.width
        )
        .scaleEffect(displayScale)
        .rotationEffect(Angle(degrees: overlay.rotation))
        .position(x: displayPosition.x, y: displayPosition.y)
        .gesture(
            DragGesture()
                .updating($liveDragPosition) { value, state, _ in
                    let proposed = CGPoint(
                        x: overlay.normalizedPosition.x * canvasSize.width  + value.translation.width,
                        y: overlay.normalizedPosition.y * canvasSize.height + value.translation.height
                    )
                    state = clamped(proposed)
                }
                .onEnded { value in
                    guard canvasSize.width > 0, canvasSize.height > 0 else { return }
                    let proposed = CGPoint(
                        x: overlay.normalizedPosition.x * canvasSize.width  + value.translation.width,
                        y: overlay.normalizedPosition.y * canvasSize.height + value.translation.height
                    )
                    let result = clamped(proposed)
                    overlay.normalizedPosition = CGPoint(
                        x: result.x / canvasSize.width,
                        y: result.y / canvasSize.height
                    )
                }
        )
        .onTapGesture { onSelect() }
    }
}

// MARK: - Edit Panel

struct TextOverlayEditPanel: View {
    @Binding var overlay: TextOverlay
    let canvasSize: CGSize
    var onDelete: () -> Void
    var onDone: () -> Void

    @FocusState private var textFocused: Bool
    private let charLimit = 40

    // Same bounds the old on-canvas resize handle enforced (min ~80pt wide,
    // max 92% of the canvas).
    private var widthRange: ClosedRange<Double> {
        guard canvasSize.width > 0 else { return 0.1...0.92 }
        let minFraction = min(0.92, Double(80 / canvasSize.width))
        return minFraction...0.92
    }

    var body: some View {

        VStack(alignment: .leading, spacing: 10) {

            // Row 1: Full-width text box with char cap
            ZStack(alignment: .topLeading) {
                if overlay.text.isEmpty {
                    Text("Your text")
                        .foregroundColor(Color(.placeholderText))
                        .padding(.horizontal, 5)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $overlay.text)
                    .frame(minHeight: 34, maxHeight: 40)
                    .scrollContentBackground(.hidden)
                    .focused($textFocused)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { textFocused = false }
                                .buttonStyle(.borderedProminent)
                                .tint(Color.brandBlue)
                        }
                    }
                    .onKeyPress(.tab) { .handled }
                    .onChange(of: overlay.text) { _, new in
                        if new.count > charLimit { overlay.text = String(new.prefix(charLimit)) }
                        if overlay.widthAutoFit { overlay.autoFitWidth() }
                    }
            }
            .padding(4)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
            .overlay(alignment: .bottomTrailing) {
                Text("\(overlay.text.count)/\(charLimit)")
                    .font(.caption2)
                    .foregroundColor(overlay.text.count >= charLimit ? .red : .secondary)
                    .padding(4)
            }

            // Row 2: Font picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(TextOverlay.availableFonts, id: \.name) { f in
                        Button(action: { overlay.fontName = f.name }) {
                            Text(f.displayName)
                                .font(.custom(TextOverlay.resolvedFontName(base: f.name, bold: overlay.isBold, italic: overlay.isItalic), size: 13))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(overlay.fontName == f.name ? Color.accentColor : Color(.secondarySystemBackground))
                                .foregroundColor(overlay.fontName == f.name ? .white : .primary)
                                .cornerRadius(999)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }

            // Row 3: text color, Size slider, Bold, Italic
            HStack(spacing: 10) {
                ColorPicker("", selection: $overlay.textColor).labelsHidden()
                Text("Size").font(.caption).foregroundColor(.secondary)
                Slider(
                    value: Binding(
                        get: { Double(overlay.fontSize) },
                        set: { overlay.fontSize = CGFloat($0) }
                    ),
                    in: 16...48, step: 1
                )
                Text("\(Int(overlay.fontSize))")
                    .font(.caption).foregroundColor(.secondary).frame(width: 26)
                Button(action: { overlay.isBold.toggle() }) {
                    Text("B")
                        .font(.custom("Georgia-Bold", size: 16))
                        .frame(width: 34, height: 30)
                        .background(overlay.isBold ? Color.accentColor : Color(.secondarySystemBackground))
                        .foregroundColor(overlay.isBold ? .white : .primary)
                        .cornerRadius(999)
                }
                Button(action: { overlay.isItalic.toggle() }) {
                    Text("I")
                        .font(.custom("Georgia-Italic", size: 16))
                        .frame(width: 34, height: 30)
                        .background(overlay.isItalic ? Color.accentColor : Color(.secondarySystemBackground))
                        .foregroundColor(overlay.isItalic ? .white : .primary)
                        .cornerRadius(999)
                }
            }

            // Row: Border (with a container) or Halo (Float only) — never both.
            // The halo is a plain on/off; its color is automatic (see
            // TextOverlay.haloColor).
            HStack(spacing: 8) {
                if overlay.bgStyle != .none {
                    // Segmented control (same one as the Write step's phrase
                    // filter): Black / Off / Match (border matches the font
                    // color) — maps onto borderEnabled + borderUsesFontColor.
                    Text("Border").font(.caption).foregroundColor(.secondary)
                    CompactSegmentedControl(
                        options: ["Black", "Off", "Match"],
                        selection: Binding(
                            get: {
                                !overlay.borderEnabled ? "Off"
                                    : (overlay.borderUsesFontColor ? "Match" : "Black")
                            },
                            set: { choice in
                                switch choice {
                                case "Off":
                                    overlay.borderEnabled = false
                                case "Match":
                                    overlay.borderEnabled = true
                                    overlay.borderUsesFontColor = true
                                default:
                                    overlay.borderEnabled = true
                                    overlay.borderUsesFontColor = false
                                }
                            }
                        )
                    )
                } else {
                    Button("Halo") { overlay.haloEnabled.toggle() }
                        .font(.system(size: 13, weight: .semibold))
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 16)
                        .frame(height: 30)
                        .background(overlay.haloEnabled ? Color.accentColor : Color(.secondarySystemBackground))
                        .foregroundColor(overlay.haloEnabled ? .white : .primary)
                        .cornerRadius(999)
                }
            }

            // Row 4: BG controls, color, mirror — all in one scrollable strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Background color first, before the container icons. Kept in
                    // the layout (just invisible) for Float so the icons don't
                    // shift sideways when switching to/from it.
                    ColorPicker("", selection: $overlay.bgColor).labelsHidden()
                        .opacity(overlay.bgStyle == .none ? 0 : 1)
                        .allowsHitTesting(overlay.bgStyle != .none)

                    ForEach(TextBgStyle.displayOrder, id: \.self) { style in
                        Button(action: { overlay.bgStyle = style }) {
                            Image(systemName: style.systemImage)
                                .font(.system(size: 15))
                                .frame(width: 34, height: 30)
                                .background(overlay.bgStyle == style ? Color.accentColor : Color(.secondarySystemBackground))
                                .foregroundColor(overlay.bgStyle == style ? .white : .primary)
                                .cornerRadius(999)
                        }
                    }

                    if overlay.bgStyle == .speech || overlay.bgStyle == .thought {
                        Divider().frame(height: 24)

                        // Left/right: speech only — thought bubbles have no
                        // left/right tail control, always dead center.
                        // Cycles left → right → left in an endless loop on
                        // each tap — never highlighted, since there's no
                        // single "active" state to indicate.
                        if overlay.bgStyle == .speech {
                            Button(action: { overlay.tailHPosition = overlay.tailHPosition.next }) {
                                Image(systemName: "arrow.left.and.right")
                                    .font(.system(size: 14))
                                    .frame(width: 34, height: 30)
                                    .background(Color(.secondarySystemBackground))
                                    .foregroundColor(.primary)
                                    .cornerRadius(999)
                            }
                        }

                        // Up/down: both styles — top vs bottom tail.
                        Button(action: { overlay.tailFlippedV.toggle() }) {
                            Image(systemName: "arrow.up.and.down")
                                .font(.system(size: 14))
                                .frame(width: 34, height: 30)
                                .background(Color(.secondarySystemBackground))
                                .foregroundColor(.primary)
                                .cornerRadius(999)
                        }
                    }

                    // (Background color now leads this strip, and the Border
                    // toggle lives on the Halo row.)
                }
                .padding(.horizontal, 2)
            }

            // Row: Width + Rotation sliders, one row — replaces the old
            // on-canvas resize/rotate drag handles.
            HStack(spacing: 8) {
                Text("Width").font(.caption).foregroundColor(.secondary)
                Slider(
                    value: Binding(
                        get: { Double(overlay.normalizedWidth) },
                        set: {
                            overlay.normalizedWidth = CGFloat($0)
                            overlay.widthAutoFit = false   // user chose a width — stop auto-fitting
                        }
                    ),
                    in: widthRange
                )
                Text("Rotate").font(.caption).foregroundColor(.secondary)
                Slider(
                    value: Binding(
                        get: { overlay.rotation },
                        set: { overlay.rotation = $0 }
                    ),
                    in: -180...180
                )
            }

            // Row 5: Done, Delete — last.
            HStack(spacing: 8) {
                Button("Save", action: onDone)
                    .savePill()

                Button(action: onDelete) {
                    Image(systemName: "trash").foregroundColor(.red)
                }
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        // Anything that changes the text's rendered width re-fits it, unless
        // the user has set the width by hand (widthAutoFit cleared).
        .onChange(of: overlay.fontName) { _, _ in if overlay.widthAutoFit { overlay.autoFitWidth() } }
        .onChange(of: overlay.fontSize) { _, _ in if overlay.widthAutoFit { overlay.autoFitWidth() } }
        .onChange(of: overlay.isBold)   { _, _ in if overlay.widthAutoFit { overlay.autoFitWidth() } }
        .onChange(of: overlay.isItalic) { _, _ in if overlay.widthAutoFit { overlay.autoFitWidth() } }
    }
}

// MARK: - QR Overlay Item View

struct QROverlayItemView: View {
    @Binding var overlay: QROverlay
    let canvasSize: CGSize
    let printCanvasSize: CGSize
    let isSelected: Bool
    let onSelect: () -> Void

    @GestureState private var dragOffset: CGSize = .zero
    @State private var qrImage: UIImage? = nil

    private var size: CGFloat {
        QROverlay.fixedNormalizedSize * min(canvasSize.width, canvasSize.height)
    }

    var body: some View {
        Group {
            if let img = qrImage {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
            } else {
                Color.white.opacity(0.85)
                    .overlay(Image(systemName: "qrcode")
                        .font(.largeTitle)
                        .foregroundColor(.black.opacity(0.3)))
            }
        }
        .frame(width: size, height: size)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.white : Color.clear, lineWidth: 1.5)
                .padding(-2)
        )
        .position(
            x: overlay.normalizedPosition.x * canvasSize.width  + dragOffset.width,
            y: overlay.normalizedPosition.y * canvasSize.height + dragOffset.height
        )
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in state = value.translation }
                .onEnded { value in
                    guard canvasSize.width > 0, canvasSize.height > 0 else { return }
                    let nx = overlay.normalizedPosition.x + value.translation.width  / canvasSize.width
                    let ny = overlay.normalizedPosition.y + value.translation.height / canvasSize.height
                    var updated = overlay
                    updated.normalizedPosition = CGPoint(x: max(0, min(1, nx)), y: max(0, min(1, ny)))
                    updated.snapToNearestCorner(canvasSize: canvasSize, printCanvasSize: printCanvasSize)
                    overlay = updated
                }
        )
        .onTapGesture { onSelect() }
        .onChange(of: overlay.content) { _, _ in generateQR() }
        .onAppear {
            guard canvasSize.width > 0, canvasSize.height > 0 else { generateQR(); return }
            var updated = overlay
            updated.snapToNearestCorner(canvasSize: canvasSize, printCanvasSize: printCanvasSize)
            overlay = updated
            generateQR()
        }
    }

    private func generateQR() {
        guard !overlay.content.isEmpty,
              let data = overlay.content.data(using: .utf8) else { qrImage = nil; return }
        Task.detached(priority: .utility) {
            let filter = CIFilter.qrCodeGenerator()
            filter.setValue(data, forKey: "inputMessage")
            filter.setValue("M",  forKey: "inputCorrectionLevel")
            guard let output = filter.outputImage else { return }
            let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
            let ctx = CIContext()
            guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return }
            let img = UIImage(cgImage: cg)
            await MainActor.run { qrImage = img }
        }
    }
}

// MARK: - QR Overlay Edit Panel

struct QROverlayEditPanel: View {
    @Binding var overlay: QROverlay
    let canvasSize: CGSize
    let printCanvasSize: CGSize
    var onDelete: () -> Void
    var onDone: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row 1: Done, Delete, corner-move buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button("Save", action: onDone)
                        .savePill()

                    Button(action: onDelete) {
                        Image(systemName: "trash").foregroundColor(.red)
                    }
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())

                    Divider().frame(height: 24)

                    Text("Move").font(.caption).foregroundColor(.secondary)

                    Button(action: {
                        var updated = overlay
                        updated.flipHorizontal(canvasSize: canvasSize, printCanvasSize: printCanvasSize)
                        overlay = updated
                    }) {
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 14))
                            .frame(width: 34, height: 30)
                            .background(Color(.secondarySystemBackground))
                            .foregroundColor(.primary)
                            .cornerRadius(999)
                    }

                    Button(action: {
                        var updated = overlay
                        updated.flipVertical(canvasSize: canvasSize, printCanvasSize: printCanvasSize)
                        overlay = updated
                    }) {
                        Image(systemName: "arrow.up.and.down")
                            .font(.system(size: 14))
                            .frame(width: 34, height: 30)
                            .background(Color(.secondarySystemBackground))
                            .foregroundColor(.primary)
                            .cornerRadius(999)
                    }
                }
                .padding(.horizontal, 2)
            }

            // Row 2: Text input
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        TextField("Secret message or URL…", text: $overlay.userInputText)
                            .textFieldStyle(.roundedBorder)
                            .focused($focused)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .onChange(of: overlay.userInputText) { _, new in
                                if new.count > 75 {
                                    overlay.userInputText = String(new.prefix(75))
                                }
                                overlay.content = new.isEmpty ? QROverlay.defaultContent : new
                            }
                        Text("\(overlay.userInputText.count)/75")
                            .font(.caption)
                            .foregroundColor(overlay.userInputText.count >= 75 ? .red : .secondary)
                            .monospacedDigit()
                    }
                    Text("Recipients scan with their iPhone camera to reveal the hidden message.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .onAppear { focused = true }
    }
}

#Preview {
    TextOverlayStepView(draft: PostcardDraft(), onNext: {})
}
