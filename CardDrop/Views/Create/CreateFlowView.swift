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
    @EnvironmentObject private var appSettings: AppSettings

    @State private var isModerating = false
    @State private var moderationFlagged: [String] = []
    @State private var showHardBlockAlert = false
    @State private var showFamilyModeAlert = false
    @State private var showCasualWarningAlert = false
    @State private var showFamilyModeSheet = false

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
                    NicknameStepView(draft: draft, onNext: { currentStep = 1 })
                case 1:
                    PhotoPickerStepView(
                        draft: draft,
                        photoItem: $photoItem,
                        onNext: { currentStep = 2 }
                    )
                case 2:
                    TextOverlayStepView(draft: draft, onNext: { currentStep = 3 })
                case 3:
                    MessageStepView(draft: draft, onNext: {
                        currentStep = 5
                    })
                case 4:
                    InvisibleInkStepView(draft: draft, onNext: { currentStep = 5 })
                case 5:
                    BackOfCardStepView(draft: draft, onNext: { currentStep = 6 })
                case 6:
                    PreviewSendStepView(draft: draft, filteredImage: filteredImage,
                                        originalStatus: originalStatus,
                                        onNext: { currentStep = 7 })
                case 7:
                    SendOptionsView(draft: draft, filteredImage: filteredImage,
                                    originalStatus: originalStatus,
                                    hasDraftSaved: currentDraftID != nil,
                                    onSaveUnsent:    { saveDraft(status: .unsent) },
                                    onSaveSent:      { saveDraft(status: .sent) },
                                    onGoToAddress:   { currentStep = 5 },
                                    onFinish:        { dismiss() },
                                    onSendToSomeoneElse: {
                                        let clone = draft.cloneForNewRecipient()
                                        onSendToSomeoneElse?(clone)
                                        dismiss()
                                    },
                                    onEditCard: {
                                        if originalStatus == .sent {
                                            let clone = draft.cloneForNewRecipient()
                                            onEditCard?(clone)
                                            dismiss()
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
                // Left: step navigation arrows (hidden for immutable sent cards)
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    if originalStatus != .sent {
                    Button { currentStep = prevStep(from: currentStep) } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(currentStep == 0)

                    Button {
                        let next = nextStep(from: currentStep)
                        if currentStep >= 3 && draft.moderationState == .untested {
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
                                    let harassmentOnly = categories.allSatisfy {
                                        ModerationService.harassmentLabels.contains($0)
                                    }
                                    if harassmentOnly {
                                        if appSettings.familyMode {
                                            showFamilyModeAlert = true
                                        } else {
                                            showCasualWarningAlert = true
                                        }
                                    } else {
                                        showHardBlockAlert = true
                                    }
                                }
                            }
                        } else {
                            currentStep = next
                        }
                    } label: {
                        if isModerating {
                            ProgressView()
                        } else {
                            Image(systemName: "chevron.right")
                        }
                    }
                    .disabled(currentStep >= 7 || (currentStep == 0 && !namesFilled) || (currentStep == 1 && !hasStarted) || isModerating)
                    } // end if originalStatus != .sent
                }

                // Right: Close (auto-saves unless opened from a sent card with no changes)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        if hasStarted && (originalStatus == .unsent || isDirty) {
                            saveDraft()
                        }
                        dismiss()
                    }
                }
            }
            .onAppear { recomputeFilteredImage() }
            .onReceive(draft.$composedImage) { _ in recomputeFilteredImage() }
            .onReceive(draft.$filter)        { _ in recomputeFilteredImage() }
            .onChange(of: currentStep)       { _ in updateThumbnail() }

            .onReceive(draft.objectWillChange) { _ in isDirty = true }
            .alert("Content Not Allowed", isPresented: $showHardBlockAlert) {
                Button("Go to Message Step") { currentStep = 3 }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your message was flagged for: \(moderationFlagged.joined(separator: ", ")). Please revise before continuing.")
            }
            .alert("Language Not Allowed in Family Mode", isPresented: $showFamilyModeAlert) {
                Button("Go to Settings") { showFamilyModeSheet = true }
                Button("Go to Message Step") { currentStep = 3 }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your message contains language that's blocked in Family Mode. Turn off Family Mode in Settings to allow more casual language.")
            }
            .alert("That's a Little Spicy", isPresented: $showCasualWarningAlert) {
                Button("Send Anyway") {
                    draft.moderationState = .passed
                    currentStep += 1
                }
                Button("Edit Message") { currentStep = 3 }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your message contains some strong language. You can send it as-is or tone it down — your call.")
            }
            .sheet(isPresented: $showFamilyModeSheet) {
                FamilyModeSettingSheet()
                    .environmentObject(appSettings)
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
                size: frontSize,
                border: draft.border,
                orientation: draft.orientation,
                borderText: draft.borderText,
                borderFontName: draft.borderFontName,
                borderTextColor: draft.borderTextColor
            )
        )
        renderer.proposedSize = ProposedViewSize(frontSize)
        guard let img = renderer.uiImage else { return }
        draftManager.saveDraftFront(img, snapshotID: snapshotID, draft: draft, currentStep: currentStep)
    }

    // MARK: - Filtered image

    private func recomputeFilteredImage() {
        guard let base = draft.composedImage ?? draft.image else { return }
        guard let cgImage = base.cgImage else { return }
        let filter = draft.filter
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
        case 0: return "Names"
        case 1: return "Choose Photo"
        case 2: return "Style It"
        case 3: return "Write Card"
        case 4: return "Invisible Ink"
        case 5: return "Addresses"
        case 6: return "Preview"
        case 7: return "Send"
        default: return "Create"
        }
    }

    private func nextStep(from step: Int) -> Int {
        if step == 3 { return draft.includeBackMessageQR ? 4 : 5 }
        return step + 1
    }

    private func prevStep(from step: Int) -> Int {
        if step == 5 { return draft.includeBackMessageQR ? 4 : 3 }
        return step - 1
    }
}

#Preview {
    CreateFlowView()
        .environmentObject(DraftManager())
}
