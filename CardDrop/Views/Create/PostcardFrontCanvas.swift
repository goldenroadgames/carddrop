import SwiftUI
import CoreImage.CIFilterBuiltins

struct PostcardFrontCanvas: View {
    let image: UIImage?
    let overlays: [TextOverlay]
    let qrOverlays: [QROverlay]
    let burstOverlays: [BurstCaptionOverlay]
    let size: CGSize
    var border: PostcardBorder = .fullBleed
    var orientation: PostcardOrientation = .landscape
    var borderText: String = ""
    var borderFontName: String = "Georgia"
    var borderTextColor: Color = .black
    var onQRLongPress: ((String) -> Void)? = nil

    init(image: UIImage?, overlays: [TextOverlay], qrOverlays: [QROverlay] = [],
         burstOverlays: [BurstCaptionOverlay] = [], size: CGSize,
         border: PostcardBorder = .fullBleed, orientation: PostcardOrientation = .landscape,
         borderText: String = "", borderFontName: String = "Georgia", borderTextColor: Color = .black,
         onQRLongPress: ((String) -> Void)? = nil) {
        self.image = image
        self.overlays = overlays
        self.qrOverlays = qrOverlays
        self.burstOverlays = burstOverlays
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
                ForEach(overlays) { overlay in
                    overlayView(overlay)
                }
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
        let topPad: CGFloat = {
            if overlay.bgStyle == .speech  && overlay.tailFlippedV { return SpeechBubbleShape.tailHeight }
            if overlay.bgStyle == .thought && overlay.tailFlippedV { return ThoughtBubbleShape.tailHeight }
            return 0
        }()
        let botPad: CGFloat = bottomPad(for: overlay)
        let fontScale: CGFloat = overlay.canvasWidth > 0
            ? imageAreaSize.width / overlay.canvasWidth
            : 1
        let scaledFontSize = overlay.fontSize * fontScale

        Text(overlay.text.isEmpty ? " " : overlay.text)
            .font(.custom(overlay.resolvedFontName, size: scaledFontSize))
            .foregroundColor(overlay.textColor)
            .padding(.horizontal, 10)
            .padding(.top,    8 + topPad)
            .padding(.bottom, 8 + botPad)
            .background(bgShape(overlay))
            .frame(maxWidth: overlay.normalizedWidth * imageAreaSize.width, alignment: .leading)
            .rotationEffect(Angle(degrees: overlay.rotation))
            .position(
                x: overlay.normalizedPosition.x * imageAreaSize.width,
                y: overlay.normalizedPosition.y * imageAreaSize.height
            )
    }

    private func bottomPad(for overlay: TextOverlay) -> CGFloat {
        if overlay.bgStyle == .speech  && !overlay.tailFlippedV { return SpeechBubbleShape.tailHeight }
        if overlay.bgStyle == .thought && !overlay.tailFlippedV { return ThoughtBubbleShape.tailHeight }
        return 0
    }

    @ViewBuilder
    private func bgShape(_ overlay: TextOverlay) -> some View {
        switch overlay.bgStyle {
        case .none:
            Color.clear
        case .box:
            RoundedRectangle(cornerRadius: 10).fill(overlay.bgColor)
        case .speech:
            SpeechBubbleShape(tailOnLeft: !overlay.tailFlippedH, tailOnBottom: !overlay.tailFlippedV)
                .fill(overlay.bgColor)
        case .thought:
            ThoughtBubbleShape(tailOnLeft: !overlay.tailFlippedH, tailOnBottom: !overlay.tailFlippedV)
                .fill(overlay.bgColor)
        }
    }
}
