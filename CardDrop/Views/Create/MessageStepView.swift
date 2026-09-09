import SwiftUI
import CoreImage.CIFilterBuiltins

private enum MessageField: Hashable {
    case message
}

struct MessageStepView: View {
    @ObservedObject var draft: PostcardDraft
    var onNext: () -> Void

    @FocusState private var focus: MessageField?
    @State private var isModerating = false
    @State private var flaggedCategories: [String] = []
    @State private var showHardBlockAlert = false

    @State private var greetings: [CardbackGreeting] = []
    @State private var phrases: [CardbackPhrase] = []

    // From/To — also editable on Choose Photo, but since names are now
    // optional there (see [[project_choose_photo_step_split]] / the session
    // that dropped the namesFilled gate), this gives a second chance to
    // fill them in or fix a typo without having to go back a step.
    @State private var nicknameSyncTask: Task<Void, Never>?
    @State private var showToContactPicker = false
    @State private var contactPickedNickname: String?

    private var usedContactPickerForTo: Bool {
        contactPickedNickname != nil && contactPickedNickname == draft.recipientNickname
    }

    private static let phraseCategories = ["All", "Basic", "Romantic", "Quirky"]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {

            fromToRow

            CompactSegmentedControl(options: Self.phraseCategories, selection: $draft.phraseCategory)
                .opacity(phrases.isEmpty ? 0 : 1)
                .onChange(of: draft.phraseCategory) { _, _ in
                    draft.phraseId = filteredPhrases.first?.id
                }

            CarouselRow(
                text: greetingPreviewText,
                onPrev: { stepGreeting(by: -1) },
                onNext: { stepGreeting(by: 1) }
            )
            .opacity(greetings.isEmpty ? 0 : 1)

            CarouselRow(
                text: phrasePreviewText,
                onPrev: { stepPhrase(by: -1) },
                onNext: { stepPhrase(by: 1) }
            )
            .opacity(phrases.isEmpty ? 0 : 1)

            // Message section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Message")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                    Text("\(draft.message.count)/525")
                        .font(.caption)
                        .foregroundColor(draft.message.count >= 525 ? .red : .secondary)
                }
                .padding(.top, 4)

                ZStack(alignment: .topLeading) {
                    if draft.message.isEmpty {
                        Text("Write your message…")
                            .foregroundColor(Color(.placeholderText))
                            .padding(.horizontal, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $draft.message)
                        .font(.system(size: 17, weight: .regular))
                        .frame(maxHeight: .infinity)
                        .scrollContentBackground(.hidden)
                        // Counteracts TextEditor's built-in ~8pt textContainerInset,
                        // which isn't otherwise exposed to trim directly.
                        .padding(.top, -8)
                        .focused($focus, equals: .message)
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") { focus = nil }
                                    .buttonStyle(.borderedProminent)
                                    .tint(Color.brandBlue)
                            }
                        }
                        .onKeyPress(.tab) { .handled }
                        .onKeyPress(.return) { .handled }
                        .onChange(of: draft.message) { _, new in
                            let cleaned = String(new.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
                            let trimmed = cleaned.count > 525 ? String(cleaned.prefix(525)) : cleaned
                            if trimmed != new {
                                draft.message = trimmed
                            }
                        }
                }
                .padding(3)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal)
        .padding(.top, 5 - 15 + 5)
        .padding(.bottom, 0)
        .task {
            if greetings.isEmpty {
                greetings = await CardBackContentService.fetchGreetings()
                if draft.greetingId == nil {
                    draft.greetingId = greetings.first(where: { $0.sort_order == 0 })?.id ?? greetings.first?.id
                }
            }
            // Always refresh (not just on first fetch) — if the "To"/"From"
            // nickname was changed back on Style It since this view last
            // computed greetingSalutation/Closing, arriving here needs to
            // re-fill the greeting with the current nickname rather than
            // leaving the stale text baked into the draft.
            updateGreetingText()
            if phrases.isEmpty {
                phrases = await CardBackContentService.fetchPhrases()
                if draft.phraseId == nil {
                    draft.phraseId = phrases.first(where: { $0.sort_order == 0 })?.id ?? phrases.first?.id
                }
                updatePhraseText()
            }
        }
        .onChange(of: draft.greetingId) { _, _ in updateGreetingText() }
        .onChange(of: draft.senderNickname) { _, _ in updateGreetingText() }
        .onChange(of: draft.recipientNickname) { _, _ in updateGreetingText() }
        .onChange(of: draft.phraseId) { _, _ in updatePhraseText() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 5) {
                LiveBackPreview(draft: draft)
                    .padding(.horizontal)
                    .offset(y: -5)

                Button {
                    focus = nil

                    let recipientMissing = draft.recipientNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let senderMissing = draft.senderNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    draft.showRecipientNicknameError = recipientMissing
                    draft.showSenderNicknameError = senderMissing
                    guard !recipientMissing && !senderMissing else { return }

                    if draft.moderationState == .passed {
                        onNext()
                        return
                    }
                    Task {
                        isModerating = true
                        let result = await ModerationService.check(texts: messageTexts)
                        isModerating = false
                        switch result {
                        case .clean:
                            draft.moderationState = .passed
                            onNext()
                        case .flagged(let categories):
                            flaggedCategories = categories
                            showHardBlockAlert = true
                        }
                    }
                } label: {
                    Group {
                        if isModerating {
                            ProgressView().tint(.white)
                        } else {
                            Text("Next: Addresses")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.brandBlue)
                    .foregroundColor(.white)
                    .cornerRadius(999)
                }
                .disabled(isModerating)
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            .padding(.top, 12)
            .background(Color(uiColor: .systemBackground))
        }
        // Hard block — sexual, violence, self-harm, harassment (no override)
        .alert("Content Not Allowed", isPresented: $showHardBlockAlert) {
            Button("Edit Message", role: .cancel) { }
        } message: {
            Text("Your message was flagged for: \(flaggedCategories.joined(separator: ", ")). Please revise before continuing.")
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var messageTexts: [String] {
        var texts = [draft.message]
        texts += draft.qrOverlays.map { $0.content }
        return texts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: - Greeting carousel

    private var currentGreetingIndex: Int {
        greetings.firstIndex(where: { $0.id == draft.greetingId }) ?? 0
    }

    private var greetingPreviewText: String {
        guard greetings.indices.contains(currentGreetingIndex) else { return "" }
        let filled = greetings[currentGreetingIndex].filled(sender: draft.senderNickname, recipient: draft.recipientNickname)
        return [filled.salutation, filled.closing].filter { !$0.isEmpty }.joined(separator: "   ")
    }

    private func stepGreeting(by delta: Int) {
        guard !greetings.isEmpty else { return }
        let newIndex = (currentGreetingIndex + delta + greetings.count) % greetings.count
        draft.greetingId = greetings[newIndex].id
    }

    private func updateGreetingText() {
        guard let id = draft.greetingId, let g = greetings.first(where: { $0.id == id }) else {
            draft.greetingSalutation = ""
            draft.greetingClosing = ""
            return
        }
        let filled = g.filled(sender: draft.senderNickname, recipient: draft.recipientNickname)
        draft.greetingSalutation = filled.salutation
        draft.greetingClosing = filled.closing
    }

    // MARK: - Phrase carousel

    private var filteredPhrases: [CardbackPhrase] {
        guard draft.phraseCategory != "All" else { return phrases }
        return phrases.filter { $0.category == draft.phraseCategory }
    }

    private var currentPhraseIndex: Int {
        filteredPhrases.firstIndex(where: { $0.id == draft.phraseId }) ?? 0
    }

    private var phrasePreviewText: String {
        guard filteredPhrases.indices.contains(currentPhraseIndex) else { return "" }
        return filteredPhrases[currentPhraseIndex].text
    }

    private func stepPhrase(by delta: Int) {
        guard !filteredPhrases.isEmpty else { return }
        let newIndex = (currentPhraseIndex + delta + filteredPhrases.count) % filteredPhrases.count
        draft.phraseId = filteredPhrases[newIndex].id
    }

    private func updatePhraseText() {
        guard let id = draft.phraseId, let p = phrases.first(where: { $0.id == id }) else {
            draft.phraseText = ""
            return
        }
        draft.phraseText = p.text
    }

    // Same From/To control as Choose Photo (ChoosePhotoStepView.fromToRow) —
    // kept in sync by hand rather than shared, since the two steps' layouts
    // don't otherwise share a common container.
    private var fromToRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 6) {
                    Text("To")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.brandBlue)
                    Button {
                        showToContactPicker = true
                    } label: {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .foregroundColor(.accentColor)
                            .frame(minWidth: 28, minHeight: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    TextField("e.g. Grandma & Grandpa", text: $draft.recipientNickname)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(draft.showRecipientNicknameError ? Color.red : Color(.systemGray4), lineWidth: draft.showRecipientNicknameError ? 1.5 : 1)
                        )
                        .onChange(of: draft.recipientNickname) { _, _ in draft.showRecipientNicknameError = false }
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 6) {
                    Text("From")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.brandBlue)
                    TextField("e.g. Pookie", text: $draft.senderNickname)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(draft.showSenderNicknameError ? Color.red : Color(.systemGray4), lineWidth: draft.showSenderNicknameError ? 1.5 : 1)
                        )
                        .onChange(of: draft.senderNickname) { _, newValue in
                            draft.showSenderNicknameError = false
                            nicknameSyncTask?.cancel()
                            nicknameSyncTask = Task {
                                try? await Task.sleep(nanoseconds: 800_000_000)
                                guard !Task.isCancelled else { return }
                                await UserService.updateSenderNickname(newValue)
                            }
                        }
                }
                .frame(maxWidth: .infinity)
            }

            if usedContactPickerForTo {
                Text("Edit to use a different nickname, sunshine")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.brandBlue)
                    .padding(.leading, 8)
            }
        }
        .padding(.bottom, 8)
        .sheet(isPresented: $showToContactPicker) {
            ContactNamePickerView { info in
                if !info.nickname.isEmpty { draft.recipientNickname = info.nickname }
                contactPickedNickname = draft.recipientNickname
                draft.recipientFirstName = info.firstName
                draft.recipientLastName  = info.lastName
                draft.recipientStreet    = info.street
                draft.recipientCity      = info.city
                draft.recipientState     = info.state
                draft.recipientZip       = info.zip
                draft.recipientCountry   = info.country
                draft.recipientEmail     = info.email
                draft.recipientPhone     = info.phone
            }
        }
    }
}

// MARK: - Carousel row

private struct CarouselRow: View {
    let text: String
    let onPrev: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            Button(action: onPrev) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.brandBlue)
                    .padding(.vertical, 7)
            }
            Spacer(minLength: 8)
            Text(text)
                .font(.system(size: 17, weight: .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
            Spacer(minLength: 8)
            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.brandBlue)
                    .padding(.vertical, 7)
            }
        }
        .padding(.horizontal, 8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(999)
    }
}

// MARK: - Compact segmented control

private struct CompactSegmentedControl: View {
    let options: [String]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    Text(option)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(selection == option ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(selection == option ? Color(.systemBackground) : Color.clear)
                        .cornerRadius(999)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(999)
    }
}

// MARK: - Live back preview
//
// PostcardBackCanvas uses fixed absolute pixel coordinates (2700x1800
// native canvas), not proportional ones, so it must be rendered at that
// native size and then visually scaled down — not handed a small size
// directly, which would break its internal geometry.
private struct LiveBackPreview: View {
    @ObservedObject var draft: PostcardDraft

    private let nativeSize = CGSize(width: 2700, height: 1800)

    @State private var qr1Image: UIImage?
    @State private var qr2Image: UIImage?

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / nativeSize.width
            PostcardBackCanvas(draft: draft, size: nativeSize, qr1Image: qr1Image, qr2Image: qr2Image)
                .frame(width: nativeSize.width, height: nativeSize.height)
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
                .compositingGroup()
                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
        }
        .aspectRatio(nativeSize.width / nativeSize.height, contentMode: .fit)
        .task(id: draft.backMessageQRContent) {
            let qr1Content = draft.includeBackMessageQR && !draft.backMessageQRContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? draft.backMessageQRContent
                : "https://carddropapp.com"
            qr1Image = Self.makeQRCode(from: qr1Content)
            qr2Image = Self.makeQRCode(from: "https://carddropapp.com/card/\(draft.cardID.uuidString)")
        }
    }

    private static func makeQRCode(from string: String) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M",  forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

#Preview {
    MessageStepView(draft: PostcardDraft(), onNext: {})
        .environmentObject(AppSettings())
}
