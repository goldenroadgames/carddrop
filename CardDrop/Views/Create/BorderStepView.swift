import SwiftUI

struct BorderStepView: View {
    @ObservedObject var draft: PostcardDraft
    let filteredImage: UIImage?
    var onNext: () -> Void

    // Saved custom-text state so switching Decorative → Custom Text doesn't clobber it
    @State private var savedCustomText: String = ""
    @State private var savedCustomFont: String = "Georgia"
    @State private var savedCustomColor: Color = .black

    // Transfer alert
    @State private var showTransferAlert = false

    // Preview text/color for the canvas (placeholder when empty in customText mode)
    private var previewText: String {
        if draft.border == .decorative { return draft.borderText }
        return draft.borderText.isEmpty ? "CardDrop - The OG Personal Messenger" : draft.borderText
    }
    private var previewColor: Color {
        if draft.border == .decorative { return draft.borderTextColor }
        return draft.borderText.isEmpty ? Color.gray.opacity(0.35) : draft.borderTextColor
    }

    var body: some View {
        GeometryReader { geo in
        let frameSize = cardFrameSize(availableSize: geo.size)

        VStack(spacing: 0) {
            // Live card preview — fixed size, same across steps
            PostcardFrontCanvas(
                image: filteredImage ?? draft.composedImage ?? draft.image,
                overlays: draft.textOverlays,
                qrOverlays: draft.qrOverlays,
                burstOverlays: draft.burstOverlays,
                size: frameSize,
                border: draft.border,
                orientation: draft.orientation,
                borderText: previewText,
                borderFontName: draft.borderFontName,
                borderTextColor: previewColor
            )
            .frame(width: frameSize.width, height: frameSize.height)
            .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 5)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)

            Divider().padding(.top, 10)

            VStack(spacing: 12) {
                // Border type buttons
                HStack(spacing: 8) {
                    BorderOptionButton(title: "Borderless",  selected: draft.border == .fullBleed)   { draft.border = .fullBleed }
                    BorderOptionButton(title: "Classic",     selected: draft.border == .whiteBorder) { draft.border = .whiteBorder }
                    // Decorative and Custom Text hidden for now — code preserved below
                    // BorderOptionButton(title: "Decorative",  selected: draft.border == .decorative)  { switchToDecorative() }
                    // BorderOptionButton(title: "Custom Text", selected: draft.border == .customText)  { switchToCustomText() }
                }
                .padding(.horizontal)

                // Decorative preset picker
                if draft.border == .decorative {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(DecorativeBorderPreset.all) { preset in
                                let selected = draft.decorativePresetID == preset.id
                                Button {
                                    draft.decorativePresetID = preset.id
                                    draft.borderText         = preset.text
                                    draft.borderTextColor    = preset.color
                                    draft.borderFontName     = preset.fontName
                                } label: {
                                    Text(preset.name)
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(selected ? Color.brandBlue.opacity(0.12) : Color(.secondarySystemBackground))
                                        .foregroundColor(selected ? Color.brandBlue : .primary)
                                        .overlay(Capsule().stroke(selected ? Color.brandBlue : Color.clear, lineWidth: 1.5))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))

                    // Font + color tweak controls
                    HStack(spacing: 10) {
                        Picker("Font", selection: $draft.borderFontName) {
                            ForEach(borderFonts, id: \.name) { f in
                                Text(f.label).font(.custom(f.name, size: 14)).tag(f.name)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)

                        ColorPicker("", selection: $draft.borderTextColor, supportsOpacity: false)
                            .labelsHidden()
                    }
                    .padding(.horizontal)
                    .transition(.opacity)
                }

                // Custom text controls
                if draft.border == .customText {
                    VStack(spacing: 10) {
                        TextField("Border text…", text: $draft.borderText)
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 10) {
                            Picker("Font", selection: $draft.borderFontName) {
                                ForEach(borderFonts, id: \.name) { f in
                                    Text(f.label).font(.custom(f.name, size: 14)).tag(f.name)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)

                            ColorPicker("", selection: $draft.borderTextColor, supportsOpacity: false)
                                .labelsHidden()
                        }
                    }
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: draft.border)
            .padding(.vertical, 12)

            Spacer()

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
        }
        .frame(width: geo.size.width, height: geo.size.height)

        } // end GeometryReader
        .alert("Use Decorative as Starting Point?", isPresented: $showTransferAlert) {
            Button("Transfer") {
                // Keep the decorative text/font/color — already in draft
                draft.border = .customText
            }
            Button("Start Fresh") {
                draft.border          = .customText
                draft.borderText      = savedCustomText
                draft.borderFontName  = savedCustomFont
                draft.borderTextColor = savedCustomColor
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Would you like to start with the decorative border text, or go back to your previous custom text?")
        }
    }

    // MARK: - Border switching

    private func switchToDecorative() {
        if draft.border == .customText {
            // Save current custom state before leaving
            savedCustomText  = draft.borderText
            savedCustomFont  = draft.borderFontName
            savedCustomColor = draft.borderTextColor
        }
        draft.border = .decorative
    }

    private func switchToCustomText() {
        if draft.border == .decorative && !draft.borderText.isEmpty {
            // Ask whether to carry over the decorative text
            showTransferAlert = true
        } else {
            draft.border = .customText
        }
    }

    private func cardFrameSize(availableSize: CGSize) -> CGSize {
        let w = availableSize.width - 32
        return CGSize(width: w, height: w / draft.orientation.aspectRatio)
    }
}

private let borderFonts: [(name: String, label: String)] = [
    ("Georgia",             "Georgia"),
    ("Georgia-Italic",      "Georgia Italic"),
    ("Baskerville",         "Baskerville"),
    ("Palatino-Roman",      "Palatino"),
    ("TimesNewRomanPSMT",   "Times New Roman"),
    ("HelveticaNeue",       "Helvetica Neue"),
    ("HelveticaNeue-Bold",  "Helvetica Bold"),
    ("Futura-Medium",       "Futura"),
    ("AvenirNext-Regular",  "Avenir Next"),
    ("AmericanTypewriter",  "Typewriter"),
    ("CourierNewPSMT",      "Courier"),
]

private struct BorderOptionButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(selected ? Color.brandBlue.opacity(0.12) : Color(.secondarySystemBackground))
                .foregroundColor(selected ? Color.brandBlue : .primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(selected ? Color.brandBlue : Color.clear, lineWidth: 2)
                )
                .cornerRadius(10)
        }
    }
}
