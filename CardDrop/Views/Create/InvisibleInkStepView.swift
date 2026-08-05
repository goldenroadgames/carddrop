import SwiftUI
import CoreImage.CIFilterBuiltins

struct InvisibleInkStepView: View {
    @ObservedObject var draft: PostcardDraft
    var onNext: () -> Void

    @State private var isModerating = false
    @State private var showBlockAlert = false
    @State private var flaggedCategories: [String] = []
    @FocusState private var textFocused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {

                // Header
                VStack(spacing: 8) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)

                    Text("Invisible Ink")
                        .font(.title.bold())
                        .foregroundColor(.white)

                    Text("Add a secret message they unlock with their phone camera")
                        .font(.subheadline)
                        .foregroundColor(.green.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top)

                // Text input
                VStack(alignment: .leading, spacing: 6) {
                    ZStack(alignment: .topLeading) {
                        if draft.backMessageQRContent.isEmpty {
                            Text("Only they will know…")
                                .foregroundColor(.green.opacity(0.35))
                                .padding(.horizontal, 5)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $draft.backMessageQRContent)
                            .frame(minHeight: 120)
                            .scrollContentBackground(.hidden)
                            .foregroundColor(.green)
                            .focused($textFocused)
                            .onChange(of: draft.backMessageQRContent) { _, new in
                                if new.count > 200 {
                                    draft.backMessageQRContent = String(new.prefix(200))
                                }
                            }
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.07))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.green.opacity(0.25), lineWidth: 1)
                    )

                    HStack {
                        Spacer()
                        Text("\(draft.backMessageQRContent.count)/200")
                            .font(.caption)
                            .foregroundColor(draft.backMessageQRContent.count >= 200 ? .red : .green.opacity(0.4))
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal)

                // Live QR preview
                if !draft.backMessageQRContent.isEmpty, let qrImage = makeQRCode(from: draft.backMessageQRContent) {
                    VStack(spacing: 6) {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 110, height: 110)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.green.opacity(0.4), lineWidth: 1)
                            )
                        Text("Your secret, encoded")
                            .font(.caption2)
                            .foregroundColor(.green.opacity(0.4))
                    }
                }

                Spacer()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                textFocused = false
                guard !draft.backMessageQRContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    onNext()
                    return
                }
                Task {
                    isModerating = true
                    let result = await ModerationService.check(texts: [draft.backMessageQRContent])
                    isModerating = false
                    switch result {
                    case .clean:
                        onNext()
                    case .flagged(let categories):
                        flaggedCategories = categories
                        showBlockAlert = true
                    }
                }
            } label: {
                Group {
                    if isModerating {
                        ProgressView().tint(.white)
                    } else {
                        Text("Next: Addresses")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.brandBlue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isModerating)
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color.black)
        }
        .onAppear { textFocused = true }
        .alert("Content Not Allowed", isPresented: $showBlockAlert) {
            Button("Edit Message", role: .cancel) { }
        } message: {
            Text("Your hidden message was flagged for: \(flaggedCategories.joined(separator: ", ")). Please revise before continuing.")
        }
    }

    private func makeQRCode(from string: String) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

#Preview {
    InvisibleInkStepView(draft: PostcardDraft(), onNext: {})
}
