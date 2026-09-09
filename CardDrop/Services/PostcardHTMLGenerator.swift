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
