import SwiftUI

struct DraftListView: View {
    /// Called when the user picks a draft to resume.
    var onResume: (PostcardDraft, Int, UUID) -> Void

    @EnvironmentObject private var draftManager: DraftManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if draftManager.drafts.isEmpty {
                    ContentUnavailableView(
                        "No Drafts",
                        systemImage: "doc.badge.clock",
                        description: Text("Saved drafts will appear here.")
                    )
                } else {
                    List {
                        ForEach(draftManager.drafts) { snapshot in
                            Button {
                                let (draft, step) = draftManager.load(snapshot)
                                onResume(draft, step, snapshot.id)
                            } label: {
                                DraftRowView(snapshot: snapshot)
                            }
                        }
                        .onDelete { indexSet in
                            indexSet.map { draftManager.drafts[$0].id }
                                    .forEach { draftManager.delete($0) }
                        }
                    }
                }
            }
            .navigationTitle("Drafts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Row

struct DraftRowView: View {
    let snapshot: PostcardDraftSnapshot
    @EnvironmentObject private var draftManager: DraftManager
    @State private var thumbnail: UIImage? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            Group {
                if let img = thumbnail {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(.secondarySystemBackground)
                        .overlay(Image(systemName: "photo")
                            .foregroundColor(.secondary))
                }
            }
            .frame(width: 72, height: 48)
            .clipped()
            .cornerRadius(4)

            // Metadata
            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.title)
                    .font(.body)
                    .foregroundColor(.primary)
                Text(snapshot.stepLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(snapshot.lastModified, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .task {
            thumbnail = draftManager.thumbnail(for: snapshot)
        }
    }
}
