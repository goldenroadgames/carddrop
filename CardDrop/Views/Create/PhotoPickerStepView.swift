import SwiftUI
import PhotosUI

// Minimum pixel dimensions for acceptable print quality on a 6x9 postcard at ~200 DPI.
// 300 DPI ideal = 1800×2700; we warn below that but still allow proceeding.
private let minPrintPixels: CGFloat = 1800  // long side
private let minPrintPixelsShort: CGFloat = 1200  // short side

struct PhotoPickerStepView: View {
    @ObservedObject var draft: PostcardDraft
    @Binding var photoItem: PhotosPickerItem?
    var onNext: () -> Void

    @State private var isPickerPresented = false
    @State private var isModerating = false
    @State private var pendingLowResImage: UIImage? = nil
    @State private var showLowResAlert = false
    @State private var flaggedCategories: [String] = []
    @State private var showModerationAlert = false

    @GestureState private var gestureScale: CGFloat = 1.0
    @GestureState private var gestureDrag: CGSize = .zero

    // Set from the GeometryReader; drives rerenderComposed()
    @State private var availableSize: CGSize = .zero

    var body: some View {
        // GeometryReader is the outermost container so we get the full
        // available size in one place. Everything inside is a plain VStack
        // flow — no centering tricks — so the card top never moves.
        GeometryReader { geo in
            // Budget for all non-card fixed elements:
            //   orientation picker ~44pt + hint text ~32pt = ~76pt header
            //   border picker ~42pt + choose diff ~44pt + next ~54pt = ~140pt footer
            //   total ~220pt  →  card gets the rest
            let cardAvailable = CGSize(
                width: geo.size.width,
                height: max(0, geo.size.height - 220)
            )
            let frameSize = postcardFrameSize(in: cardAvailable)
            let imgSize   = borderImageSize(in: frameSize)

            if draft.image != nil {
                VStack(alignment: .center, spacing: 0) {
                    // ── Orientation picker ─────────────────────────────
                    Picker("Orientation", selection: $draft.orientation) {
                        Text("Landscape").tag(PostcardOrientation.landscape)
                        Text("Portrait").tag(PostcardOrientation.portrait)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .onChange(of: draft.orientation) { _, _ in
                        draft.imageScale = 1.0
                        draft.imageOffset = .zero
                        rerenderComposed()
                    }

                    // ── Hint text ──────────────────────────────────────
                    Text("Pinch to zoom · Drag to reposition")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .padding(.vertical, 6)

                    // ── Card preview ───────────────────────────────────
                    // Top is anchored here (right below hint text).
                    // Height varies with orientation; controls below follow.
                    ZStack {
                        if draft.border == .whiteBorder { Color.white }
                        if let image = draft.image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: imgSize.width, height: imgSize.height)
                                .scaleEffect(draft.imageScale * gestureScale)
                                .offset(
                                    x: draft.imageOffset.width + gestureDrag.width,
                                    y: draft.imageOffset.height + gestureDrag.height
                                )
                                .clipped()
                        }
                    }
                    .frame(width: frameSize.width, height: frameSize.height)
                    .clipped()
                    .contentShape(Rectangle())
                    .background(Color.gray.opacity(0.2))
                    .compositingGroup()
                    .shadow(radius: 4)
                    .animation(.none, value: draft.orientation)
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .updating($gestureScale) { value, state, _ in state = value }
                                .onEnded { value in
                                    draft.imageScale = max(1.0, draft.imageScale * value)
                                    rerenderComposed()
                                },
                            DragGesture()
                                .updating($gestureDrag) { value, state, _ in state = value.translation }
                                .onEnded { value in
                                    draft.imageOffset.width += value.translation.width
                                    draft.imageOffset.height += value.translation.height
                                    rerenderComposed()
                                }
                        )
                    )

                    // ── Border + choose diff (follow card bottom) ──────
                    Picker("Border", selection: $draft.border) {
                        Text("Borderless").tag(PostcardBorder.fullBleed)
                        Text("Classic").tag(PostcardBorder.whiteBorder)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 10)

                    Button("Choose a Different Photo") {
                        isPickerPresented = true
                    }
                    .font(.subheadline)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())

                }
                .onAppear { availableSize = cardAvailable }
                .onChange(of: geo.size) { _, newSize in
                    availableSize = CGSize(width: newSize.width, height: max(0, newSize.height - 220))
                }

            } else {
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
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isModerating ? Color.gray : Color.brandBlue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .disabled(isModerating)
                    .padding(.horizontal)
                    Spacer()
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if draft.image != nil {
                Button(action: {
                    draft.renderComposedImage(frameSize: borderImageSize(in: postcardFrameSize(in: availableSize)))
                    onNext()
                }) {
                    Text("Next: Style It")
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
        }
        .photosPicker(isPresented: $isPickerPresented, selection: $photoItem, matching: .images)
        .task {
            if draft.image == nil {
                isPickerPresented = true
            }
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
                print("📐 Photo resolution: \(Int(pixelWidth))×\(Int(pixelHeight))px — long: \(Int(longSide)), short: \(Int(shortSide))")
                if longSide < minPrintPixels || shortSide < minPrintPixelsShort {
                    pendingLowResImage = image
                    showLowResAlert = true
                    return
                }

                draft.image = image
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

    private func postcardFrameSize(in available: CGSize) -> CGSize {
        guard available.width > 0, available.height > 0 else { return .zero }
        let maxWidth  = available.width  - 48
        let maxHeight = available.height - 16
        let ratio = draft.orientation.aspectRatio
        if ratio >= 1 {
            let w = min(maxWidth, maxHeight * ratio)
            return CGSize(width: w, height: w / ratio)
        } else {
            let h = min(maxHeight, maxWidth / ratio)
            return CGSize(width: h * ratio, height: h)
        }
    }

    private func borderImageSize(in frameSize: CGSize) -> CGSize {
        guard draft.border == .whiteBorder else { return frameSize }
        let fx: CGFloat = draft.orientation == .landscape ? 0.25/6.0 : 0.25/4.0
        let fy: CGFloat = draft.orientation == .landscape ? 0.25/4.0 : 0.25/6.0
        return CGSize(width: frameSize.width  - 2 * frameSize.width  * fx,
                      height: frameSize.height - 2 * frameSize.height * fy)
    }

    private func rerenderComposed() {
        guard availableSize != .zero, draft.image != nil else { return }
        let frameSize = postcardFrameSize(in: availableSize)
        draft.renderComposedImage(frameSize: borderImageSize(in: frameSize))
    }
}
