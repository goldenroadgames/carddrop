import SwiftUI

struct CardFlipPreviewView: View {
    @ObservedObject var draft: PostcardDraft
    let filteredImage: UIImage?

    @Environment(\.dismiss) private var dismiss
    @State private var showingFront = true
    @State private var scaleX: CGFloat = 1.0

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let frontRatio = draft.orientation.aspectRatio
                let backRatio: CGFloat = 6.0 / 4.0          // back is always landscape
                let frontFrame = cardFrame(in: geo.size, ratio: frontRatio)
                let backFrame  = cardFrame(in: geo.size, ratio: backRatio)

                VStack(spacing: 20) {
                    Spacer()

                    Group {
                        if showingFront {
                            PostcardFrontCanvas(
                                image: filteredImage,
                                overlays: draft.textOverlays,
                                qrOverlays: draft.qrOverlays,
                                burstOverlays: draft.burstOverlays,
                                size: frontFrame
                            )
                            .frame(width: frontFrame.width, height: frontFrame.height)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            PostcardBackCanvas(draft: draft, size: backFrame, qr1Image: nil, qr2Image: nil)
                                .frame(width: backFrame.width, height: backFrame.height)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
                    .scaleEffect(x: scaleX, y: 1)
                    .onTapGesture { flip() }

                    Text(showingFront ? "Tap to see the back" : "Tap to see the front")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .navigationTitle(showingFront ? "Front" : "Back")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button { flip() } label: {
                        Label(
                            showingFront ? "Flip to Back" : "Flip to Front",
                            systemImage: "arrow.left.arrow.right"
                        )
                    }
                }
            }
        }
    }

    private func flip() {
        // Fold away
        withAnimation(.easeIn(duration: 0.18)) {
            scaleX = 0
        }
        // Swap face + unfold
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            showingFront.toggle()
            withAnimation(.easeOut(duration: 0.18)) {
                scaleX = 1
            }
        }
    }

    private func cardFrame(in available: CGSize, ratio: CGFloat) -> CGSize {
        let maxW = available.width - 48
        let maxH = available.height - 120
        if ratio >= 1 {
            let w = min(maxW, maxH * ratio)
            return CGSize(width: w, height: w / ratio)
        } else {
            let h = min(maxH, maxW / ratio)
            return CGSize(width: h * ratio, height: h)
        }
    }
}
