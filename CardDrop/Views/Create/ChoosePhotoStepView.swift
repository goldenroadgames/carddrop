import SwiftUI
import PhotosUI

// Minimum pixel dimensions for acceptable print quality on a 6x9 postcard at ~200 DPI.
// 300 DPI ideal = 1800×2700; we warn below that but still allow proceeding.
private let minPrintPixels: CGFloat = 1800  // long side
private let minPrintPixelsShort: CGFloat = 1200  // short side

// MARK: - Step 0: Choose Photo
//
// Split back out from Style It (which had absorbed this, orientation/border,
// and From/To into one merged step). Top to bottom: From/To fields, then the
// "safe zone" (pinch/drag hint, photo canvas, "Choose a Different Photo"
// link) sized by its own GeometryReader, then the Landscape/Portrait and
// Borderless/Classic toggles below that, then "Next: Style It" pinned at the
// bottom as usual. Orientation/Border toggles here never need to rebaseline
// any text overlay (unlike the equivalent toggles used to when they lived in
// Style It) because no text overlay can exist yet this early in the flow.
struct ChoosePhotoStepView: View {
    @ObservedObject var draft: PostcardDraft
    @Binding var photoItem: PhotosPickerItem?
    var onNext: () -> Void

    @State private var isPickerPresented = false
    @State private var isModerating = false
    @State private var pendingLowResImage: UIImage? = nil
    @State private var showLowResAlert = false
    @State private var flaggedCategories: [String] = []
    @State private var showModerationAlert = false
    @State private var cachedFilteredImage: UIImage? = nil
    @State private var filterThumbnails: [PostcardFilter: UIImage] = [:]
    @State private var filterThumbnailsSourceImage: UIImage? = nil

    private let filmstripHeight: CGFloat = 92

    @State private var nicknameSyncTask: Task<Void, Never>?
    @State private var showToContactPicker = false
    @State private var contactPickedNickname: String?

    // Live pinch-to-zoom / drag-to-reposition deltas, applied on top of the
    // raw photo (draft.image) before committing into draft.imageScale/
    // imageOffset and re-baking draft.composedImage on gesture end.
    @GestureState private var gestureScale: CGFloat = 1.0
    @GestureState private var gestureDrag: CGSize = .zero

    private var hasStarted: Bool { draft.image != nil }

    private var namesFilled: Bool {
        !draft.senderNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.recipientNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var usedContactPickerForTo: Bool {
        contactPickedNickname != nil && contactPickedNickname == draft.recipientNickname
    }

    var body: some View {
        VStack(spacing: 0) {
            if draft.image != nil {
                fromToRow
                Divider()
            }

            GeometryReader { geo in
                let frameSize = postcardFrameSize(availableSize: geo.size)
                let imgSize   = imageAreaSize(in: frameSize)

                Group {
                    if draft.image == nil {
                        emptyPhotoState
                    } else {
                        safeZoneContent(frameSize: frameSize, imgSize: imgSize)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            if draft.image != nil {
                Divider()

                // Filters — first control below the safe zone, above the
                // Landscape/Portrait toggle.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(PostcardFilter.allCases, id: \.self) { filter in
                            ZStack {
                                Color.clear.frame(width: 64, height: 64)
                                if let thumb = filterThumbnails[filter] {
                                    FilterThumbnailView(
                                        thumbnail: thumb,
                                        filter: filter,
                                        isSelected: draft.filter == filter
                                    ) {
                                        draft.filter = filter
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .padding(.top, 4)
                .frame(height: filmstripHeight)
                .background(Color(.systemBackground))

                Divider()

                VStack(spacing: 4) {
                    SlidingTogglePill(
                        options: [(PostcardOrientation.landscape, "Landscape"), (.portrait, "Portrait")],
                        selection: draft.orientation
                    ) { option in
                        draft.orientation = option
                        draft.imageScale = 1.0
                        draft.imageOffset = .zero
                        rerenderComposedImage()
                    }

                    SlidingTogglePill(
                        options: [(PostcardBorder.fullBleed, "Borderless"), (.whiteBorder, "Classic")],
                        selection: draft.border
                    ) { option in
                        draft.border = option
                        rerenderComposedImage()
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if draft.image != nil {
                VStack(spacing: 0) {
                    Divider()
                    Button(action: onNext) {
                        Text("Next: Style It")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background((hasStarted && namesFilled) ? Color.brandBlue : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(999)
                    }
                    .disabled(!(hasStarted && namesFilled))
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .background(Color(uiColor: .systemBackground))
            }
        }
        .onAppear {
            // DraftManager.load(_:) restores imageScale/imageOffset from the
            // saved snapshot but always reconstructs composedImage as nil
            // (it isn't persisted to disk) — re-bake immediately so a
            // reopened draft's crop matches its saved position right away.
            rerenderComposedImage()
            updateCachedFilteredImage()
            updateFilterThumbnailsIfNeeded()
        }
        .task {
            if draft.senderNickname.isEmpty, let saved = await UserService.fetchSenderNickname(), !saved.isEmpty {
                draft.senderNickname = saved
            }
        }
        .onChange(of: draft.filter) { _, _ in updateCachedFilteredImage() }
        .onReceive(draft.$composedImage) { _ in updateFilterThumbnailsIfNeeded() }
        .onReceive(draft.$image) { newImage in
            // @Published's publisher fires from willSet — draft.image itself
            // hasn't been updated to the new value yet at this point, so use
            // the value the publisher actually delivers instead of
            // re-reading (stale) draft.image. This was the reason filter
            // thumbnails didn't appear until leaving and re-entering this
            // step after first choosing a photo: this call used to read
            // draft.image directly, which was still nil at that moment.
            updateFilterThumbnailsIfNeeded(newImage)
            updateCachedFilteredImage(newImage)
        }
        .photoPickingPipeline(
            draft: draft, photoItem: $photoItem, isPickerPresented: $isPickerPresented,
            isModerating: $isModerating, pendingLowResImage: $pendingLowResImage,
            showLowResAlert: $showLowResAlert, flaggedCategories: $flaggedCategories,
            showModerationAlert: $showModerationAlert
        )
    }

    // Pinch/drag hint, the photo canvas itself, and "Choose a Different
    // Photo" — the part of the screen that flexes with available height.
    @ViewBuilder
    private func safeZoneContent(frameSize: CGSize, imgSize: CGSize) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            // Pinch hint stays anchored directly above the canvas and
            // "Choose a Different Photo" directly below it (each keeping its
            // own existing padding) — this whole group is what gets
            // vertically centered in the safe zone via the two Spacers
            // around it, rather than the group sitting top-anchored with
            // leftover space only pushed to the bottom.
            VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Pinch to zoom · Drag to reposition")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.brandBlue)
                Button {
                    print("🔵 Undo tapped — before: scale=\(draft.imageScale) offset=\(draft.imageOffset)")
                    draft.imageScale = 1.0
                    draft.imageOffset = .zero
                    rerenderComposedImage()
                    print("🔵 Undo tapped — after: scale=\(draft.imageScale) offset=\(draft.imageOffset)")
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .foregroundColor(.brandBlue)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)

            // Canvas — photo positioning only, no text/QR/Greetings/Burst
            // overlays here (none can exist yet this early in the flow).
            ZStack {
                (draft.border == .whiteBorder || draft.border == .decorative) ? Color.white : Color.black

                ZStack {
                    Color.white
                        .frame(width: imgSize.width, height: imgSize.height)

                    if let img = cachedFilteredImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: imgSize.width, height: imgSize.height)
                            .scaleEffect(draft.imageScale * gestureScale)
                            .offset(
                                // draft.imageOffset is stored NORMALIZED
                                // (fraction of canvas width/height) — see
                                // PostcardDraft.rendered(at:)'s comment — so
                                // it must be scaled back up by this canvas's
                                // own current imgSize to get raw points for
                                // display here. gestureDrag (the live,
                                // uncommitted delta) is already in this
                                // canvas's raw points, added as-is.
                                x: draft.imageOffset.width * imgSize.width + gestureDrag.width,
                                y: draft.imageOffset.height * imgSize.height + gestureDrag.height
                            )
                            .clipped()
                            // The photo never needs to handle touches itself
                            // (the dedicated Color.clear layer below does
                            // all gesture recognition) — but `.scaleEffect`
                            // is a geometry effect, so SwiftUI's hit-testing
                            // still follows the SCALED bounds, not the
                            // clipped visual ones. Without this, a zoomed-in
                            // photo's tappable region can extend past its
                            // clip into whatever's above the canvas (e.g.
                            // the Undo button), intercepting taps there
                            // depending on exactly how it's scaled/panned.
                            .allowsHitTesting(false)
                    }

                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: imgSize.width, height: imgSize.height)
                        // `.simultaneousGesture` rather than `.gesture` — a
                        // pure pinch (MagnificationGesture) with no panning
                        // component, attached via `.gesture`, can leave the
                        // multi-touch session in a state where the very next
                        // single tap ANYWHERE (even the unrelated Undo
                        // button above) gets swallowed, since `.gesture`
                        // claims exclusive priority over gesture resolution.
                        // `.simultaneousGesture` doesn't claim that
                        // exclusivity, letting the Undo button's own tap
                        // recognize normally right after a pinch-only zoom.
                        .simultaneousGesture(
                            SimultaneousGesture(
                                MagnificationGesture()
                                    .updating($gestureScale) { value, state, _ in state = value }
                                    .onEnded { value in
                                        // No lower clamp at 1.0 — zooming out
                                        // smaller than "fill" is allowed; the
                                        // resulting gap around the photo is
                                        // handled by a solid backdrop fill,
                                        // both in this live preview (the
                                        // Color.white behind it) and in the
                                        // real print bake (PostcardDraft.
                                        // rendered(at:)). Only floors at a
                                        // small positive value so the photo
                                        // can never invert/collapse to zero.
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
                }
                .frame(width: imgSize.width, height: imgSize.height)
                .clipped()
            }
            .frame(width: frameSize.width, height: frameSize.height)
            .compositingGroup()
            .shadow(radius: 4)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)

            Button("Choose a Different Photo") {
                isPickerPresented = true
            }
            .font(.system(size: 15, weight: .regular))
            .padding(.top, 6)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 10)
    }

    // From/To nickname entry — half-width side by side (label above field).
    private var fromToRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("To")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.brandBlue)
                    HStack(spacing: 8) {
                        Button {
                            showToContactPicker = true
                        } label: {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .foregroundColor(.accentColor)
                                .frame(minWidth: 28, minHeight: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        TextField("e.g. Grandma & Grandpa", text: $draft.recipientNickname)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 2) {
                    Text("From")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.brandBlue)
                    TextField("e.g. Pookie", text: $draft.senderNickname)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: draft.senderNickname) { _, newValue in
                            nicknameSyncTask?.cancel()
                            nicknameSyncTask = Task {
                                try? await Task.sleep(nanoseconds: 800_000_000)
                                guard !Task.isCancelled else { return }
                                await UserService.updateSenderNickname(newValue)
                            }
                        }
                }
                .frame(maxWidth: .infinity)
            }

            if usedContactPickerForTo {
                Text("Edit to use a different nickname, sunshine")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.brandBlue)
                    .padding(.leading, 8)
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .sheet(isPresented: $showToContactPicker) {
            ContactNamePickerView { info in
                if !info.nickname.isEmpty { draft.recipientNickname = info.nickname }
                contactPickedNickname = draft.recipientNickname
                draft.recipientFirstName = info.firstName
                draft.recipientLastName  = info.lastName
                draft.recipientStreet    = info.street
                draft.recipientCity      = info.city
                draft.recipientState     = info.state
                draft.recipientZip       = info.zip
                draft.recipientCountry   = info.country
                draft.recipientEmail     = info.email
                draft.recipientPhone     = info.phone
            }
        }
    }

    @ViewBuilder
    private var emptyPhotoState: some View {
        VStack(spacing: 16) {
            Spacer()
            if isModerating {
                ProgressView("Checking photo…")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)
                Text("Choose a photo for your card")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                isPickerPresented = true
            } label: {
                Text("Choose Photo")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isModerating ? Color.gray : Color.brandBlue)
                    .foregroundColor(.white)
                    .cornerRadius(999)
            }
            .disabled(isModerating)
            .padding(.horizontal)
            Spacer()
        }
    }

    // Bakes composedImage at the CANONICAL print resolution (2700x1800 /
    // 1800x2700), never at this step's own small live-viewport size — see
    // [[feedback_editor_print_sync_bitmap]].
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

    private func updateFilterThumbnailsIfNeeded(_ overrideImage: UIImage? = nil) {
        guard let base = draft.composedImage ?? overrideImage ?? draft.image else { return }
        guard base !== filterThumbnailsSourceImage else { return }
        filterThumbnailsSourceImage = base
        let thumbSize: CGFloat = 64
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> [PostcardFilter: UIImage] in
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: thumbSize, height: thumbSize))
                let small = renderer.image { _ in
                    let side = min(base.size.width, base.size.height)
                    let cropRect = CGRect(
                        x: (base.size.width  - side) / 2,
                        y: (base.size.height - side) / 2,
                        width: side, height: side
                    )
                    let scale = thumbSize / side
                    let drawRect = CGRect(
                        x: -cropRect.minX * scale,
                        y: -cropRect.minY * scale,
                        width: base.size.width * scale,
                        height: base.size.height * scale
                    )
                    base.draw(in: drawRect)
                }
                var thumbs: [PostcardFilter: UIImage] = [:]
                for filter in PostcardFilter.allCases {
                    thumbs[filter] = filter.apply(to: small)
                }
                return thumbs
            }.value
            guard base === filterThumbnailsSourceImage else { return }
            filterThumbnails = result
        }
    }

    private func postcardFrameSize(availableSize: CGSize) -> CGSize {
        guard availableSize.width > 0, availableSize.height > 0 else { return .zero }
        let maxWidth  = availableSize.width - 32
        // Unlike Style It's frame math, this GeometryReader only needs to
        // reserve space for ITS OWN internal chrome now — the pinch/drag
        // hint row (~32pt incl. top padding), this canvas's own top padding
        // (10pt), and the "Choose a Different Photo" link below (~32pt incl.
        // padding) — From/To and the toggles are separate VStack siblings
        // outside this GeometryReader, sized automatically. Itemized: hint
        // row ~28pt, canvas top padding 10pt, "Choose a Different Photo"
        // ~30pt, outer bottom padding 10pt = ~78pt; 90 gives that a small
        // cushion without starving the canvas the way the old 120 guess did.
        let maxHeight = availableSize.height - 90
        let ratio = draft.orientation.aspectRatio
        if ratio >= 1 {
            let w = min(maxWidth, maxHeight * ratio)
            return CGSize(width: w, height: w / ratio)
        } else {
            // Unlike Style It's much larger GeometryReader (where portrait
            // got a deliberate 1/3 height boost since maxWidth/ratio was
            // comfortably under maxHeight there), this safe zone is a small,
            // tightly-reserved area — boosting past maxHeight here overflows
            // the canvas past its own bounds (GeometryReader doesn't clip
            // children) and into the "Choose a Different Photo" link below.
            // Stay height-bound at maxHeight, same margin landscape gets.
            let h = min(maxHeight, maxWidth / ratio)
            return CGSize(width: h * ratio, height: h)
        }
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
}

// MARK: - Photo Picking Pipeline
//
// Extracted as its own ViewModifier — see TextOverlayStepView.swift's
// history for why (SourceKit/type-checker strain on long modifier chains).
private struct PhotoPickingPipeline: ViewModifier {
    @ObservedObject var draft: PostcardDraft
    @Binding var photoItem: PhotosPickerItem?
    @Binding var isPickerPresented: Bool
    @Binding var isModerating: Bool
    @Binding var pendingLowResImage: UIImage?
    @Binding var showLowResAlert: Bool
    @Binding var flaggedCategories: [String]
    @Binding var showModerationAlert: Bool

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $isPickerPresented, selection: $photoItem, matching: .images)
            .task {
                if draft.image == nil { isPickerPresented = true }
            }
            .onChange(of: photoItem) { _, newItem in
                Task {
                    guard let data = try? await newItem?.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { return }

                    isModerating = true
                    let result = await ModerationService.check(image: image)
                    isModerating = false

                    switch result {
                    case .flagged(let categories):
                        flaggedCategories = categories
                        showModerationAlert = true
                        photoItem = nil
                        return
                    case .clean:
                        break
                    }

                    let pixelWidth  = image.size.width  * image.scale
                    let pixelHeight = image.size.height * image.scale
                    let longSide    = max(pixelWidth, pixelHeight)
                    let shortSide   = min(pixelWidth, pixelHeight)
                    if longSide < minPrintPixels || shortSide < minPrintPixelsShort {
                        pendingLowResImage = image
                        showLowResAlert = true
                        return
                    }

                    draft.image = image
                    draft.imageScale = 1.0
                    draft.imageOffset = .zero
                }
            }
            .alert("Photo May Print Blurry", isPresented: $showLowResAlert) {
                Button("Use Anyway") {
                    draft.image = pendingLowResImage
                    pendingLowResImage = nil
                }
                Button("Choose Different Photo", role: .cancel) {
                    pendingLowResImage = nil
                    photoItem = nil
                    isPickerPresented = true
                }
            } message: {
                Text("This photo is lower resolution than recommended for a postcard and may not print as sharply as you'd like.")
            }
            .alert("Photo Not Allowed", isPresented: $showModerationAlert) {
                Button("Choose a Different Photo", role: .cancel) { isPickerPresented = true }
            } message: {
                Text("That photo was flagged for: \(flaggedCategories.joined(separator: ", ")). Please choose a different photo.")
            }
    }
}

private extension View {
    func photoPickingPipeline(
        draft: PostcardDraft,
        photoItem: Binding<PhotosPickerItem?>,
        isPickerPresented: Binding<Bool>,
        isModerating: Binding<Bool>,
        pendingLowResImage: Binding<UIImage?>,
        showLowResAlert: Binding<Bool>,
        flaggedCategories: Binding<[String]>,
        showModerationAlert: Binding<Bool>
    ) -> some View {
        modifier(PhotoPickingPipeline(
            draft: draft, photoItem: photoItem, isPickerPresented: isPickerPresented,
            isModerating: isModerating, pendingLowResImage: pendingLowResImage,
            showLowResAlert: showLowResAlert, flaggedCategories: flaggedCategories,
            showModerationAlert: showModerationAlert
        ))
    }
}

// MARK: - Sliding Toggle  (2-option pill with an animated blue thumb that
// slides to the selected side — used for Orientation and Border. Not
// .pickerStyle(.segmented): a native segmented control has its own fixed
// intrinsic height and won't stretch to fill a taller frame.)
private struct SlidingTogglePill<T: Hashable>: View {
    let options: [(value: T, label: String)]
    let selection: T
    let onSelect: (T) -> Void

    @EnvironmentObject private var appSettings: AppSettings

    var body: some View {
        let theme = appSettings.uiTheme
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                Text(option.label)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(selection == option.value ? theme.textOnAccent : .primary)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 999)
                            .fill(theme.accentColor)
                            .opacity(selection == option.value ? 1 : 0)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard selection != option.value else { return }
                        withAnimation(.easeInOut(duration: 0.2)) { onSelect(option.value) }
                    }
            }
        }
        .padding(3)
        .themedSurface(theme, cornerRadius: 999)
    }
}

#Preview {
    ChoosePhotoStepView(draft: PostcardDraft(), photoItem: .constant(nil), onNext: {})
        .environmentObject(AppSettings())
}
