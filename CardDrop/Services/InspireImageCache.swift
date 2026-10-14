import SwiftUI
import UIKit

/// On-disk cache for the "Get Inspired" gallery images. Marketing images are
/// never overwritten under the same card id (a changed card gets a new id), so
/// a file is downloaded once per device and then read from disk. Lives in the
/// Caches folder: iOS may clear it, which just means a re-download.
///   thumb  — grid tiles (fetched ahead of time for every listed card)
///   front  — finished card in the deck (fetched when first viewed)
///   before — original photo in the deck (fetched when first viewed)
enum InspireImageKind: String {
    case thumb = "_thumb"
    case front = ""
    case before = "_before"
}

actor InspireImageCache {
    static let shared = InspireImageCache()
    private init() {}

    // Decoded images for this session, so a tile that re-appears doesn't flash
    // a placeholder while the disk read happens.
    nonisolated private static let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 60
        return cache
    }()

    // Own session with no URL cache, so images aren't stored twice.
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("InspireImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func name(_ id: UUID, _ kind: InspireImageKind) -> String {
        "\(id.uuidString.lowercased())\(kind.rawValue).jpg"
    }

    nonisolated static func memoryImage(_ id: UUID, _ kind: InspireImageKind) -> UIImage? {
        memory.object(forKey: name(id, kind) as NSString)
    }

    /// Disk first, then download and save. Returns nil if the file doesn't
    /// exist (e.g. an older card with no "before" photo) or the download fails;
    /// nothing is saved in that case, so a later call tries again.
    func image(_ id: UUID, _ kind: InspireImageKind, from url: URL) async -> UIImage? {
        let name = Self.name(id, kind)
        if let cached = Self.memory.object(forKey: name as NSString) { return cached }

        let file = directory.appendingPathComponent(name)
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            Self.memory.setObject(image, forKey: name as NSString)
            return image
        }

        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data) else { return nil }
        try? data.write(to: file, options: .atomic)
        Self.memory.setObject(image, forKey: name as NSString)
        return image
    }

    /// Downloads any grid thumbnails not already on disk (a few at a time).
    func prefetchThumbnails(ids: [UUID]) async {
        let missing = ids.filter {
            !FileManager.default.fileExists(atPath: directory.appendingPathComponent(Self.name($0, .thumb)).path)
        }
        var index = 0
        while index < missing.count {
            let batch = missing[index..<min(index + 4, missing.count)]
            await withTaskGroup(of: Void.self) { group in
                for id in batch {
                    group.addTask { _ = await self.image(id, .thumb, from: InspireCard.thumbnailURL(forID: id)) }
                }
            }
            index += 4
        }
    }

    /// Deletes cached files for cards that are no longer in the gallery.
    func prune(keeping ids: Set<UUID>) {
        let keep = Set(ids.map { $0.uuidString.lowercased() })
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            // File names are "<36-char uuid><suffix>.jpg".
            let prefix = String(file.lastPathComponent.prefix(36))
            if !keep.contains(prefix) { try? FileManager.default.removeItem(at: file) }
        }
    }
}

/// Drop-in replacement for AsyncImage on Inspire cards: draws `content` with
/// the image once it's available (`nil` while loading), and `failed == true`
/// if it couldn't be loaded.
struct InspireCachedImage<Content: View>: View {
    let card: InspireCard
    let kind: InspireImageKind
    @ViewBuilder let content: (UIImage?, Bool) -> Content

    @State private var image: UIImage?
    @State private var failed = false

    init(card: InspireCard, kind: InspireImageKind,
         @ViewBuilder content: @escaping (UIImage?, Bool) -> Content) {
        self.card = card
        self.kind = kind
        self.content = content
        _image = State(initialValue: InspireImageCache.memoryImage(card.card_id, kind))
    }

    private var url: URL {
        switch kind {
        case .thumb: card.thumbnailURL
        case .front: card.frontURL
        case .before: card.beforeURL
        }
    }

    var body: some View {
        content(image, failed)
            .task(id: "\(card.card_id)-\(kind.rawValue)") {
                if image != nil { return }
                if let loaded = await InspireImageCache.shared.image(card.card_id, kind, from: url) {
                    image = loaded
                } else {
                    failed = true
                }
            }
    }
}
