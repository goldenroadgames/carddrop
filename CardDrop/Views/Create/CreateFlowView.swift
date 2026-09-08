import Combine
import SwiftUI
import PhotosUI

struct CreateFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var draftManager: DraftManager

    var onSendToSomeoneElse: ((PostcardDraft) -> Void)? = nil
    var onEditCard: ((PostcardDraft) -> Void)? = nil

    @StateObject private var draft: PostcardDraft
    @State private var currentStep: Int
    @State private var currentDraftID: UUID?
    @State private var photoItem: PhotosPickerItem?
    @State private var originalStatus: CardStatus = .unsent
    @State private var isDirty = false
    @State private var showSavedBanner = false
    @State private var filteredImage: UIImage? = nil

    @State private var isModerating = false
    @State private var moderationFlagged: [String] = []
    @State private var showHardBlockAlert = false

    // Default: new blank postcard
    init() {
        _draft         = StateObject(wrappedValue: PostcardDraft())
        _currentStep   = State(initialValue: 0)
        _currentDraftID = State(initialValue: nil)
    }

    // Resume from saved draft. Pass draftID=nil to open as a new copy (e.g. re-editing a sent card).
    init(resuming draft: PostcardDraft, step: Int, draftID: UUID?,
         originalStatus: CardStatus = .unsent,
         onSendToSomeoneElse: ((PostcardDraft) -> Void)? = nil,
         onEditCard: ((PostcardDraft) -> Void)? = nil) {
        _draft           = StateObject(wrappedValue: draft)
        _currentStep     = State(initialValue: step)
        _currentDraftID  = State(initialValue: draftID)
        _originalStatus  = State(initialValue: originalStatus)
        self.onSendToSomeoneElse = onSendToSomeoneElse
        self.onEditCard          = onEditCard
    }

    var hasStarted: Bool { draft.image != nil }

    var namesFilled: Bool {
        !draft.senderNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.recipientNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                switch currentStep {
                case 0:
                    ChoosePhotoStepView(draft: draft, photoItem: $photoItem, onNext: { currentStep = 1 })
                case 1:
                    TextOverlayStepView(draft: draft, onNext: { currentStep = 2 })
                case 2:
                    MessageStepView(draft: draft, onNext: {
                        currentStep = 4
                    })
                case 3:
                    InvisibleInkStepView(draft: draft, onNext: { currentStep = 4 })
                case 4:
                    BackOfCardStepView(draft: draft, onNext: { currentStep = 5 })
                case 5:
                    SendOptionsView(draft: draft, filteredImage: filteredImage,
                                    originalStatus: originalStatus,
                                    hasDraftSaved: currentDraftID != nil,
                                    onSaveUnsent:    { saveDraft(status: .unsent) },
                                    onSaveSent:      { saveDraft(status: .sent) },
                                    onGoToFront:     { currentStep = 1 },
                                    onGoToBack:      { currentStep = 2 },
                                    onGoToAddress:   { currentStep = 4 },
                                    onFinish:        { dismiss() },
                                    onSendToSomeoneElse: {
                                        let clone = draft.cloneForNewRecipient()
                                        onSendToSomeoneElse?(clone)
                                        dismiss()
                                    },
                                    onEditCard: {
                                        if originalStatus == .sent {
                                            let clone = draft.cloneExact()
                                            // MyCardsView's onEditCard sets resumeParams = nil,
                                            // which is what actually dismisses this fullScreenCover —
                                            // calling dismiss() here too would race a second dismissal
                                            // against it and drop the delayed reopen.
                                            onEditCard?(clone)
                                        } else {
                                            currentStep = 0
                                        }
                                    })
                default:
                    Text("More steps coming soon")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Left: step navigation arrows (hidden for immutable sent cards).
                // Explicitly styled (not the system's default toolbar-button chrome).
                // On iOS 26+, ToolbarItemGroup/ToolbarItem still get an OS-drawn
                // Liquid Glass background SHARED across the group regardless of
                // our own button styling — sharedBackgroundVisibility(.hidden)
                // (iOS 26+ only) opts back out of that so only our pill shows.
                if #available(iOS 26.0, *) {
                    ToolbarItemGroup(placement: .navigationBarLeading) { chevronControls }
                        .sharedBackgroundVisibility(.hidden)
                    ToolbarItem(placement: .navigationBarTrailing) { closeButton }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItemGroup(placement: .navigationBarLeading) { chevronControls }
                    ToolbarItem(placement: .navigationBarTrailing) { closeButton }
                }
            }
            .onAppear { recomputeFilteredImage() }
            // @Published's publisher fires from willSet — draft.composedImage
            // itself hasn't been updated to the new value yet at this point,
            // so use the value the publisher actually delivers instead of
            // re-reading (stale) draft.composedImage (same issue as
            // [[feedback_published_willset_timing]]). Otherwise the preview
            // permanently lags one revision behind — most visibly, right
            // after a photo is first picked, composedImage transitions from
            // nil to its first bake, and a stale read still sees nil, so
            // recomputeFilteredImage() falls back to the raw unzoomed
            // draft.image instead of the actual pinch/drag-adjusted crop.
            .onReceive(draft.$composedImage) { newComposed in recomputeFilteredImage(composedOverride: newComposed) }
            .onReceive(draft.$filter)        { newFilter in recomputeFilteredImage(filterOverride: newFilter) }
            .onChange(of: currentStep) { oldValue, newValue in
                updateThumbnail()
                // Forward or backward — either way, leaving Choose Photo
                // (photo/orientation/border/filter content), Style It (front
                // text-overlay content), Write Card (back message/greeting/
                // phrase content), or Addresses (back sender/recipient
                // content — the last step that touches the back) bakes+saves
                // the real {cardID}_front.jpg/_back.jpg/_back6x9.jpg now
                // rather than waiting for Preview to first appear. Close
                // doesn't change currentStep, so it's handled separately
                // below.
                if oldValue == 0 && newValue != 0 { bakeDraftArt() }
                if oldValue == 1 && newValue != 1 { bakeDraftArt() }
                if oldValue == 2 && newValue != 2 { bakeDraftArt() }
                if oldValue == 4 && newValue != 4 { bakeDraftArt() }
            }

            .onReceive(draft.objectWillChange) { _ in isDirty = true }
            .alert("Content Not Allowed", isPresented: $showHardBlockAlert) {
                Button("Go to Message Step") { currentStep = 3 }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your message was flagged for: \(moderationFlagged.joined(separator: ", ")). Please revise before continuing.")
            }
            // Brief "Draft saved" banner
            .overlay(alignment: .top) {
                if showSavedBanner {
                    Text("Draft saved")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showSavedBanner)
        }
        .dynamicTypeSize(.medium ... .xxxLarge)
    }

    // MARK: - Save

    private func saveDraft(status: CardStatus = .unsent) {
        let id = draftManager.save(draft: draft, currentStep: currentStep, status: status, existingID: currentDraftID)
        currentDraftID = id
        updateThumbnail()
        showSavedBanner = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            showSavedBanner = false
        }
    }

    // MARK: - Front bake

    // Bakes+saves the real {cardID}_front.jpg and _back.jpg (CardRenderer
    // always renders both together) whenever the user leaves either step
    // that changes what ends up on them — Style It (front photo/text
    // overlays) or Addresses (back message/greeting/phrase) — forward,
    // backward, or Close — instead of only lazily at Preview time.
    // Fire-and-forget: the caller doesn't await this, so it never blocks
    // navigation/dismiss.
    private func bakeDraftArt() {
        guard hasStarted else { return }
        let d = draft
        let img = filteredImage
        let dm = draftManager
        Task { @MainActor in
            // CardRenderer.renderAndSave is synchronous, @MainActor, CPU-bound
            // (ImageRenderer over photo + text bubbles + Greetings badge —
            // can take a real fraction of a second to multiple seconds). If
            // this Task starts running before SwiftUI processes the pending
            // dismiss() from Close, it hogs the main thread for the whole
            // render, making the app look frozen/unresponsive right when the
            // user taps Close. Yield first so the dismiss transition gets to
            // happen before this heavy work runs.
            await Task.yield()
            _ = CardRenderer.renderAndSave(draft: d, filteredImage: img, draftManager: dm)
        }
    }

    // MARK: - Thumbnail

    private func updateThumbnail() {
        guard draft.image != nil else { return }
        if currentDraftID == nil { saveDraft(); return }
        guard let snapshotID = currentDraftID else { return }
        let isLandscape = draft.orientation == .landscape
        let frontSize = isLandscape ? CGSize(width: 900, height: 600) : CGSize(width: 600, height: 900)
        let renderer = ImageRenderer(
            content: PostcardFrontCanvas(
                image: filteredImage ?? draft.image,
                overlays: draft.textOverlays,
                qrOverlays: draft.qrOverlays,
                burstOverlays: draft.burstOverlays,
                greetingsOverlays: draft.greetingsOverlays,
                size: frontSize,
                border: draft.border,
                orientation: draft.orientation,
                borderText: draft.borderText,
                borderFontName: draft.borderFontName,
                borderTextColor: draft.borderTextColor
            )
        )
        renderer.proposedSize = ProposedViewSize(frontSize)
        renderer.isOpaque = true
        guard let img = renderer.uiImage else { return }
        draftManager.saveDraftFront(img, snapshotID: snapshotID, draft: draft, currentStep: currentStep)
    }

    // MARK: - Filtered image

    private func recomputeFilteredImage(composedOverride: UIImage?? = nil, filterOverride: PostcardFilter? = nil) {
        guard let base = (composedOverride ?? draft.composedImage) ?? draft.image else { return }
        guard let cgImage = base.cgImage else { return }
        let filter = filterOverride ?? draft.filter
        let scale = base.scale
        let orientation = base.imageOrientation
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                // CGImage and PostcardFilter (enum) are Sendable — safe to cross actor boundary
                let image = UIImage(cgImage: cgImage, scale: scale, orientation: orientation)
                return filter.apply(to: image)
            }.value
            filteredImage = result
        }
    }

    // MARK: - Moderation

    private var messageTextsFromDraft: [String] {
        var texts = [draft.message]
        if draft.includeBackMessageQR { texts.append(draft.backMessageQRContent) }
        texts += draft.qrOverlays.map { $0.content }
        return texts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: - Step title

    var stepTitle: String {
        switch currentStep {
        case 0: return "Choose Photo"
        case 1: return "Style It"
        case 2: return "Write Card"
        case 3: return "Invisible Ink"
        case 4: return "Addresses"
        case 5: return "Send"
        default: return "Create"
        }
    }

    private func nextStep(from step: Int) -> Int {
        if step == 2 { return draft.includeBackMessageQR ? 3 : 4 }
        return step + 1
    }

    private func prevStep(from step: Int) -> Int {
        if step == 4 { return draft.includeBackMessageQR ? 3 : 2 }
        return step - 1
    }

    // MARK: - Toolbar controls

    @ViewBuilder
    private var chevronControls: some View {
        if originalStatus != .sent {
            HStack(spacing: 0) {
                Button { currentStep = prevStep(from: currentStep) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(currentStep == 0 ? Color.brandBlue.opacity(0.4) : Color.brandBlue)
                        .frame(width: 36, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(currentStep == 0)

                Button {
                    let next = nextStep(from: currentStep)
                    if currentStep >= 2 && draft.moderationState == .untested {
                        Task {
                            isModerating = true
                            let result = await ModerationService.check(texts: messageTextsFromDraft)
                            isModerating = false
                            switch result {
                            case .clean:
                                draft.moderationState = .passed
                                currentStep = next
                            case .flagged(let categories):
                                moderationFlagged = categories
                                showHardBlockAlert = true
                            }
                        }
                    } else {
                        currentStep = next
                    }
                } label: {
                    Group {
                        if isModerating {
                            ProgressView()
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .foregroundColor(
                        (currentStep >= 5 || (currentStep == 0 && (!hasStarted || !namesFilled)) || isModerating)
                            ? Color.brandBlue.opacity(0.4) : Color.brandBlue
                    )
                    .frame(width: 36, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(currentStep >= 5 || (currentStep == 0 && (!hasStarted || !namesFilled)) || isModerating)
            }
        }
    }

    private var closeButton: some View {
        Button {
            if hasStarted && (originalStatus == .unsent || isDirty) {
                saveDraft()
                // Close doesn't change currentStep, so it isn't
                // caught by the onChange(of: currentStep) below —
                // needs its own explicit call.
                if currentStep == 0 || currentStep == 1 || currentStep == 2 || currentStep == 4 { bakeDraftArt() }
            }
            dismiss()
        } label: {
            Text("Close")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.brandBlue)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CreateFlowView()
        .environmentObject(DraftManager())
}
