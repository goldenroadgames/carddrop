import Foundation
import Combine
import Supabase

/// Session-level cache for the "Get Inspired" gallery — avoids hitting
/// Supabase every time the sheet is opened. The cache is reused as long as
/// it's within `cacheTTL`; otherwise (or on pull-to-refresh) it refetches
/// from page 1. Purely in-memory: resets on app relaunch, which is fine
/// since this content isn't critical/offline-required.
@MainActor
final class InspireGalleryStore: ObservableObject {
    static let shared = InspireGalleryStore()
    private init() {}

    @Published private(set) var cards: [InspireCard] = []
    @Published private(set) var isLoadingInitial = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMorePages = true

    private var currentPage = 0
    private var lastFetchedAt: Date?
    private let pageSize = 20
    private let cacheTTL: TimeInterval = 20 * 60

    private var isCacheFresh: Bool {
        guard let lastFetchedAt else { return false }
        return Date().timeIntervalSince(lastFetchedAt) < cacheTTL
    }

    /// Called when the gallery opens. Reuses the cache instantly if it's
    /// still fresh; otherwise refetches from page 1 and replaces it.
    func loadInitial(forceRefresh: Bool = false) async {
        if !forceRefresh, isCacheFresh, !cards.isEmpty { return }

        isLoadingInitial = true
        defer { isLoadingInitial = false }

        currentPage = 0
        hasMorePages = true
        let firstPage = await fetchPage(0)
        cards = firstPage
        lastFetchedAt = Date()
        hasMorePages = firstPage.count == pageSize
        syncImageCache()
    }

    /// Keeps the on-disk image cache in step with the table: deletes files for
    /// cards no longer listed and downloads any missing grid thumbnails. Runs
    /// in the background whenever the list is refetched from the server.
    private func syncImageCache() {
        Task.detached(priority: .utility) {
            struct IDRow: Decodable { let card_id: UUID }
            guard let rows: [IDRow] = try? await supabase
                .from("marketing_cards")
                .select("card_id")
                .eq("in_inspire", value: true)
                .range(from: 0, to: 4999)
                .execute()
                .value else { return }
            let ids = rows.map(\.card_id)
            await InspireImageCache.shared.prune(keeping: Set(ids))
            await InspireImageCache.shared.prefetchThumbnails(ids: ids)
        }
    }

    /// Standard infinite-scroll trigger — call from the last few grid items'
    /// `.task`/`.onAppear`.
    func loadMoreIfNeeded(currentItem: InspireCard) async {
        guard hasMorePages, !isLoadingMore else { return }
        guard let index = cards.firstIndex(where: { $0.id == currentItem.id }),
              index >= cards.count - 4 else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        currentPage += 1
        let nextPage = await fetchPage(currentPage)
        cards.append(contentsOf: nextPage)
        hasMorePages = nextPage.count == pageSize
    }

    private func fetchPage(_ page: Int) async -> [InspireCard] {
        let from = page * pageSize
        let to = from + pageSize - 1

        return (try? await supabase
            .from("marketing_cards")
            .select("card_id, sender_id, is_portrait, design_features, added_to_marketing_at")
            .eq("in_inspire", value: true)
            .order("added_to_marketing_at", ascending: false)
            .range(from: from, to: to)
            .execute()
            .value) ?? []
    }
}
