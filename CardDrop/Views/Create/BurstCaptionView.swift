import SwiftUI

// MARK: - Stroked Text  (8-directional offset simulates stroke)

private struct StrokedTextView: View {
    let text: String
    let fontName: String
    let fontSize: CGFloat
    let fillColor: Color
    var strokeWidth: CGFloat = 2

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { idx in
                Text(text)
                    .font(.custom(fontName, size: fontSize))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.black)
                    .offset(x: offsets[idx].0, y: offsets[idx].1)
            }
            Text(text)
                .font(.custom(fontName, size: fontSize))
                .multilineTextAlignment(.center)
                .foregroundColor(fillColor)
        }
    }

    private var offsets: [(CGFloat, CGFloat)] {
        let s = strokeWidth, d = s * 0.7
        return [(-s,0),(s,0),(0,-s),(0,s),(-d,-d),(d,-d),(-d,d),(d,d)]
    }
}

// MARK: - CardDrop logo placeholder  (Card normal, Drop subscripted ½ font height)

private struct CardDropLogoText: View {
    let fontName: String
    let fontSize: CGFloat
    let fillColor: Color
    let strokeWidth: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            StrokedTextView(text: "Card", fontName: fontName, fontSize: fontSize,
                            fillColor: fillColor, strokeWidth: strokeWidth)
            StrokedTextView(text: "Drop", fontName: fontName, fontSize: fontSize,
                            fillColor: fillColor, strokeWidth: strokeWidth)
                .offset(y: fontSize * 0.5)
        }
        .fixedSize()
    }
}

// MARK: - Burst Caption View  (static — used in both editing canvas and PostcardFrontCanvas)

struct BurstCaptionView: View {
    let text: String
    let preset: BurstPreset
    let burstHeight: CGFloat    // absolute height in points

    var body: some View {
        // Geometry: use "CardDrop" (single line) when empty so burst width matches logo width
        let g = BurstGeometry(text: text.isEmpty ? "CardDrop" : text,
                              fontName: preset.fontName,
                              targetBurstHeight: burstHeight)

        ZStack {
            // Outer burst fill
            BurstShape(shapeName: preset.outerShapeName)
                .fill(preset.color1)
                .frame(width: g.outerWidth, height: g.outerHeight)

            // Inner burst fill + stroke
            ZStack {
                BurstShape(shapeName: preset.innerShapeName)
                    .fill(preset.color2)
                BurstShape(shapeName: preset.innerShapeName)
                    .stroke(Color.black, lineWidth: max(0.75, g.fontHeight * 0.04))
            }
            .frame(width: g.inlayWidth, height: g.inlayHeight)

            // Text — stroked, slightly tilted
            if text.isEmpty {
                CardDropLogoText(fontName: preset.fontName, fontSize: g.fontHeight,
                                 fillColor: preset.color3,
                                 strokeWidth: max(1, g.fontHeight * 0.06))
                    .rotationEffect(.degrees(-7.5))
            } else {
                StrokedTextView(text: text, fontName: preset.fontName, fontSize: g.fontHeight,
                                fillColor: preset.color3,
                                strokeWidth: max(1, g.fontHeight * 0.06))
                    .frame(width: g.textWidth + g.fontHeight * 0.15, height: g.textHeight)
                    .rotationEffect(.degrees(-7.5))
            }
        }
        .frame(width: g.outerWidth, height: g.outerHeight)
        .compositingGroup()
        // Cream border — 8 hard-edge shadows on the flattened composite silhouette
        .shadow(color: Color.burstBorderCream, radius: 0, x:  g.borderPad, y:  0)
        .shadow(color: Color.burstBorderCream, radius: 0, x: -g.borderPad, y:  0)
        .shadow(color: Color.burstBorderCream, radius: 0, x:  0,           y:  g.borderPad)
        .shadow(color: Color.burstBorderCream, radius: 0, x:  0,           y: -g.borderPad)
        .shadow(color: Color.burstBorderCream, radius: 0, x:  g.borderPad, y:  g.borderPad)
        .shadow(color: Color.burstBorderCream, radius: 0, x: -g.borderPad, y:  g.borderPad)
        .shadow(color: Color.burstBorderCream, radius: 0, x:  g.borderPad, y: -g.borderPad)
        .shadow(color: Color.burstBorderCream, radius: 0, x: -g.borderPad, y: -g.borderPad)
        .compositingGroup()
        // Drop shadow outside the cream border
        .shadow(color: .black.opacity(0.45), radius: 2, x: 1.5, y: 2)
    }
}

// MARK: - Interactive Item View  (drag / resize / rotate handles)

struct BurstCaptionItemView: View {
    @Binding var overlay: BurstCaptionOverlay
    let canvasSize: CGSize
    let isSelected: Bool
    let onSelect: () -> Void

    @GestureState private var dragOffset: CGSize = .zero
    @State private var resizeDragBaseH: CGFloat = 0
    @State private var rotationDragBase: Double? = nil

    private var preset: BurstPreset { BurstPreset.find(overlay.presetID) }
    private var burstHeight: CGFloat { max(30, overlay.normalizedHeight * canvasSize.height) }

    var body: some View {
        BurstCaptionView(text: overlay.text, preset: preset, burstHeight: burstHeight)
            // Selection ring
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? Color.white : Color.clear, lineWidth: 1.5)
                    .padding(-4)
            )
            // Resize handle — bottom-trailing (controls height)
            .overlay(alignment: .bottomTrailing) {
                if isSelected {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 20, height: 20)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .offset(x: 8, y: 8)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if resizeDragBaseH == 0 { resizeDragBaseH = overlay.normalizedHeight }
                                    let newH = resizeDragBaseH + value.translation.width / canvasSize.width
                                    overlay.normalizedHeight = max(0.05, min(0.55, newH))
                                }
                                .onEnded { _ in resizeDragBaseH = 0 }
                        )
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
                    .updating($dragOffset) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
                        let nx = overlay.normalizedPosition.x + value.translation.width  / canvasSize.width
                        let ny = overlay.normalizedPosition.y + value.translation.height / canvasSize.height
                        overlay.normalizedPosition = CGPoint(x: max(0, min(1, nx)), y: max(0, min(1, ny)))
                    }
            )
            .onTapGesture { onSelect() }
    }
}

// MARK: - Style Chip  (thumbnail in the picker)

struct BurstStyleChip: View {
    let preset: BurstPreset
    let isSelected: Bool

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            BurstCaptionView(text: "", preset: preset, burstHeight: 32)
                .scaleEffect(0.78)
        }
        .frame(width: 86, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.25),
                        lineWidth: isSelected ? 2.5 : 1)
        )
    }
}

// MARK: - Edit Panel

struct BurstCaptionEditPanel: View {
    @Binding var overlay: BurstCaptionOverlay
    var onDelete: () -> Void
    var onDone: () -> Void

    @FocusState private var textFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {

            // Left: text input + Done/Delete
            HStack(alignment: .top, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if overlay.text.isEmpty {
                        Text("Caption text…")
                            .foregroundColor(Color(.placeholderText))
                            .padding(.horizontal, 5)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $overlay.text)
                        .frame(minHeight: 44, maxHeight: 66)
                        .scrollContentBackground(.hidden)
                        .focused($textFocused)
                        .onKeyPress(.tab) { .handled }
                }
                .padding(4)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)

                VStack(spacing: 4) {
                    Button("Done", action: onDone)
                        .font(.subheadline.weight(.medium))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // Right: style chips
            VStack(alignment: .leading, spacing: 6) {
                Text("Style").font(.caption).foregroundColor(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(BurstPreset.all) { preset in
                            BurstStyleChip(preset: preset, isSelected: preset.id == overlay.presetID)
                                .onTapGesture { overlay.presetID = preset.id }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }
}
