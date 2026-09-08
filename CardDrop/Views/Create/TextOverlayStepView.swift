import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - Step View

// Publishes the canvas's current imgSize up to the top-level body, which
// needs it in the .safeAreaInset closure (outside the GeometryReader that
// computes it) to seed a newly-added text overlay's default width.
private struct ImgSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

struct TextOverlayStepView: View {
    @ObservedObject var draft: PostcardDraft
    var onNext: () -> Void

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
                        .opacity(isEditing ? 0 : 1)
                    addOverlayButtonsRow(imgSize: lastImgSize)
                        .opacity(isEditing ? 0 : 1)
                        .allowsHitTesting(!isEditing)
                    Button(action: onNext) {
                        Text("Next: Write Card")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.brandBlue)
                            .foregroundColor(.white)
                            .cornerRadius(999)
                    }
                    .allowsHitTesting(!isEditing)
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
            if isEditing {
                editPanel(imgSize: lastImgSize)
                    .background(.regularMaterial)
                    .cornerRadius(12)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 2 + keyboardHeight)
                    .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: -3)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isEditing)
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
        // Without this, the keyboard opening (e.g. typing in the Add Text
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

    @ViewBuilder
    private func mainContent(isEditing: Bool, frameSize: CGSize, imgSize: CGSize) -> some View {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                // Pinch hint stays anchored directly above the canvas (with
                // its existing padding) — this whole group is what gets
                // vertically centered in the safe zone via the two Spacers
                // around it, rather than the group sitting top-anchored with
                // leftover space only pushed to the bottom.
                VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Text("Pinch to zoom · Drag to reposition")
                        .font(.system(size: 15, weight: .regular))
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
                .padding(.top, 8)

                // Canvas
                ZStack {
                    (draft.border == .whiteBorder || draft.border == .decorative) ? Color.white : Color.black

                    ZStack {
                        // Directly behind the photo itself (independent of
                        // the outer white-border backdrop above) — if a
                        // drag/zoom leaves part of imgSize uncovered, that
                        // gap must read as this color, not whatever the
                        // border color happens to be, matching
                        // PostcardDraft.rendered(at:)'s baked output exactly:
                        // opaque white, or the Greetings badge's own
                        // background color when one is present.
                        (draft.greetingsOverlays.first?.badgeColorChoice.color ?? .white)
                            .frame(width: imgSize.width, height: imgSize.height)

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
                                            // No lower clamp at 1.0 — zooming
                                            // out smaller than "fill" is
                                            // allowed; the resulting gap
                                            // around the photo is handled by
                                            // a solid backdrop fill, both in
                                            // this live preview and in the
                                            // real print bake (PostcardDraft.
                                            // rendered(at:)). Only floors at
                                            // a small positive value so the
                                            // photo can never invert/collapse
                                            // to zero.
                                            draft.imageScale = max(0.1, draft.imageScale * value)
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
                                    selectedGreetingsIndex = draft.greetingsOverlays.firstIndex(where: { $0.id == overlay.id })
                                    selectedIndex = nil
                                    selectedQRIndex = nil
                                    selectedBurstIndex = nil
                                }
                            )
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
                                    selectedIndex = draft.textOverlays.firstIndex(where: { $0.id == overlay.id })
                                    selectedQRIndex = nil
                                    selectedBurstIndex = nil
                                    selectedGreetingsIndex = nil
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
                Button(action: { addTextOverlay(canvasWidth: imgSize.width) }) {
                    Label("Add Text", systemImage: "plus.circle")
                        .font(.system(size: 17, weight: .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundColor(.primary)
                        .themedSurface(appSettings.uiTheme, cornerRadius: 999)
                }
                Button(action: { addGreetingsOverlay() }) {
                    Label("Greetings", systemImage: "text.badge.star")
                        .font(.system(size: 17, weight: .regular))
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
                    .font(.system(size: 17, weight: .regular))
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
                .font(.subheadline)
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
                onDelete: { draft.greetingsOverlays.remove(at: idx); selectedGreetingsIndex = nil },
                onDone: { selectedGreetingsIndex = nil }
            )
        }
    }

    private func addTextOverlay(canvasWidth: CGFloat) {
        let width = canvasWidth > 0
            ? canvasWidth
            : imageAreaSize(in: postcardFrameSize(availableSize: UIScreen.main.bounds.size)).width
        draft.textOverlays.append(TextOverlay(at: CGPoint(x: 0.5, y: 0.2), canvasWidth: width))
        selectedIndex = draft.textOverlays.count - 1
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
    private func addGreetingsOverlay() {
        if draft.greetingsOverlays.isEmpty {
            var overlay = GreetingsOverlay()
            overlay.word = draft.senderNickname
            draft.greetingsOverlays.append(overlay)
        }
        selectedGreetingsIndex = 0
        selectedIndex = nil
        selectedQRIndex = nil
        selectedBurstIndex = nil
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

    @GestureState private var dragOffset: CGSize = .zero

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

    var body: some View {
        TextOverlayBubbleView(
            overlay: overlay,
            scale: fontScale,
            boxWidth: overlay.normalizedWidth * printCanvasSize.width
        )
        .scaleEffect(displayScale)
        .rotationEffect(Angle(degrees: overlay.rotation))
        .position(
            x: overlay.normalizedPosition.x * canvasSize.width  + dragOffset.width,
            y: overlay.normalizedPosition.y * canvasSize.height + dragOffset.height
        )
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    guard canvasSize.width > 0, canvasSize.height > 0 else { return }
                    let nx = overlay.normalizedPosition.x + value.translation.width  / canvasSize.width
                    let ny = overlay.normalizedPosition.y + value.translation.height / canvasSize.height
                    // Allow center to reach the edge (clipped at image boundary by parent)
                    overlay.normalizedPosition = CGPoint(
                        x: max(0, min(1, nx)),
                        y: max(0, min(1, ny))
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

            // Row 3: Size slider + text color
            HStack(spacing: 10) {
                Text("Size").font(.caption).foregroundColor(.secondary)
                Slider(
                    value: Binding(
                        get: { Double(overlay.fontSize) },
                        set: { overlay.fontSize = CGFloat($0) }
                    ),
                    in: 12...36, step: 1
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
                ColorPicker("", selection: $overlay.textColor).labelsHidden()
            }

            // Row 4: BG controls, color, mirror — all in one scrollable strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TextBgStyle.allCases, id: \.self) { style in
                        Button(action: { overlay.bgStyle = style }) {
                            Image(systemName: style.systemImage)
                                .font(.system(size: 15))
                                .frame(width: 34, height: 30)
                                .background(overlay.bgStyle == style ? Color.accentColor : Color(.secondarySystemBackground))
                                .foregroundColor(overlay.bgStyle == style ? .white : .primary)
                                .cornerRadius(999)
                        }
                    }

                    if overlay.bgStyle != .none {
                        ColorPicker("", selection: $overlay.bgColor).labelsHidden()
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
                        set: { overlay.normalizedWidth = CGFloat($0) }
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
                Button("Done", action: onDone)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(999)

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
    }
}

// MARK: - QR Overlay Item View

struct QROverlayItemView: View {
    @Binding var overlay: QROverlay
    let canvasSize: CGSize
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
                    updated.snapToNearestCorner(canvasSize: canvasSize)
                    overlay = updated
                }
        )
        .onTapGesture { onSelect() }
        .onChange(of: overlay.content) { _, _ in generateQR() }
        .onAppear {
            guard canvasSize.width > 0, canvasSize.height > 0 else { generateQR(); return }
            var updated = overlay
            updated.snapToNearestCorner(canvasSize: canvasSize)
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
    var onDelete: () -> Void
    var onDone: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row 1: Done, Delete, corner-move buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button("Done", action: onDone)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(999)

                    Button(action: onDelete) {
                        Image(systemName: "trash").foregroundColor(.red)
                    }
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())

                    Divider().frame(height: 24)

                    Text("Move").font(.caption).foregroundColor(.secondary)

                    Button(action: {
                        var updated = overlay
                        updated.flipHorizontal(canvasSize: canvasSize)
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
                        updated.flipVertical(canvasSize: canvasSize)
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
