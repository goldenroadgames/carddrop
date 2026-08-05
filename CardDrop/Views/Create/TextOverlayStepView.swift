import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - Step View

struct TextOverlayStepView: View {
    @ObservedObject var draft: PostcardDraft
    var onNext: () -> Void

    @State private var selectedIndex: Int? = nil
    @State private var selectedQRIndex: Int? = nil
    @State private var selectedBurstIndex: Int? = nil
    @State private var cachedFilteredImage: UIImage? = nil
    @State private var filterThumbnails: [PostcardFilter: UIImage] = [:]
    @State private var filterThumbnailsSourceImage: UIImage? = nil

    private let filmstripHeight: CGFloat = 92

    var body: some View {
        GeometryReader { geo in
            let isEditing = selectedIndex != nil || selectedQRIndex != nil || selectedBurstIndex != nil
            let frameSize = postcardFrameSize(availableSize: geo.size, isEditing: false)
            let imgSize   = imageAreaSize(in: frameSize)

            VStack(spacing: 0) {
                // Filters
                if draft.composedImage != nil || draft.image != nil {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(PostcardFilter.allCases, id: \.self) { filter in
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
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                    }
                    .background(Color(.systemBackground))

                    Divider()
                }

                // Canvas
                ZStack {
                    (draft.border == .whiteBorder || draft.border == .decorative) ? Color.white : Color.black

                    ZStack {
                        if let img = cachedFilteredImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: imgSize.width, height: imgSize.height)
                                .clipped()
                        }

                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: imgSize.width, height: imgSize.height)
                            .onTapGesture { selectedIndex = nil; selectedQRIndex = nil; selectedBurstIndex = nil }

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
                                isSelected: selectedIndex == draft.textOverlays.firstIndex(where: { $0.id == overlay.id }),
                                onSelect: {
                                    selectedIndex = draft.textOverlays.firstIndex(where: { $0.id == overlay.id })
                                    selectedQRIndex = nil
                                    selectedBurstIndex = nil
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

                // Add buttons shown below canvas only when nothing is selected
                if !isEditing {
                    Divider().padding(.top, 10)
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Button(action: { addTextOverlay(canvasWidth: imgSize.width) }) {
                                Label("Add Text", systemImage: "plus.circle")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color(.secondarySystemBackground))
                                    .foregroundColor(.primary)
                                    .cornerRadius(10)
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
                            }
                        }) {
                            Label("Invisible Ink", systemImage: "eye.slash")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color(.secondarySystemBackground))
                                .foregroundColor(.primary)
                                .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.easeInOut(duration: 0.2), value: isEditing)
            // Edit panel: anchored to the bottom, flush above "Next" (stays within the safe area)
            .overlay(alignment: .bottom) {
                if isEditing {
                    editPanel(imgSize: imgSize)
                        .background(.regularMaterial)
                        .cornerRadius(12)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 2)
                        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: -3)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: onNext) {
                Text("Next: Write Card")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.brandBlue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(uiColor: .systemBackground))
        }
        .onAppear {
            updateCachedFilteredImage()
            updateFilterThumbnailsIfNeeded()
        }
        .onChange(of: draft.filter) { _, _ in updateCachedFilteredImage() }
        .onReceive(draft.$composedImage) { _ in updateFilterThumbnailsIfNeeded() }
        .onReceive(draft.$image) { _ in updateFilterThumbnailsIfNeeded() }
    }

    private func updateCachedFilteredImage() {
        guard let base = draft.composedImage ?? draft.image else { return }
        cachedFilteredImage = draft.filter.apply(to: base)
    }

    private func updateFilterThumbnailsIfNeeded() {
        guard let base = draft.composedImage ?? draft.image else { return }
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

    @ViewBuilder
    private func editPanel(imgSize: CGSize) -> some View {
        if let idx = selectedIndex, draft.textOverlays.indices.contains(idx) {
            TextOverlayEditPanel(
                overlay: Binding(
                    get: { draft.textOverlays.indices.contains(idx) ? draft.textOverlays[idx] : TextOverlay() },
                    set: { if draft.textOverlays.indices.contains(idx) { draft.textOverlays[idx] = $0 } }
                ),
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
        }
    }

    private func addTextOverlay(canvasWidth: CGFloat) {
        draft.textOverlays.append(TextOverlay(canvasWidth: canvasWidth))
        selectedIndex = draft.textOverlays.count - 1
        selectedQRIndex = nil
    }

    private func addBurstOverlay(canvasHeight: CGFloat) {
        draft.burstOverlays.append(BurstCaptionOverlay(canvasHeight: canvasHeight))
        selectedBurstIndex = draft.burstOverlays.count - 1
        selectedIndex = nil
        selectedQRIndex = nil
    }

    private func addQROverlay() {
        draft.qrOverlays.append(QROverlay())
        selectedQRIndex = draft.qrOverlays.count - 1
        selectedIndex = nil
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

    private func postcardFrameSize(availableSize: CGSize, isEditing: Bool = false) -> CGSize {
        guard availableSize.width > 0, availableSize.height > 0 else { return .zero }
        let maxWidth  = availableSize.width  - 32
        let maxHeight = availableSize.height - (isEditing ? 240 : 160) - filmstripHeight
        let ratio = draft.orientation.aspectRatio
        if ratio >= 1 {
            let w = min(maxWidth, maxHeight * ratio)
            return CGSize(width: w, height: w / ratio)
        } else {
            let h = min(maxHeight, maxWidth / ratio)
            return CGSize(width: h * ratio, height: h)
        }
    }
}

// MARK: - Individual Item View

struct TextOverlayItemView: View {
    @Binding var overlay: TextOverlay
    let canvasSize: CGSize
    let isSelected: Bool
    let onSelect: () -> Void

    @GestureState private var dragOffset: CGSize = .zero
    @State private var resizeDragBaseWidth: CGFloat = 0
    @State private var rotationDragBase: Double? = nil

    // Extra padding on each side to accommodate the bubble tail
    private var topTailPadding: CGFloat {
        if overlay.bgStyle == .speech  && overlay.tailFlippedV { return SpeechBubbleShape.tailHeight }
        if overlay.bgStyle == .thought && overlay.tailFlippedV { return ThoughtBubbleShape.tailHeight }
        return 0
    }
    private var bottomTailPadding: CGFloat {
        if overlay.bgStyle == .speech  && !overlay.tailFlippedV { return SpeechBubbleShape.tailHeight }
        if overlay.bgStyle == .thought && !overlay.tailFlippedV { return ThoughtBubbleShape.tailHeight }
        return 0
    }

    var body: some View {
        Text(overlay.text.isEmpty ? " " : overlay.text)
            .font(.custom(overlay.resolvedFontName, size: overlay.fontSize))
            .foregroundColor(overlay.textColor)
            .frame(width: overlay.normalizedWidth * canvasSize.width, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top,    8 + topTailPadding)
            .padding(.bottom, 8 + bottomTailPadding)
            .background(backgroundShape)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.white : Color.clear, lineWidth: 1.5)
                    .padding(-3)
            )
            // Resize handle — bottom-trailing
            .overlay(alignment: .bottomTrailing) {
                if isSelected {
                    ResizeHandleView(
                        normalizedWidth: $overlay.normalizedWidth,
                        canvasWidth: canvasSize.width,
                        baseWidthStorage: $resizeDragBaseWidth
                    )
                    .offset(x: 8, y: 8)
                }
            }
            // Rotate handle — bottom-leading
            .overlay(alignment: .bottomLeading) {
                if isSelected {
                    Image(systemName: "arrow.trianglehead.clockwise")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.orange)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .offset(x: -8, y: 8)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if rotationDragBase == nil { rotationDragBase = overlay.rotation }
                                    let delta = value.translation.width + value.translation.height
                                    overlay.rotation = (rotationDragBase ?? 0) + delta * 0.35
                                }
                                .onEnded { _ in rotationDragBase = nil }
                        )
                }
            }
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

    @ViewBuilder
    private var backgroundShape: some View {
        switch overlay.bgStyle {
        case .none:
            Color.clear
        case .box:
            RoundedRectangle(cornerRadius: 10)
                .fill(overlay.bgColor)
        case .speech:
            SpeechBubbleShape(tailOnLeft: !overlay.tailFlippedH, tailOnBottom: !overlay.tailFlippedV)
                .fill(overlay.bgColor)
        case .thought:
            ThoughtBubbleShape(tailOnLeft: !overlay.tailFlippedH, tailOnBottom: !overlay.tailFlippedV)
                .fill(overlay.bgColor)
        }
    }
}

// MARK: - Resize Handle

struct ResizeHandleView: View {
    @Binding var normalizedWidth: CGFloat
    let canvasWidth: CGFloat
    @Binding var baseWidthStorage: CGFloat

    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 20, height: 20)
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if baseWidthStorage == 0 { baseWidthStorage = normalizedWidth }
                        let newW = baseWidthStorage + value.translation.width / canvasWidth
                        normalizedWidth = max(80 / canvasWidth, min(0.92, newW))
                    }
                    .onEnded { _ in baseWidthStorage = 0 }
            )
    }
}

// MARK: - Edit Panel

struct TextOverlayEditPanel: View {
    @Binding var overlay: TextOverlay
    var onDelete: () -> Void
    var onDone: () -> Void

    @FocusState private var textFocused: Bool
    private let charLimit = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Row 1: Done, Delete, BG controls, color, mirror — all in one scrollable strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button("Done", action: onDone)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)

                    Button(action: onDelete) {
                        Image(systemName: "trash").foregroundColor(.red)
                    }
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())

                    Divider().frame(height: 24)

                    ForEach(TextBgStyle.allCases, id: \.self) { style in
                        Button(action: { overlay.bgStyle = style }) {
                            Image(systemName: style.systemImage)
                                .font(.system(size: 15))
                                .frame(width: 34, height: 30)
                                .background(overlay.bgStyle == style ? Color.accentColor : Color(.secondarySystemBackground))
                                .foregroundColor(overlay.bgStyle == style ? .white : .primary)
                                .cornerRadius(8)
                        }
                    }

                    if overlay.bgStyle != .none {
                        ColorPicker("", selection: $overlay.bgColor).labelsHidden()
                    }

                    if overlay.bgStyle == .speech || overlay.bgStyle == .thought {
                        Divider().frame(height: 24)

                        Button(action: { overlay.tailFlippedH.toggle() }) {
                            Image(systemName: "arrow.left.and.right")
                                .font(.system(size: 14))
                                .frame(width: 34, height: 30)
                                .background(overlay.tailFlippedH ? Color.accentColor : Color(.secondarySystemBackground))
                                .foregroundColor(overlay.tailFlippedH ? .white : .primary)
                                .cornerRadius(8)
                        }

                        Button(action: { overlay.tailFlippedV.toggle() }) {
                            Image(systemName: "arrow.up.and.down")
                                .font(.system(size: 14))
                                .frame(width: 34, height: 30)
                                .background(overlay.tailFlippedV ? Color.accentColor : Color(.secondarySystemBackground))
                                .foregroundColor(overlay.tailFlippedV ? .white : .primary)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal, 2)
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
                                .cornerRadius(8)
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
                    in: 12...60, step: 1
                )
                Text("\(Int(overlay.fontSize))")
                    .font(.caption).foregroundColor(.secondary).frame(width: 26)
                Button(action: { overlay.isBold.toggle() }) {
                    Text("B")
                        .font(.custom("Georgia-Bold", size: 16))
                        .frame(width: 34, height: 30)
                        .background(overlay.isBold ? Color.accentColor : Color(.secondarySystemBackground))
                        .foregroundColor(overlay.isBold ? .white : .primary)
                        .cornerRadius(8)
                }
                Button(action: { overlay.isItalic.toggle() }) {
                    Text("I")
                        .font(.custom("Georgia-Italic", size: 16))
                        .frame(width: 34, height: 30)
                        .background(overlay.isItalic ? Color.accentColor : Color(.secondarySystemBackground))
                        .foregroundColor(overlay.isItalic ? .white : .primary)
                        .cornerRadius(8)
                }
                ColorPicker("", selection: $overlay.textColor).labelsHidden()
            }

            // Row 4: Full-width text box with char cap
            ZStack(alignment: .topLeading) {
                if overlay.text.isEmpty {
                    Text("Your text")
                        .foregroundColor(Color(.placeholderText))
                        .padding(.horizontal, 5)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $overlay.text)
                    .frame(minHeight: 60, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .focused($textFocused)
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
                        .cornerRadius(8)

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
                            .cornerRadius(8)
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
                            .cornerRadius(8)
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
