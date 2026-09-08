import UIKit

struct PostcardHTMLGenerator {

    // MARK: - Public: URL-based (uploaded to Supabase — lightweight, images fetched by browser)

    static func generate(frontURL: String, backURL: String, frontIsPortrait: Bool,
                         frontInkMessage: String? = nil, backInkMessage: String? = nil) -> String {
        let frontSrc = "\(frontURL)\" alt=\"Card not loaded — please check your connection"
        let backSrc  = "\(backURL)\" alt=\"Card not loaded — please check your connection"
        let frontInkQR = frontInkMessage.flatMap { makeQRBase64(from: $0) }
        let backInkQR  = backInkMessage.flatMap  { makeQRBase64(from: $0) }
        return html(frontSrc: frontSrc, backSrc: backSrc, frontIsPortrait: frontIsPortrait,
                    frontInkQR: frontInkQR, frontInkMsg: frontInkMessage,
                    backInkQR: backInkQR,  backInkMsg: backInkMessage)
    }

    // MARK: - Public: Base64-embedded (local use — clipboard, share sheet, offline)

    static func generate(front: UIImage, back: UIImage, frontIsPortrait: Bool,
                         frontInkMessage: String? = nil, backInkMessage: String? = nil) -> String {
        let frontB64 = downscale(front).jpegData(compressionQuality: 0.88)?.base64EncodedString() ?? ""
        let backB64  = downscale(back).jpegData(compressionQuality: 0.88)?.base64EncodedString() ?? ""
        let frontSrc = "data:image/jpeg;base64,\(frontB64)\" alt=\"Postcard Front"
        let backSrc  = "data:image/jpeg;base64,\(backB64)\" alt=\"Postcard Back"
        let frontInkQR = frontInkMessage.flatMap { makeQRBase64(from: $0) }
        let backInkQR  = backInkMessage.flatMap  { makeQRBase64(from: $0) }
        return html(frontSrc: frontSrc, backSrc: backSrc, frontIsPortrait: frontIsPortrait,
                    frontInkQR: frontInkQR, frontInkMsg: frontInkMessage,
                    backInkQR: backInkQR,  backInkMsg: backInkMessage)
    }

    // MARK: - Private: Shared HTML template

    private static func html(frontSrc: String, backSrc: String, frontIsPortrait: Bool,
                             frontInkQR: String? = nil, frontInkMsg: String? = nil,
                             backInkQR: String?  = nil, backInkMsg: String?  = nil) -> String {
        let cardMaxWidth = frontIsPortrait ? "381px" : "572px"
        let cardVwLimit  = frontIsPortrait ? "61vw"  : "92vw"

        let frontInkHTML: String
        if let qr = frontInkQR, let msg = frontInkMsg {
            frontInkHTML = """
            <div id="front-ink" class="ink-hint" onclick="revealInk('front', '\(jsString(msg))')">
              <img src="data:image/png;base64,\(qr)" class="ink-qr" draggable="false">
              <span id="front-ink-text" class="ink-label">This card has Invisible Ink — tap to read</span>
            </div>
            """
        } else {
            frontInkHTML = ""
        }

        let backInkHTML: String
        if let qr = backInkQR, let msg = backInkMsg {
            backInkHTML = """
            <div id="back-ink" class="ink-hint" style="display:none" onclick="revealInk('back', '\(jsString(msg))')">
              <img src="data:image/png;base64,\(qr)" class="ink-qr" draggable="false">
              <span id="back-ink-text" class="ink-label">This card has Invisible Ink — tap to read</span>
            </div>
            """
        } else {
            backInkHTML = ""
        }

        let hasInk = frontInkHTML.isEmpty && backInkHTML.isEmpty ? "" : """

          function revealInk(side, msg) {
            var el  = document.getElementById(side + '-ink');
            var txt = document.getElementById(side + '-ink-text');
            var isRevealed = el.dataset.revealed === 'true';
            txt.textContent = isRevealed ? 'This card has Invisible Ink — tap to read' : msg;
            el.dataset.revealed = isRevealed ? 'false' : 'true';
            setTimeout(notifyHeight, 50);
          }
        """

        let inkFlipJS = (frontInkQR != nil || backInkQR != nil) ? """

              var frontInkEl = document.getElementById('front-ink');
              var backInkEl  = document.getElementById('back-ink');
              if (frontInkEl) frontInkEl.style.display = isFront ? 'flex' : 'none';
              if (backInkEl)  backInkEl.style.display  = isFront ? 'none' : 'flex';
        """ : ""

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>CardDrop</title>
        <style>
          *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
          body {
            min-height: 100dvh;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            gap: 20px;
            background: transparent;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            padding: 24px;
            -webkit-tap-highlight-color: transparent;
            user-select: none;
          }
          .face {
            border-radius: 4px;
            overflow: hidden;
            box-shadow: 0 8px 32px rgba(0,0,0,0.18), 0 2px 8px rgba(0,0,0,0.10);
            cursor: pointer;
            transition: transform 0.18s ease-in;
          }
          .face img {
            width: 100%;
            height: auto;
            display: block;
          }
          .face.folding   { transform: scaleX(0); transition: transform 0.18s ease-in; }
          .face.unfolding { transform: scaleX(1); transition: transform 0.18s ease-out; }
          .controls {
            display: flex;
            flex-direction: column;
            align-items: center;
            gap: 6px;
            width: 100%;
          }
          .hint { font-size: 11px; color: rgba(255,255,255,0.7); display: block; margin-top: 2px; }
          .flip-btn {
            margin-top: 4px;
            padding: 12px 0;
            width: 100%;
            border-radius: 12px;
            border: none;
            background: #007AFF;
            color: #fff;
            font-size: 15px;
            font-weight: 600;
            font-family: inherit;
            cursor: pointer;
            transition: opacity 0.15s;
          }
          .flip-btn:active { opacity: 0.8; }
          .ink-hint {
            display: flex;
            align-items: center;
            gap: 10px;
            width: 100%;
            padding: 10px 12px;
            border-radius: 12px;
            background: #1a1a1a;
            cursor: pointer;
          }
          .ink-qr {
            width: 40px;
            height: 40px;
            border-radius: 4px;
            flex-shrink: 0;
            image-rendering: pixelated;
          }
          .ink-label { font-size: 13px; color: #e0e0e0; }
        </style>
        </head>
        <body>

        <div id="front" class="face" onclick="flip()" style="width:min(\(cardVwLimit),\(cardMaxWidth));">
          <img src="\(frontSrc)" draggable="false">
        </div>
        <div id="back" class="face" onclick="flip()" style="display:none;width:min(\(cardVwLimit),\(cardMaxWidth));">
          <img src="\(backSrc)" draggable="false">
        </div>

        <div class="controls">
          <button class="flip-btn" id="flip-btn" onclick="flip()"><span id="flip-label">Flip to Back</span><span class="hint">or tap the card</span></button>
        \(frontInkHTML)\(backInkHTML)</div>

        <script>
          var isFront = true;
          var flipLabel = document.getElementById('flip-label');

          function notifyHeight() {
            window.parent.postMessage({ type: 'cd-resize', height: document.body.scrollHeight }, '*');
          }

          window.addEventListener('load', notifyHeight);
        \(hasInk)
          function flip() {
            var current = document.getElementById(isFront ? 'front' : 'back');
            var next    = document.getElementById(isFront ? 'back'  : 'front');

            current.classList.add('folding');
            current.style.transition = 'transform 0.18s ease-in';
            current.style.transform  = 'scaleX(0)';

            setTimeout(function() {
              current.style.display = 'none';
              current.classList.remove('folding');
              current.style.transform = '';

              next.style.display    = 'block';
              next.style.transform  = 'scaleX(0)';
              next.style.transition = 'none';
              next.getBoundingClientRect();
              next.style.transition = 'transform 0.18s ease-out';
              next.style.transform  = 'scaleX(1)';

              isFront = !isFront;
              flipLabel.textContent = isFront ? 'Flip to Back' : 'Flip to Front';
        \(inkFlipJS)
              setTimeout(notifyHeight, 200);
            }, 190);
          }
        </script>
        </body>
        </html>
        """
    }

    // MARK: - Private: QR code generator

    private static func makeQRBase64(from string: String) -> String? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg).pngData()?.base64EncodedString()
    }

    private static func jsString(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "'",  with: "\\'")
         .replacingOccurrences(of: "\n", with: "\\n")
         .replacingOccurrences(of: "\r", with: "\\r")
    }

    // MARK: - Private: Downscale for base64 embedding

    static func scaledForMMS(_ image: UIImage) -> UIImage { downscale(image, maxDimension: 900) }

    // Deliberately much smaller than scaledForMMS — this is just a small
    // in-thread thumbnail; most recipients will see the full-size image via
    // the URL's own rich link preview instead.
    static func scaledForThumbnail(_ image: UIImage) -> UIImage { downscale(image, maxDimension: 300) }

    // Composites the front and 4x6 back thumbnails into one "fanned photo
    // stack" image — back peeking out lower-right, front on top, each
    // tilted the opposite way. Used as the MMS thumbnail attachment instead
    // of the front alone. The 4x6 back (not 6x9) is used deliberately here —
    // it shares the front's exact physical aspect ratio/scale, whereas the
    // 6x9 back is a genuinely larger card and would look mismatched stacked
    // against the front at the same downscale size.
    //
    // UIGraphicsImageRenderer's context behaves like a normal UIKit/SwiftUI
    // Y-DOWN coordinate space (unlike a raw CGContext, which is Y-up and
    // needs manual flipping — see PostcardBackCanvas's Core Text drawing),
    // so a POSITIVE angle in CGContext.rotate(by:) here is CLOCKWISE, same
    // as SwiftUI's .rotationEffect(.degrees(positive)). Counterclockwise is
    // therefore a negative angle.
    static func stackedThumbnail(front: UIImage, back: UIImage) -> UIImage {
        // 600px — sharp enough to look good in Messages' full-screen
        // image viewer (tapping the attachment itself), nowhere near
        // print-worthy resolution. The inline bubble size in the thread
        // is controlled by Messages' own layout, not by this.
        let frontSmall = downscale(front, maxDimension: 600)
        let backSmall  = downscale(back,  maxDimension: 600)

        let frontAngle: CGFloat = -10 * .pi / 180  // counterclockwise
        let backAngle:  CGFloat =   5 * .pi / 180  // clockwise

        func rotatedBounds(_ size: CGSize, angle: CGFloat) -> CGSize {
            CGSize(
                width:  abs(size.width * cos(angle)) + abs(size.height * sin(angle)),
                height: abs(size.width * sin(angle)) + abs(size.height * cos(angle))
            )
        }

        let frontBounds = rotatedBounds(frontSmall.size, angle: frontAngle)
        let backBounds  = rotatedBounds(backSmall.size,  angle: backAngle)

        // Back sits offset down-and-right of front, so it peeks out from
        // behind once front is drawn on top of it.
        let offset = CGSize(
            width:  min(frontSmall.size.width,  backSmall.size.width)  * 0.22,
            height: min(frontSmall.size.height, backSmall.size.height) * 0.22
        )
        let frontCenter = CGPoint.zero
        let backCenter  = CGPoint(x: offset.width, y: offset.height)

        let minX = min(frontCenter.x - frontBounds.width  / 2, backCenter.x - backBounds.width  / 2)
        let maxX = max(frontCenter.x + frontBounds.width  / 2, backCenter.x + backBounds.width  / 2)
        let minY = min(frontCenter.y - frontBounds.height / 2, backCenter.y - backBounds.height / 2)
        let maxY = max(frontCenter.y + frontBounds.height / 2, backCenter.y + backBounds.height / 2)

        let padding: CGFloat = 8
        let canvasSize = CGSize(width: (maxX - minX) + padding * 2, height: (maxY - minY) + padding * 2)
        let shift = CGPoint(x: -minX + padding, y: -minY + padding)

        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { ctx in
            func draw(_ image: UIImage, center: CGPoint, angle: CGFloat) {
                let cg = ctx.cgContext
                cg.saveGState()
                cg.translateBy(x: center.x + shift.x, y: center.y + shift.y)
                cg.rotate(by: angle)
                image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2,
                                       width: image.size.width, height: image.size.height))
                cg.restoreGState()
            }
            draw(backSmall, center: backCenter, angle: backAngle)
            draw(frontSmall, center: frontCenter, angle: frontAngle)
        }
    }

    private static func downscale(_ image: UIImage, maxDimension: CGFloat = 1200) -> UIImage {
        let size = image.size
        let long = max(size.width, size.height)
        guard long > maxDimension else { return image }
        let scale = maxDimension / long
        let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
