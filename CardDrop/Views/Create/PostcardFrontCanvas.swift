import SwiftUI
import CoreImage.CIFilterBuiltins

struct PostcardFrontCanvas: View {
    let image: UIImage?
    let overlays: [TextOverlay]
    let qrOverlays: [QROverlay]
    let burstOverlays: [BurstCaptionOverlay]
    let greetingsOverlays: [GreetingsOverlay]
    // "Put subject in front" — already baked (see PostcardDraft.
    // renderSubjectCutoutComposedImage) to this canvas's own size, with a
    // transparent background and the subject positioned exactly where it
    // sits on the photo beneath it. nil when no cutout exists.
    var subjectCutoutImage: UIImage? = nil
    let size: CGSize
    var border: PostcardBorder = .fullBleed
    var orientation: PostcardOrientation = .landscape
    var borderText: String = ""
    var borderFontName: String = "Georgia"
    var borderTextColor: Color = .black
    var onQRLongPress: ((String) -> Void)? = nil

    init(image: UIImage?, overlays: [TextOverlay], qrOverlays: [QROverlay] = [],
         burstOverlays: [BurstCaptionOverlay] = [], greetingsOverlays: [GreetingsOverlay] = [],
         subjectCutoutImage: UIImage? = nil, size: CGSize,
         border: PostcardBorder = .fullBleed, orientation: PostcardOrientation = .landscape,
         borderText: String = "", borderFontName: String = "Georgia", borderTextColor: Color = .black,
         onQRLongPress: ((String) -> Void)? = nil) {
        self.image = image
        self.overlays = overlays
        self.qrOverlays = qrOverlays
        self.burstOverlays = burstOverlays
        self.greetingsOverlays = greetingsOverlays
        self.subjectCutoutImage = subjectCutoutImage
        self.size = size
        self.border = border
        self.orientation = orientation
        self.borderText = borderText
        self.borderFontName = borderFontName
        self.borderTextColor = borderTextColor
        self.onQRLongPress = onQRLongPress
    }

    private var imageAreaSize: CGSize {
        let insetFractions: (x: Double, y: Double)
        switch border {
        case .fullBleed:
            return size
        case .whiteBorder:
            switch orientation {
            case .landscape: insetFractions = (0.25/6.0, 0.25/4.0)
            case .portrait:  insetFractions = (0.25/4.0, 0.25/6.0)
            }
        case .customText, .decorative:
            switch orientation {
            case .landscape: insetFractions = (3.0/8.0/6.0, 3.0/8.0/4.0)
            case .portrait:  insetFractions = (3.0/8.0/4.0, 3.0/8.0/6.0)
            }
        }
        let insetX = size.width  * insetFractions.x
        let insetY = size.height * insetFractions.y
        return CGSize(width: size.width - 2 * insetX, height: size.height - 2 * insetY)
    }

    var body: some View {
        ZStack {
            if border == .whiteBorder || border == .customText || border == .decorative { Color.white }
            ZStack {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: imageAreaSize.width, height: imageAreaSize.height)
                        .clipped()
                } else {
                    Color.black.frame(width: imageAreaSize.width, height: imageAreaSize.height)
                }
                ForEach(burstOverlays) { burst in
                    let preset = BurstPreset.find(burst.presetID)
                    let bh = burst.normalizedHeight * imageAreaSize.height
                    BurstCaptionView(text: burst.text, preset: preset, burstHeight: bh)
                        .rotationEffect(Angle(degrees: burst.rotation))
                        .position(
                            x: burst.normalizedPosition.x * imageAreaSize.width,
                            y: burst.normalizedPosition.y * imageAreaSize.height
                        )
                }
                ForEach(greetingsOverlays) { greeting in
                    greetingsBadgeView(greeting)
                }
                // "Put subject in front" — already baked/positioned to
                // exactly this canvas's imageAreaSize (see
                // PostcardDraft.renderSubjectCutoutComposedImage); no
                // further transform needed here, unlike the live editor's
                // own gesture-scaled version of this same layer.
                if let cutout = subjectCutoutImage {
                    Image(uiImage: cutout)
                        .resizable()
                        .frame(width: imageAreaSize.width, height: imageAreaSize.height)
                }
                ForEach(overlays) { overlay in
                    overlayView(overlay)
                }
                // QR (invisible ink) renders last so it's always on top of
                // any other styling object it might share space with.
                ForEach(qrOverlays) { qr in
                    if let img = makeQRImage(for: qr) {
                        let sz = QROverlay.fixedNormalizedSize * min(imageAreaSize.width, imageAreaSize.height)
                        Image(uiImage: img)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: sz, height: sz)
                            .cornerRadius(4)
                            .onLongPressGesture(minimumDuration: 0.5) {
                                onQRLongPress?(qr.content)
                            }
                            .position(
                                x: qr.normalizedPosition.x * imageAreaSize.width,
                                y: qr.normalizedPosition.y * imageAreaSize.height
                            )
                    }
                }
            }
            .frame(width: imageAreaSize.width, height: imageAreaSize.height)
            .clipped()

            if (border == .customText || border == .decorative) && !borderText.isEmpty {
                CustomTextBorderView(
                    cardSize: size,
                    orientation: orientation,
                    text: borderText,
                    fontName: borderFontName,
                    textColor: borderTextColor
                )
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func makeQRImage(for qr: QROverlay) -> UIImage? {
        guard !qr.content.isEmpty,
              let data = qr.content.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M",  forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    @ViewBuilder
    private func greetingsBadgeView(_ greeting: GreetingsOverlay) -> some View {
        // Rendered once as a bitmap at the canonical print resolution (see
        // GreetingsBadgeRenderer) — the exact same code path/bitmap the live
        // editor scales down to preview, so the two can never drift apart.
        // Scaled here only if imageAreaSize is smaller than the true print
        // resolution (e.g. a bordered/inset front).
        let isLandscapeGreetings = imageAreaSize.width >= imageAreaSize.height
        let greetingsReferenceWidth: CGFloat = isLandscapeGreetings ? 2775 : 1875
        let greetingsDisplayScale = imageAreaSize.width / greetingsReferenceWidth
        if let rendered = GreetingsBadgeRenderer.render(overlay: greeting, isLandscape: isLandscapeGreetings) {
            // Badge always sizes itself to its true rendered content —
            // Tilt's clearance from the card's left/right edges is
            // guaranteed by the rotated-bounding-box math in
            // GreetingsFixedPosition.center().
            let center = greeting.fixedPosition.center(badgeSize: rendered.size, canvasSize: CGSize(width: greetingsReferenceWidth, height: greetingsReferenceWidth * imageAreaSize.height / imageAreaSize.width))
            let w = rendered.size.width * greetingsDisplayScale
            let h = rendered.size.height * greetingsDisplayScale

            // Tilt's background "ribbon" is positioned/sized independently
            // of the text — `center` above is already solved to guarantee
            // 0.5in clearance from the card's left/right edges (see
            // GreetingsFixedPosition.center()); the ribbon instead centers
            // itself on the card's own horizontal midpoint and is widened
            // just enough that its rotated footprint bleeds off both edges.
            // `t` is the shift (print-scale, along the ribbon's own rotated
            // axis) between the two centers, applied as a live offset on
            // the text image so one shared rotation/position transform
            // serves both.
            let isTiltPos = greeting.fixedPosition.isTilt
            let isCorner = greeting.fixedPosition == .corner
            let rotationDeg = greeting.fixedPosition.rotationDegrees(isLandscape: isLandscapeGreetings)
            let theta = rotationDeg * .pi / 180
            let t: CGFloat = isTiltPos ? (greetingsReferenceWidth / 2 - center.x) / cos(theta) : 0
            let ribbonCenter = CGPoint(x: center.x + t * cos(theta), y: center.y + t * sin(theta))

            // Centered badges get a background that spans the full card
            // width — the badge content (image) stays its own natural size,
            // centered within that wider background, rather than being
            // stretched to fill it. Tilt gets a similarly wide background
            // (the bleeding ribbon), computed to guarantee edge-to-edge
            // coverage once rotated.
            // +150 (0.5in print-scale) overshoot on each side beyond the
            // exact minimum — the bare-minimum width just barely grazes the
            // edges with zero margin, vulnerable to rounding; overshooting
            // is free since the excess is simply clipped off-canvas.
            let ribbonWidthPrintScale = (greetingsReferenceWidth + 300 - rendered.size.height * abs(sin(theta))) / abs(cos(theta))
            let bgWidth: CGFloat = greeting.fixedPosition == .center
                ? imageAreaSize.width
                : (isTiltPos ? ribbonWidthPrintScale * greetingsDisplayScale : w)
            // The bitmap itself has a transparent background (see
            // GreetingsBadgeRenderer) — draw the badge color underneath it here.
            let badgeLayer = ZStack {
                Rectangle().fill(isCorner ? Color.clear : greeting.badgeColorChoice.color.opacity(greeting.backgroundOpacity))
                    .frame(width: bgWidth, height: h)
                Image(uiImage: rendered.image)
                    .resizable()
                    .frame(width: w, height: h)
                    .offset(x: -t * greetingsDisplayScale)
            }
            .frame(width: bgWidth, height: h)
            .rotationEffect(Angle(degrees: rotationDeg))
            .position(x: ribbonCenter.x * greetingsDisplayScale, y: ribbonCenter.y * greetingsDisplayScale)

            if isCorner {
                // Corner position: ribbon + the exposed top-left corner as one
                // filled path in canvas space, under the badge (same shape the
                // live editor draws — see GreetingsCornerBackgroundShape).
                ZStack(alignment: .topLeading) {
                    GreetingsCornerBackgroundShape(
                        ribbonCenter: CGPoint(x: ribbonCenter.x * greetingsDisplayScale, y: ribbonCenter.y * greetingsDisplayScale),
                        ribbonSize: CGSize(width: ribbonWidthPrintScale * greetingsDisplayScale, height: h),
                        theta: CGFloat(theta),
                        overshoot: 300 * greetingsDisplayScale,
                        tuck: 2 * greetingsDisplayScale
                    )
                    .fill(greeting.badgeColorChoice.color.opacity(greeting.backgroundOpacity))
                    badgeLayer
                }
                .frame(width: imageAreaSize.width, height: imageAreaSize.height)
            } else {
                badgeLayer
            }
        }
    }

    @ViewBuilder
    private func overlayView(_ overlay: TextOverlay) -> some View {
        // Editor-canvas-native size -> print-resolution-canvas size
        // multiplier. See TextOverlayBubbleView's doc comment: that shared
        // view is what guarantees this stays in sync with the live editor.
        let fontScale: CGFloat = overlay.canvasWidth > 0
            ? imageAreaSize.width / overlay.canvasWidth
            : 1
        TextOverlayBubbleView(
            overlay: overlay,
            scale: fontScale,
            boxWidth: overlay.normalizedWidth * imageAreaSize.width
        )
        .rotationEffect(Angle(degrees: overlay.rotation))
        .position(
            x: overlay.normalizedPosition.x * imageAreaSize.width,
            y: overlay.normalizedPosition.y * imageAreaSize.height
        )
    }
}
