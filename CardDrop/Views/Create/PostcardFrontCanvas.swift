import SwiftUI
import CoreImage.CIFilterBuiltins

struct PostcardFrontCanvas: View {
    let image: UIImage?
    let overlays: [TextOverlay]
    let qrOverlays: [QROverlay]
    let burstOverlays: [BurstCaptionOverlay]
    let greetingsOverlays: [GreetingsOverlay]
    let size: CGSize
    var border: PostcardBorder = .fullBleed
    var orientation: PostcardOrientation = .landscape
    var borderText: String = ""
    var borderFontName: String = "Georgia"
    var borderTextColor: Color = .black
    var onQRLongPress: ((String) -> Void)? = nil

    init(image: UIImage?, overlays: [TextOverlay], qrOverlays: [QROverlay] = [],
         burstOverlays: [BurstCaptionOverlay] = [], greetingsOverlays: [GreetingsOverlay] = [], size: CGSize,
         border: PostcardBorder = .fullBleed, orientation: PostcardOrientation = .landscape,
         borderText: String = "", borderFontName: String = "Georgia", borderTextColor: Color = .black,
         onQRLongPress: ((String) -> Void)? = nil) {
        self.image = image
        self.overlays = overlays
        self.qrOverlays = qrOverlays
        self.burstOverlays = burstOverlays
        self.greetingsOverlays = greetingsOverlays
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
                    // Rendered once as a bitmap at the canonical print
                    // resolution (see GreetingsBadgeRenderer) — the exact
                    // same code path/bitmap the live editor scales down to
                    // preview, so the two can never drift apart. Scaled here
                    // only if imageAreaSize is smaller than the true print
                    // resolution (e.g. a bordered/inset front).
                    let isLandscapeGreetings = imageAreaSize.width >= imageAreaSize.height
                    let greetingsReferenceWidth: CGFloat = isLandscapeGreetings ? 2775 : 1875
                    let greetingsDisplayScale = imageAreaSize.width / greetingsReferenceWidth
                    if let rendered = GreetingsBadgeRenderer.render(overlay: greeting, isLandscape: isLandscapeGreetings) {
                        // +75 bleed-margin match — see GreetingsCaptionView's identical fix.
                        let badgeSize: CGSize = greeting.fixedPosition == .left
                            ? CGSize(width: isLandscapeGreetings ? 2925 : 2000, height: rendered.size.height)
                            : rendered.size
                        let center = greeting.fixedPosition.center(badgeSize: badgeSize, canvasSize: CGSize(width: greetingsReferenceWidth, height: greetingsReferenceWidth * imageAreaSize.height / imageAreaSize.width))
                        let w = rendered.size.width * greetingsDisplayScale
                        let h = rendered.size.height * greetingsDisplayScale
                        // The bitmap itself has a transparent background
                        // (see GreetingsBadgeRenderer) — draw the badge
                        // color underneath it here.
                        ZStack {
                            Rectangle().fill(greeting.badgeColorChoice.color.opacity(greeting.backgroundOpacity))
                            Image(uiImage: rendered.image)
                                .resizable()
                        }
                        .frame(width: w, height: h)
                        .rotationEffect(Angle(degrees: greeting.fixedPosition.rotationDegrees))
                        .position(x: center.x * greetingsDisplayScale, y: center.y * greetingsDisplayScale)
                    }
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
