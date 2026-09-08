import SwiftUI

// Publishes the canvas's current frameSize up to the top-level body, which
// needs it in the .safeAreaInset closure (outside the GeometryReader that
// computes it) to pass to draft.renderComposedImage(frameSize:).
private struct FrameSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

struct CanvasSetupStepView: View {
    @ObservedObject var draft: PostcardDraft
    var onNext: () -> Void

    @GestureState private var gestureScale: CGFloat = 1.0
    @GestureState private var gestureDrag: CGSize = .zero
    @State private var lastFrameSize: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            // Orientation picker
            Picker("Orientation", selection: $draft.orientation) {
                Text("Landscape").tag(PostcardOrientation.landscape)
                Text("Portrait").tag(PostcardOrientation.portrait)
            }
            .pickerStyle(.segmented)
            .padding()
            .onChange(of: draft.orientation) { _, _ in
                draft.imageScale = 1.0
                draft.imageOffset = .zero
            }

            // Frame preview — the GeometryReader only has to size the canvas
            // itself now; the hint text and "Next" button live in the
            // .safeAreaInset below, where SwiftUI reserves their real
            // measured height automatically instead of a guessed constant.
            GeometryReader { geo in
                let frameSize = postcardFrameSize(in: geo.size)

                ZStack {
                    if let image = draft.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: frameSize.width, height: frameSize.height)
                            .scaleEffect(draft.imageScale * gestureScale)
                            .offset(
                                x: draft.imageOffset.width + gestureDrag.width,
                                y: draft.imageOffset.height + gestureDrag.height
                            )
                            .clipped()
                    }
                }
                .frame(width: frameSize.width, height: frameSize.height)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(4)
                .shadow(radius: 4)
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .updating($gestureScale) { value, state, _ in state = value }
                            .onEnded { value in
                                draft.imageScale = max(1.0, draft.imageScale * value)
                            },
                        DragGesture()
                            .updating($gestureDrag) { value, state, _ in state = value.translation }
                            .onEnded { value in
                                draft.imageOffset.width += value.translation.width
                                draft.imageOffset.height += value.translation.height
                            }
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .background(Color.clear.preference(key: FrameSizeKey.self, value: frameSize))
            }
        }
        .onPreferenceChange(FrameSizeKey.self) { lastFrameSize = $0 }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Text("Pinch to zoom · Drag to reposition")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button {
                        draft.imageScale = 1.0
                        draft.imageOffset = .zero
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
                .padding(.bottom, 8)

                Button(action: {
                    draft.renderComposedImage(frameSize: lastFrameSize)
                    onNext()
                }) {
                    Text("Next: Choose Filter")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.brandBlue)
                        .foregroundColor(.white)
                        .cornerRadius(999)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(Color(uiColor: .systemBackground))
        }
    }

    private func postcardFrameSize(in available: CGSize) -> CGSize {
        let maxWidth = available.width - 48
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
}
