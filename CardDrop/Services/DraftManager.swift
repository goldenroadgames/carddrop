import Combine
import UIKit

class DraftManager: ObservableObject {
    @Published private(set) var drafts: [PostcardDraftSnapshot] = []

    // Set once at app launch and updated on account switch via CardDropApp.
    // Stored as a var so nonisolated functions can derive paths from it.
    private var directory: URL = DraftManager.draftsDirectory(for: "_pending")

    init() {
        // Intentionally empty — data loads when setUser() is called from CardDropApp.
    }

    // MARK: - User lifecycle

    func setUser(_ userID: String) {
        directory = DraftManager.draftsDirectory(for: userID)
        drafts = []
        createDirectoryIfNeeded()
        loadIndex()
    }

    /// Clear in-memory data without touching disk (used on sign-out of named accounts).
    func clearUser() {
        drafts = []
    }

    // MARK: - Public API

    /// Save or overwrite a draft. Returns the draft's UUID (use it to overwrite next time).
    @discardableResult
    func save(draft: PostcardDraft, currentStep: Int, status: CardStatus = .unsent, existingID: UUID? = nil) -> UUID {
        let existing = existingID.flatMap { id in drafts.first { $0.id == id } }
        let snapshot = PostcardDraftSnapshot(
            draft: draft,
            currentStep: currentStep,
            status: status,
            existingID: existingID,
            existingCreatedAt: existing?.createdAt
        )

        saveImageToDisk(draft.image, name: "\(snapshot.id)_original", quality: 1.0)  // full quality — print source

        if let idx = drafts.firstIndex(where: { $0.id == snapshot.id }) {
            drafts[idx] = snapshot
        } else {
            drafts.insert(snapshot, at: 0)
        }
        persistIndex()
        return snapshot.id
    }

    func delete(_ id: UUID) {
        drafts.removeAll { $0.id == id }
        deleteImageFromDisk(name: "\(id)_original")
        deleteImageFromDisk(name: "\(id)_front")
        deleteImageFromDisk(name: "\(id)_back")
        deleteImageFromDisk(name: "\(id)_back6x9")
        persistIndex()
    }

    /// Delete all data for the current user (anonymous sign-out discard path).
    func clearAllData() {
        drafts = []
        try? FileManager.default.removeItem(at: directory)
    }

    /// Reconstruct a live PostcardDraft + the step to resume at.
    func load(_ snapshot: PostcardDraftSnapshot) -> (PostcardDraft, Int) {
        let original = loadImageFromDisk(name: "\(snapshot.id)_original")
        return (snapshot.toPostcardDraft(originalImage: original, composedImage: nil),
                snapshot.currentStep)
    }

    /// Load just the thumbnail image for a draft (front render if available, else original).
    func thumbnail(for snapshot: PostcardDraftSnapshot) -> UIImage? {
        if let img = loadImageFromDisk(name: "\(snapshot.id)_front") { return img }
        if let img = loadImageFromDisk(name: "\(snapshot.id)_original") { return img }
        return nil
    }

    // MARK: - Merge (anonymous → named account)

    /// Copy all drafts from the anonymous user's folder into a named account's folder,
    /// then delete the anonymous folder. Call before signing out.
    func mergeAnonymousData(from anonymousID: String, into targetID: String) {
        let anonDir = DraftManager.draftsDirectory(for: anonymousID)
        let targetDir = DraftManager.draftsDirectory(for: targetID)

        try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        // Load both indexes
        let anonSnapshots = loadIndex(from: anonDir)
        var targetSnapshots = loadIndex(from: targetDir)

        // Copy images and merge index entries (anonymous drafts go to front)
        for snapshot in anonSnapshots {
            for suffix in ["_original", "_front", "_back", "_back6x9"] {
                let src = anonDir.appendingPathComponent("\(snapshot.id)\(suffix).jpg")
                let dst = targetDir.appendingPathComponent("\(snapshot.id)\(suffix).jpg")
                try? FileManager.default.copyItem(at: src, to: dst)
            }
            targetSnapshots.insert(snapshot, at: 0)
        }

        if let data = try? JSONEncoder().encode(targetSnapshots) {
            try? data.write(to: targetDir.appendingPathComponent("index.json"), options: .atomic)
        }

        // Clean up anonymous folder
        try? FileManager.default.removeItem(at: anonDir)
        drafts = []
    }

    // MARK: - Storage helpers

    static func draftsDirectory(for userID: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("drafts/\(userID)", isDirectory: true)
    }

    private func createDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func persistIndex() {
        guard let data = try? JSONEncoder().encode(drafts) else { return }
        try? data.write(to: directory.appendingPathComponent("index.json"), options: .atomic)
    }

    private func loadIndex() {
        drafts = loadIndex(from: directory)
    }

    private func loadIndex(from dir: URL) -> [PostcardDraftSnapshot] {
        let url = dir.appendingPathComponent("index.json")
        guard let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode([PostcardDraftSnapshot].self, from: data)
        else { return [] }
        return saved
    }

    private func saveImageToDisk(_ image: UIImage?, name: String, quality: CGFloat = 0.75) {
        guard let image, let data = image.jpegData(compressionQuality: quality) else { return }
        try? data.write(to: directory.appendingPathComponent("\(name).jpg"), options: .atomic)
    }

    func loadImageFromDisk(name: String) -> UIImage? {
        let url = directory.appendingPathComponent("\(name).jpg")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func loadImageDataFromDisk(name: String) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent("\(name).jpg"))
    }

    func loadFrontData(for cardID: UUID) -> Data? {
        loadImageDataFromDisk(name: "\(cardID.uuidString)_front")
    }

    func loadBackData(for cardID: UUID) -> Data? {
        loadImageDataFromDisk(name: "\(cardID.uuidString)_back")
    }

    func loadBack6x9Data(for cardID: UUID) -> Data? {
        loadImageDataFromDisk(name: "\(cardID.uuidString)_back6x9")
    }

    @MainActor
    func restoreFromServer(cardID: UUID, recipientName: String, sentAt: Date, isLandscape: Bool) {
        guard !drafts.contains(where: { $0.cardID == cardID }) else { return }
        var snapshot = PostcardDraftSnapshot.makeRestored(
            cardID: cardID,
            recipientName: recipientName,
            sentAt: sentAt,
            isLandscape: isLandscape
        )
        drafts.append(snapshot)
        persistIndex()
    }

    func saveFront(_ image: UIImage, cardID: UUID) {
        saveImageToDisk(image, name: "\(cardID.uuidString)_front", quality: 0.88)
    }

    /// Rebuilds the persisted snapshot fresh from the live draft (preserving
    /// identity/createdAt/status) rather than only bumping `lastModified` —
    /// otherwise fields changed since the last full `save(draft:...)` (text
    /// overlays, QR overlays, etc.) get silently frozen at their prior state
    /// every time this thumbnail-only path runs.
    func saveDraftFront(_ image: UIImage, snapshotID: UUID, draft: PostcardDraft, currentStep: Int) {
        saveImageToDisk(image, name: "\(snapshotID)_front", quality: 0.88)
        if let idx = drafts.firstIndex(where: { $0.id == snapshotID }) {
            let existing = drafts[idx]
            drafts[idx] = PostcardDraftSnapshot(
                draft: draft,
                currentStep: currentStep,
                status: existing.status,
                existingID: existing.id,
                existingCreatedAt: existing.createdAt
            )
            persistIndex()
        }
    }

    func loadFront(for cardID: UUID) -> UIImage? {
        loadImageFromDisk(name: "\(cardID.uuidString)_front")
    }

    func saveBack(_ image: UIImage, cardID: UUID) {
        saveImageToDisk(image, name: "\(cardID.uuidString)_back", quality: 0.88)
    }

    func loadBack(for cardID: UUID) -> UIImage? {
        loadImageFromDisk(name: "\(cardID.uuidString)_back")
    }

    func saveBack6x9(_ image: UIImage, cardID: UUID) {
        saveImageToDisk(image, name: "\(cardID.uuidString)_back6x9", quality: 0.88)
    }

    func loadBack6x9(for cardID: UUID) -> UIImage? {
        loadImageFromDisk(name: "\(cardID.uuidString)_back6x9")
    }

    private func deleteImageFromDisk(name: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(name).jpg"))
    }
}
