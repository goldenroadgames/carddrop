import SwiftUI

struct NicknameStepView: View {
    @ObservedObject var draft: PostcardDraft
    var onNext: () -> Void

    @State private var syncTask: Task<Void, Never>?

    private var isValid: Bool {
        !draft.senderNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.recipientNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            GreetingsPostcardGraphic()

            Text("Who's this card between?")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 6) {
                Text("From")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g. Pookie", text: $draft.senderNickname)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: draft.senderNickname) { _, newValue in
                        syncTask?.cancel()
                        syncTask = Task {
                            try? await Task.sleep(nanoseconds: 800_000_000)
                            guard !Task.isCancelled else { return }
                            await UserService.updateSenderNickname(newValue)
                        }
                    }
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 6) {
                Text("To")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g. Grandma & Grandpa", text: $draft.recipientNickname)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)

            Spacer()
        }
        .task {
            if draft.senderNickname.isEmpty, let saved = await UserService.fetchSenderNickname(), !saved.isEmpty {
                draft.senderNickname = saved
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: onNext) {
                Text("Next: Choose Photo")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(isValid ? Color.brandBlue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(!isValid)
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(uiColor: .systemBackground))
        }
    }
}
