import SwiftUI

struct CanvasSetupStepView: View {
    @ObservedObject var draft: PostcardDraft
    var onNext: () -> Void

    @GestureState private var gestureScale: CGFloat = 1.0
    @GestureState private var gestureDrag: CGSize = .zero

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

            // Frame preview + button — all inside GeometryReader so frameSize is always live
            GeometryReader { geo in
                let frameSize = postcardFrameSize(in: CGSize(width: geo.size.width, height: geo.size.height - 80))

                VStack(spacing: 0) {
                    Spacer()

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

                    Spacer()

                    Text("Pinch to zoom · Drag to reposition")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)

                    Button(action: {
                        draft.renderComposedImage(frameSize: frameSize)
                        onNext()
                    }) {
                        Text("Next: Choose Filter")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.brandBlue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
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
