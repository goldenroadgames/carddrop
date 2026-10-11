import SwiftUI

struct LegalDocumentView: View {
    let title: String
    let document: LegalDocumentService.Document

    @State private var blocks: [MarkdownBlock]?
    @State private var lastModified: Date?
    @State private var loadFailed = false

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter
    }()

    var body: some View {
        ScrollView {
            Group {
                if let blocks {
                    VStack(alignment: .leading, spacing: 14) {
                        if let lastModified, document != .help {
                            Text("Last updated: \(Self.displayDateFormatter.string(from: lastModified))")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        ForEach(blocks) { block in
                            blockView(block)
                        }
                    }
                    .textSelection(.enabled)
                } else if loadFailed {
                    VStack(spacing: 8) {
                        Text("Couldn't load \(title).")
                            .font(.subheadline)
                        Button("Try Again") { Task { await load() } }
                    }
                    .foregroundColor(.secondary)
                } else {
                    ProgressView()
                }
            }
            .padding()
            // Clear the bottom Postcards/Profile control so the last lines
            // (the Privacy / Terms links) aren't hidden behind it.
            .padding(.bottom, 96)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            if document == .help && level == 2 {
                // Help's group labels: small blue all-caps, like the website.
                Text(inline(text))
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundColor(.accentColor)
                    .padding(.top, 14)
            } else {
                Text(inline(text))
                    .font(level <= 1 ? .title2.bold() : .title3.bold())
                    .padding(.top, level <= 1 ? 4 : 8)
            }
        case .bullet(let text):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                Text(inline(text))
            }
            .font(.body)
        case .paragraph(let text):
            Text(inline(text))
                .font(.body)
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    private func load() async {
        loadFailed = false
        do {
            let fetched = try await LegalDocumentService.fetch(document)
            var parsed = MarkdownBlock.parse(fetched.text)
            // Drop the doc's leading H1 — it just repeats the nav bar title.
            if case .heading(1, _) = parsed.first {
                parsed.removeFirst()
            }
            blocks = parsed
            lastModified = fetched.lastModified
        } catch {
            loadFailed = true
        }
    }
}

// MARK: - Minimal block-level markdown parser
//
// AttributedString(markdown:) parses inline styling fine but doesn't reliably
// preserve paragraph/heading/list line breaks when rendered through a single
// Text — everything collapses into one run-on paragraph. Parsing block
// structure ourselves and rendering each block as its own Text sidesteps that.
enum MarkdownBlock: Identifiable {
    case heading(level: Int, text: String)
    case bullet(text: String)
    case paragraph(text: String)

    var id: String {
        switch self {
        case .heading(_, let text): return "h-\(text)"
        case .bullet(let text): return "b-\(text)"
        case .paragraph(let text): return "p-\(text)"
        }
    }

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            result.append(.paragraph(text: paragraphLines.joined(separator: " ")))
            paragraphLines = []
        }

        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushParagraph()
            } else if line.hasPrefix("#") {
                flushParagraph()
                let level = line.prefix(while: { $0 == "#" }).count
                let text = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                result.append(.heading(level: level, text: text))
            } else if line.hasPrefix("- ") {
                flushParagraph()
                result.append(.bullet(text: String(line.dropFirst(2))))
            } else {
                paragraphLines.append(line)
            }
        }
        flushParagraph()
        return result
    }
}
