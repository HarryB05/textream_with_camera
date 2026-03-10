import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct StorylineListView: View {
    @Bindable var store: StorylineStore
    @Binding var selectedID: UUID?
    @Binding var isCreatingNew: Bool
    let onImportGenerated: (Storyline) -> Void

    @State private var isImporting = false
    @State private var isGeneratingFromFile = false
    @State private var importError: String?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedID) {
                if store.storylines.isEmpty && !isCreatingNew {
                    emptyState
                }

                ForEach(store.storylines) { saved in
                    storylineRow(saved)
                        .tag(saved.id)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                deleteStoryline(saved.id)
                            }
                        }
                }
                .onDelete { offsets in
                    for offset in offsets {
                        let id = store.storylines[offset].id
                        deleteStoryline(id)
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selectedID) { _, newID in
                if newID != nil {
                    isCreatingNew = false
                }
            }

            Divider()

            bottomBar
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.plainText, .pdf],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .overlay {
            if isGeneratingFromFile {
                generatingOverlay
            }
        }
    }

    // MARK: - Row

    private func storylineRow(_ saved: SavedStoryline) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(saved.storyline.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

            HStack(spacing: 8) {
                Text("\(saved.storyline.points.count) points")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text(Self.dateFormatter.string(from: saved.updatedAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No storylines yet")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
            Text("Create one from chat or import a file.")
                .font(.system(size: 11))
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowSeparator(.hidden)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let error = importError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
            }

            HStack(spacing: 8) {
                Button {
                    selectedID = nil
                    isCreatingNew = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.bubble")
                            .font(.system(size: 12))
                        Text("New from Chat")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                Spacer()

                Button {
                    importError = nil
                    isImporting = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 12))
                        Text("Import")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Generating Overlay

    private var generatingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("Generating outline from file...")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - File Import

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            extractTextAndGenerate(from: url)
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func extractTextAndGenerate(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            importError = "Unable to access the file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let text: String
        if url.pathExtension.lowercased() == "pdf" {
            guard let doc = PDFDocument(url: url), let content = doc.string, !content.isEmpty else {
                importError = "Could not extract text from PDF."
                return
            }
            text = content
        } else {
            guard let content = try? String(contentsOf: url, encoding: .utf8), !content.isEmpty else {
                importError = "Could not read file contents."
                return
            }
            text = content
        }

        isGeneratingFromFile = true
        importError = nil

        Task {
            do {
                let storyline = try await AIService.shared.generateStorylineFromDocument(text)
                await MainActor.run {
                    isGeneratingFromFile = false
                    onImportGenerated(storyline)
                }
            } catch {
                await MainActor.run {
                    isGeneratingFromFile = false
                    importError = "Generation failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Delete

    private func deleteStoryline(_ id: UUID) {
        if selectedID == id {
            selectedID = nil
        }
        store.delete(id)
    }
}
