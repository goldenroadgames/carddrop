import SwiftUI

// MARK: - Burst Color Palette  (matches captions.py COLORS dict)

extension Color {
    static let burstRed    = Color(red: 1.0,        green: 0.0,       blue: 0.0)
    static let burstYellow = Color(red: 1.0,        green: 0.843,     blue: 0.0)
    static let burstBlue   = Color(red: 0.0,        green: 0.278,     blue: 0.671)
    static let burstGreen  = Color(red: 0.133,      green: 0.545,     blue: 0.133)
    static let burstBorderCream = Color(red: 240/255, green: 234/255, blue: 216/255)
}

// MARK: - SVG Path Data  (d= attributes extracted from Assets/bursts/)

private enum BurstPathData {
    // poly.svg — viewBox 0 0 6520 6250
    static let poly = "M605 5828 c-3 -7 94 -306 215 -663 121 -358 218 -655 216 -661 -2 -5 -169 -127 -370 -269 -201 -142 -366 -264 -366 -270 0 -6 153 -121 340 -255 299 -213 339 -244 323 -255 -10 -6 -114 -67 -230 -135 -117 -68 -213 -129 -213 -136 0 -7 101 -66 225 -131 124 -65 225 -121 225 -126 0 -4 -167 -230 -372 -502 -254 -339 -368 -499 -361 -506 7 -7 265 -7 818 1 444 6 810 8 814 5 3 -4 60 -162 127 -352 66 -191 127 -351 135 -356 11 -7 125 46 417 192 221 111 407 201 413 201 6 0 570 -330 1252 -732 1246 -735 1300 -764 1322 -727 5 8 -152 334 -416 860 -233 466 -421 850 -419 853 3 2 334 -58 735 -135 402 -76 736 -137 743 -134 6 2 12 8 12 12 0 10 -741 696 -1030 953 -113 100 -208 185 -212 189 -4 4 118 125 272 271 154 145 280 269 280 275 0 10 -242 240 -388 371 l-46 41 413 852 c301 619 411 855 403 863 -8 8 -275 -105 -979 -412 -532 -233 -976 -425 -985 -427 -10 -3 -222 108 -507 267 -269 150 -495 270 -500 269 -6 -2 -71 -86 -146 -187 -74 -101 -139 -181 -143 -179 -116 65 -1982 1078 -1994 1082 -11 4 -20 2 -23 -7z"

    // blob.svg — viewBox 0 0 210 297
    static let blob = "m 88.985274,184.717 c -1.131622,2.6e-4 -2.252133,-0.35269 -3.154627,-0.99351 -1.430866,-1.01626 -2.30505,-2.73738 -2.281237,-4.4921 0.01429,-1.04986 0.325702,-1.95818 0.600869,-2.7596 0.06747,-0.19685 0.135202,-0.39317 0.19685,-0.59029 0.61595,-1.97511 0.63791,-5.07841 -0.315648,-6.37487 -0.279136,-0.37967 -0.600869,-0.53445 -1.110192,-0.53445 -0.132027,0 -0.275431,0.0114 -0.426244,0.0336 0,0 -1.190095,0.17647 -5.932222,0.87894 -0.289455,0.0429 -0.582348,0.0646 -0.86995,0.0646 -2.124605,2.7e-4 -4.059767,-1.18692 -5.050102,-3.098 -0.999332,-1.92829 -0.846138,-4.14179 0.409575,-5.92138 l 3.088216,-4.37594 c 0.500063,-0.70856 0.442913,-1.72879 -0.132292,-2.37411 -0.126206,-0.14129 -0.308768,-0.23283 -0.677333,-0.40957 -0.262731,-0.12648 -0.560652,-0.26961 -0.883973,-0.4699 -0.344752,-0.21405 -0.636852,-0.43101 -0.894556,-0.62283 -0.500592,-0.37227 -0.757237,-0.55431 -1.115748,-0.62151 -0.242094,-0.0452 -0.534723,-0.0661 -0.921544,-0.0661 -0.257175,0 -0.515937,0.008 -0.773906,0.0167 -0.296333,0.009 -0.591608,0.0185 -0.882914,0.0185 -1.077648,0 -2.47068,-0.11853 -3.686175,-1.04404 -1.189567,-0.90593 -1.914261,-2.42544 -1.988609,-4.16851 -0.08625,-2.02697 0.699559,-3.96108 2.102379,-5.17393 1.202796,-1.03981 2.804319,-1.56713 4.760384,-1.56713 0.364596,0 0.744008,0.019 1.127654,0.0566 0.155046,0.0154 0.313267,0.0323 0.473075,0.0495 0.471752,0.0508 0.959908,0.10345 1.379008,0.10345 0.335492,0 0.766763,-0.0341 0.917575,-0.19552 0.347133,-0.37227 0.191823,-0.97314 -1.628775,-2.94243 -0.116946,-0.12674 -0.228864,-0.24792 -0.332846,-0.36275 -1.540139,-1.70127 -1.92061,-4.05659 -0.993245,-6.14706 0.92022,-2.07407 2.957777,-3.41419 5.191389,-3.41419 0.297921,0 0.601398,0.0233 0.902229,0.0691 5.678752,0.86492 6.739467,1.02632 6.739467,1.02632 0.143404,0.022 0.280723,0.0331 0.408252,0.0331 0.542131,0 0.922337,-0.19367 1.233487,-0.62812 0.647436,-0.90434 0.805657,-2.63657 0.360627,-3.94335 -0.105833,-0.31062 -0.225689,-0.626 -0.352425,-0.95991 -0.421216,-1.10834 -0.898525,-2.36484 -0.948531,-3.77666 -0.104775,-2.9419 1.798638,-5.68986 4.525698,-6.53362 0.546629,-0.16933 1.121833,-0.25506 1.709473,-0.25506 2.464858,0 4.777846,1.51792 5.624248,3.69173 0.536839,1.37795 0.469371,2.7477 0.409839,3.95605 -0.0164,0.33232 -0.03201,0.64611 -0.0344,0.94642 -0.01164,1.42054 0.534193,3.95552 1.589881,5.0202 0.334169,0.33682 0.586581,0.38021 0.769144,0.38021 0.09975,0 0.210608,-0.0148 0.329406,-0.0434 l 0.07726,-0.0193 c 2.860415,-0.73184 5.067565,-3.03662 5.771095,-6.01742 l 0.88768,-3.76211 c 0.23442,-0.99351 0.74427,-1.87933 1.47505,-2.56116 0.028,-0.0267 0.0643,-0.0598 0.10081,-0.0926 1.31709,-1.1811 3.0099,-1.83065 4.76858,-1.83065 3.31205,0 6.25501,2.22541 7.15671,5.41205 0.79799,2.81887 1.02024,3.60468 1.02024,3.60468 0.39026,1.37875 1.37768,2.55006 2.64107,3.13267 0.38656,0.17833 0.83873,0.27226 1.30757,0.27226 1.46711,0 2.82046,-0.87101 3.14775,-2.02618 0.40984,-1.44621 1.14564,-2.67732 2.12778,-3.5605 1.05304,-0.94694 2.42279,-1.4904 3.75761,-1.4904 0.2122,0 0.42518,0.0138 0.63368,0.0402 2.43787,0.31274 4.436,2.46618 4.75138,5.12074 0.23204,1.9558 -0.41698,4.0902 -1.82747,6.01081 -0.7501,1.02103 -0.72919,1.11469 -0.61384,1.63248 0.2466,1.10622 0.46779,1.52426 0.98611,1.86452 0.4318,0.2831 0.99589,0.43921 1.58882,0.43921 0.17833,0 0.35851,-0.014 0.53499,-0.0415 0.36195,-0.0569 0.76702,-0.17331 1.19618,-0.29713 0.77496,-0.22331 1.65364,-0.47625 2.62678,-0.47625 0.27305,0 0.54372,0.0204 0.8046,0.0606 2.40956,0.37041 4.34208,2.63975 4.39923,5.16546 0.0511,2.23626 -1.32424,4.45505 -3.42213,5.52106 -0.64955,0.32993 -1.24962,0.56409 -1.77932,0.77073 -1.14009,0.44503 -1.76821,0.68977 -2.37807,1.5494 -1.05013,1.48034 -1.50707,2.94799 -1.08665,3.48985 0.32174,0.41487 0.67099,0.78793 1.04087,1.18296 1.18878,1.26947 2.53604,2.70801 2.63155,5.36786 0.0669,1.86188 -0.57415,3.76899 -1.75948,5.23161 -0.20346,0.25135 -0.42439,0.49107 -0.65696,0.71332 -0.45985,0.43947 -0.94853,0.80724 -1.42134,1.16257 -0.76888,0.57838 -1.4949,1.12422 -1.57771,1.62243 -0.0773,0.46355 0.43603,1.22476 1.3073,1.93913 0.20082,0.16457 0.40799,0.3257 0.61569,0.48763 1.08188,0.84323 2.30822,1.79864 2.98873,3.33057 0.68474,1.54173 0.64956,3.44567 -0.0968,5.2242 -0.889,2.11746 -2.57546,3.55653 -4.51141,3.85022 -0.24501,0.0373 -0.49557,0.0561 -0.74507,0.0561 -1.59412,0 -3.26549,-0.78687 -4.5855,-2.15821 -0.74453,-0.77417 -1.30386,-1.6121 -1.84493,-2.42199 -0.25903,-0.38788 -0.50324,-0.75433 -0.75883,-1.09882 -1.66,-2.24234 -4.581,-4.62491 -6.72412,-4.62491 -0.14764,0 -0.29131,0.0119 -0.42677,0.0354 -0.85858,0.14949 -1.96797,0.61278 -2.58075,1.07765 -0.33549,0.25453 -0.54478,1.3417 -0.66992,1.99125 -0.0323,0.16669 -0.0635,0.32888 -0.0955,0.48393 -0.4146,1.99733 -0.93107,4.48336 -3.6875,6.0825 -0.99218,0.576 -2.10793,0.88027 -3.22633,0.88027 -0.78105,0 -1.52691,-0.14896 -2.21694,-0.44265 -1.50336,-0.64029 -2.45824,-1.80869 -3.30041,-2.83951 -0.24421,-0.29898 -0.47493,-0.58129 -0.70617,-0.83529 -0.80513,-0.8845 -1.81081,-1.60469 -2.90778,-2.08332 -0.2958,-0.12886 -0.62177,-0.19156 -0.99615,-0.19156 -2.08915,0 -4.933161,1.97643 -6.370113,3.80735 -0.678656,0.86545 -0.843227,1.38298 -0.861748,1.66476 -0.01164,0.17939 -0.01164,0.36803 -0.01191,0.56753 -2.65e-4,0.66675 -7.94e-4,1.49622 -0.423069,2.47941 -0.786342,1.82933 -2.099469,3.15754 -3.697817,3.74015 -0.5842,0.21299 -1.202796,0.32094 -1.837796,0.32094 z"
}

// MARK: - SVG Path Cache  (lazy static lets — parsed once, reused)

enum BurstShapeCache {
    static let poly: CGPath? = SVGPathParser.parse(BurstPathData.poly)
    static let blob: CGPath? = SVGPathParser.parse(BurstPathData.blob)

    static func cgPath(for name: String) -> CGPath? {
        switch name {
        case "poly": return poly
        case "blob": return blob
        default:     return poly
        }
    }
}

// MARK: - SVG Path Parser  (subset: M m L l H h V v C c Z z)

struct SVGPathParser {
    static func parse(_ d: String) -> CGPath? {
        let tokens = tokenize(d)
        guard !tokens.isEmpty else { return nil }

        let mPath = CGMutablePath()
        var i = 0
        var cx: CGFloat = 0, cy: CGFloat = 0
        var sx: CGFloat = 0, sy: CGFloat = 0

        func num() -> CGFloat {
            guard i < tokens.count else { return 0 }
            let v = CGFloat(Double(tokens[i]) ?? 0); i += 1; return v
        }
        func hasNum() -> Bool { i < tokens.count && Double(tokens[i]) != nil }

        while i < tokens.count {
            let cmd = tokens[i]; i += 1
            switch cmd {
            case "M":
                let x = num(), y = num()
                mPath.move(to: .init(x: x, y: y)); cx = x; cy = y; sx = x; sy = y
                while hasNum() { let lx = num(), ly = num(); mPath.addLine(to: .init(x: lx, y: ly)); cx = lx; cy = ly }
            case "m":
                let x = cx + num(), y = cy + num()
                mPath.move(to: .init(x: x, y: y)); cx = x; cy = y; sx = x; sy = y
                while hasNum() { let dx = num(), dy = num(); mPath.addLine(to: .init(x: cx+dx, y: cy+dy)); cx += dx; cy += dy }
            case "L":
                while hasNum() { let x = num(), y = num(); mPath.addLine(to: .init(x: x, y: y)); cx = x; cy = y }
            case "l":
                while hasNum() { let dx = num(), dy = num(); mPath.addLine(to: .init(x: cx+dx, y: cy+dy)); cx += dx; cy += dy }
            case "H":
                while hasNum() { let x = num(); mPath.addLine(to: .init(x: x, y: cy)); cx = x }
            case "h":
                while hasNum() { let dx = num(); mPath.addLine(to: .init(x: cx+dx, y: cy)); cx += dx }
            case "V":
                while hasNum() { let y = num(); mPath.addLine(to: .init(x: cx, y: y)); cy = y }
            case "v":
                while hasNum() { let dy = num(); mPath.addLine(to: .init(x: cx, y: cy+dy)); cy += dy }
            case "C":
                while hasNum() {
                    let x1=num(),y1=num(),x2=num(),y2=num(),x=num(),y=num()
                    mPath.addCurve(to: .init(x:x,y:y), control1: .init(x:x1,y:y1), control2: .init(x:x2,y:y2))
                    cx=x; cy=y
                }
            case "c":
                while hasNum() {
                    let dx1=num(),dy1=num(),dx2=num(),dy2=num(),dx=num(),dy=num()
                    mPath.addCurve(to: .init(x:cx+dx, y:cy+dy),
                                   control1: .init(x:cx+dx1, y:cy+dy1),
                                   control2: .init(x:cx+dx2, y:cy+dy2))
                    cx+=dx; cy+=dy
                }
            case "Z", "z":
                mPath.closeSubpath(); cx=sx; cy=sy
            default:
                break
            }
        }
        return mPath.isEmpty ? nil : mPath
    }

    private static func tokenize(_ d: String) -> [String] {
        var tokens: [String] = []
        var i = d.startIndex
        while i < d.endIndex {
            let c = d[i]
            if c.isWhitespace || c == "," { i = d.index(after: i); continue }
            if c.isLetter && c != "e" && c != "E" {
                tokens.append(String(c)); i = d.index(after: i); continue
            }
            if c.isNumber || c == "." || c == "-" {
                var num = ""
                if c == "-" { num = "-"; i = d.index(after: i) }
                outer: while i < d.endIndex {
                    let n = d[i]
                    if n.isNumber || n == "." {
                        num.append(n); i = d.index(after: i)
                    } else if (n == "e" || n == "E"), !num.isEmpty, num != "-" {
                        num.append(n); i = d.index(after: i)
                        if i < d.endIndex, d[i] == "+" || d[i] == "-" {
                            num.append(d[i]); i = d.index(after: i)
                        }
                        while i < d.endIndex && d[i].isNumber { num.append(d[i]); i = d.index(after: i) }
                        break outer
                    } else { break outer }
                }
                if !num.isEmpty, num != "-" { tokens.append(num) }
                continue
            }
            i = d.index(after: i)
        }
        return tokens
    }
}

// MARK: - BurstShape  (SwiftUI Shape — scales SVG path to fill its frame)

struct BurstShape: Shape {
    let shapeName: String

    func path(in rect: CGRect) -> Path {
        guard let cgPath = BurstShapeCache.cgPath(for: shapeName) else { return Path() }
        let bounds = cgPath.boundingBoxOfPath
        guard bounds.width > 0, bounds.height > 0 else { return Path(cgPath) }
        let sx = rect.width  / bounds.width
        let sy = rect.height / bounds.height
        var t  = CGAffineTransform(a: sx, b: 0, c: 0, d: sy,
                                   tx: rect.minX - bounds.minX * sx,
                                   ty: rect.minY - bounds.minY * sy)
        return Path(cgPath.copy(using: &t) ?? cgPath)
    }
}

// MARK: - Burst Preset  (16 curated style combinations)

struct BurstPreset: Identifiable {
    let id: String
    let outerShapeName: String
    let innerShapeName: String
    let fontName: String        // PostScript font name (Bangers-Regular / Creepster-Regular)
    let color1: Color           // outer fill
    let color2: Color           // inner fill
    let color3: Color           // text fill

    static let all: [BurstPreset] = {
        let r=Color.burstRed, y=Color.burstYellow, b=Color.burstBlue, g=Color.burstGreen
        let C="Creepster-Regular", B="Bangers-Regular"
        return [
            // poly-blob-bangers
            BurstPreset(id:"poly-blob-bangers-ryb", outerShapeName:"poly",innerShapeName:"blob",fontName:B,color1:r,color2:y,color3:b),
            BurstPreset(id:"poly-blob-bangers-rby", outerShapeName:"poly",innerShapeName:"blob",fontName:B,color1:r,color2:b,color3:y),
            BurstPreset(id:"poly-blob-bangers-ygr", outerShapeName:"poly",innerShapeName:"blob",fontName:B,color1:y,color2:g,color3:r),
            BurstPreset(id:"poly-blob-bangers-bry", outerShapeName:"poly",innerShapeName:"blob",fontName:B,color1:b,color2:r,color3:y),
            BurstPreset(id:"poly-blob-bangers-byr", outerShapeName:"poly",innerShapeName:"blob",fontName:B,color1:b,color2:y,color3:r),
            BurstPreset(id:"poly-blob-bangers-byg", outerShapeName:"poly",innerShapeName:"blob",fontName:B,color1:b,color2:y,color3:g),
            BurstPreset(id:"poly-blob-bangers-ryr", outerShapeName:"poly",innerShapeName:"blob",fontName:B,color1:r,color2:y,color3:r),
            BurstPreset(id:"poly-blob-bangers-yry", outerShapeName:"poly",innerShapeName:"blob",fontName:B,color1:y,color2:r,color3:y),
            BurstPreset(id:"poly-blob-bangers-ygy", outerShapeName:"poly",innerShapeName:"blob",fontName:B,color1:y,color2:g,color3:y),
            BurstPreset(id:"poly-blob-bangers-gyr", outerShapeName:"poly",innerShapeName:"blob",fontName:B,color1:g,color2:y,color3:r),
            BurstPreset(id:"poly-blob-bangers-gyg", outerShapeName:"poly",innerShapeName:"blob",fontName:B,color1:g,color2:y,color3:g),
            BurstPreset(id:"poly-blob-bangers-byb", outerShapeName:"poly",innerShapeName:"blob",fontName:B,color1:b,color2:y,color3:b),
            BurstPreset(id:"poly-blob-bangers-yby", outerShapeName:"poly",innerShapeName:"blob",fontName:B,color1:y,color2:b,color3:y),
            // blob-blob-creepster
            BurstPreset(id:"blob-blob-creepster-ryb", outerShapeName:"blob",innerShapeName:"blob",fontName:C,color1:r,color2:y,color3:b),
            BurstPreset(id:"blob-blob-creepster-ryg", outerShapeName:"blob",innerShapeName:"blob",fontName:C,color1:r,color2:y,color3:g),
            BurstPreset(id:"blob-blob-creepster-gyg", outerShapeName:"blob",innerShapeName:"blob",fontName:C,color1:g,color2:y,color3:g),
            BurstPreset(id:"blob-blob-creepster-ygy", outerShapeName:"blob",innerShapeName:"blob",fontName:C,color1:y,color2:g,color3:y),
            BurstPreset(id:"blob-blob-creepster-ryr", outerShapeName:"blob",innerShapeName:"blob",fontName:C,color1:r,color2:y,color3:r),
            BurstPreset(id:"blob-blob-creepster-yry", outerShapeName:"blob",innerShapeName:"blob",fontName:C,color1:y,color2:r,color3:y),
            BurstPreset(id:"blob-blob-creepster-gyr", outerShapeName:"blob",innerShapeName:"blob",fontName:C,color1:g,color2:y,color3:r),
            BurstPreset(id:"blob-blob-creepster-byr", outerShapeName:"blob",innerShapeName:"blob",fontName:C,color1:b,color2:y,color3:r),
        ]
    }()

    static func find(_ id: String) -> BurstPreset {
        all.first { $0.id == id } ?? all[0]
    }
}

// MARK: - Burst Caption Overlay Model

struct BurstCaptionOverlay: Identifiable {
    var id: UUID = UUID()
    var text: String = ""
    var presetID: String
    var normalizedPosition: CGPoint = CGPoint(x: 0.5, y: 0.5)
    var normalizedHeight: CGFloat = 1.0 / 6.0  // 1" on a 6" card
    var canvasHeight: CGFloat = 0               // canvas height when overlay was created
    var rotation: Double = 0                    // user-adjustable overlay rotation

    init(presetID: String = BurstPreset.all[0].id, canvasHeight: CGFloat = 0) {
        self.presetID    = presetID
        self.canvasHeight = canvasHeight
    }
}

// MARK: - Burst Geometry  (mirrors captions.py layout constants)

struct BurstGeometry {
    // captions.py constants (normalised to fontHeight)
    private static let inlayRatio:    CGFloat = 1.5        // INLAY_TO_TEXT_RATIO
    private static let paddingFactor: CGFloat = 0.4
    static  let outerToFontRatio: CGFloat = inlayRatio + 2 * paddingFactor  // ≈ 1.967

    let fontHeight:   CGFloat
    let textWidth:    CGFloat
    let textHeight:   CGFloat   // total height of all lines
    let inlayWidth:   CGFloat
    let inlayHeight:  CGFloat
    let outerWidth:   CGFloat
    let outerHeight:  CGFloat
    let borderPad:    CGFloat   // cream ring around outer shape

    init(text: String, fontName: String, targetBurstHeight h: CGFloat) {
        let fh      = max(8, h / Self.outerToFontRatio)
        let lines   = (text.isEmpty ? " " : text).components(separatedBy: "\n")
        let lineCount = CGFloat(max(1, lines.count))
        let tw      = lines.map { Self.measureText($0.isEmpty ? " " : $0, fontName: fontName, size: fh) }.max() ?? fh
        let lineH   = UIFont(name: fontName, size: fh)?.lineHeight ?? fh * 1.2
        let th      = lineH * lineCount + fh * 0.5  // real line height + 0.25fh top/bottom padding
        fontHeight  = fh
        textWidth   = tw
        textHeight  = th
        inlayWidth  = max(tw + fh * 0.15, fh * 0.5) * Self.inlayRatio
        inlayHeight = max(fh, th) * Self.inlayRatio
        let pad     = fh * Self.paddingFactor
        outerWidth  = inlayWidth  + pad * 2
        outerHeight = inlayHeight + pad * 2
        borderPad   = max(1, h * 0.01)
    }

    static func measureText(_ text: String, fontName: String, size: CGFloat) -> CGFloat {
        if let f = UIFont(name: fontName, size: size) {
            return (text as NSString).size(withAttributes: [.font: f]).width
        }
        return size * CGFloat(text.count) * 0.6   // rough fallback
    }
}
