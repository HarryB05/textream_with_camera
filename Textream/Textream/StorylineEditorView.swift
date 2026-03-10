import SwiftUI
import UniformTypeIdentifiers

struct StorylineEditorView: View {
    @Binding var saved: SavedStoryline
    let onSave: (SavedStoryline) -> Void
    let onStartPresenting: () -> Void

    @State private var newPhraseText: [Int: String] = [:]
    @State private var draggingPointIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    titleSection
                    openingHookSection
                    pointsList
                    addPointButton
                    closingSection
                }
                .padding(20)
            }

            Divider()

            HStack {
                Text("\(saved.storyline.points.count) points")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)

                Spacer()

                Button {
                    onStartPresenting()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14))
                        Text("Start Presenting")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(saved.storyline.points.isEmpty)
            }
            .padding(16)
        }
    }

    // MARK: - Title

    private var titleSection: some View {
        TextField("Presentation Title", text: $saved.storyline.title)
            .font(.system(size: 20, weight: .bold))
            .textFieldStyle(.plain)
            .onChange(of: saved.storyline.title) { _, _ in commitEdit() }
    }

    // MARK: - Opening Hook

    private var openingHookSection: some View {
        GroupBox {
            TextEditor(text: $saved.storyline.openingHook)
                .font(.system(size: 13))
                .frame(minHeight: 40)
                .scrollContentBackground(.hidden)
                .onChange(of: saved.storyline.openingHook) { _, _ in commitEdit() }
        } label: {
            Label("Opening Hook", systemImage: "play.circle")
                .font(.system(size: 12, weight: .semibold))
        }
    }

    // MARK: - Points List

    private var pointsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Talking Points")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(saved.storyline.points.enumerated()), id: \.element.id) { index, _ in
                pointEditor(at: index)
                    .opacity(draggingPointIndex == index ? 0.4 : 1)
                    .onDrag {
                        draggingPointIndex = index
                        return NSItemProvider(object: "\(index)" as NSString)
                    }
                    .onDrop(of: [.text], delegate: PointDropDelegate(
                        destinationIndex: index,
                        draggingIndex: $draggingPointIndex,
                        points: $saved.storyline.points,
                        onReorder: { commitEdit() }
                    ))
            }
        }
    }

    private func pointEditor(at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.accentColor)
                    .clipShape(Circle())

                TextField("Point title", text: $saved.storyline.points[index].title)
                    .font(.system(size: 14, weight: .semibold))
                    .textFieldStyle(.plain)
                    .onChange(of: saved.storyline.points[index].title) { _, _ in commitEdit() }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        deletePoint(at: index)
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            TextEditor(text: $saved.storyline.points[index].details)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(minHeight: 30)
                .scrollContentBackground(.hidden)
                .onChange(of: saved.storyline.points[index].details) { _, _ in commitEdit() }

            keyPhrasesEditor(at: index)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.03))
        )
    }

    // MARK: - Key Phrases

    private func keyPhrasesEditor(at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 4) {
                ForEach(Array(saved.storyline.points[index].keyPhrases.enumerated()), id: \.offset) { phraseIdx, phrase in
                    HStack(spacing: 4) {
                        Text(phrase)
                            .font(.system(size: 11))
                        Button {
                            removePhrase(at: phraseIdx, pointIndex: index)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Capsule())
                }
            }

            HStack(spacing: 6) {
                TextField("Add phrase...", text: phraseBinding(for: index))
                    .font(.system(size: 11))
                    .textFieldStyle(.plain)
                    .frame(maxWidth: 150)
                    .onSubmit {
                        addPhrase(at: index)
                    }

                Button {
                    addPhrase(at: index)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentColor.opacity(0.6))
                }
                .buttonStyle(.plain)
                .disabled((newPhraseText[index] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func phraseBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { newPhraseText[index] ?? "" },
            set: { newPhraseText[index] = $0 }
        )
    }

    private func addPhrase(at index: Int) {
        let text = (newPhraseText[index] ?? "").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        saved.storyline.points[index].keyPhrases.append(text)
        newPhraseText[index] = ""
        commitEdit()
    }

    private func removePhrase(at phraseIndex: Int, pointIndex: Int) {
        saved.storyline.points[pointIndex].keyPhrases.remove(at: phraseIndex)
        commitEdit()
    }

    // MARK: - Add / Delete Points

    private var addPointButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                let newOrder = saved.storyline.points.count
                let point = StorylinePoint(
                    title: "New Point",
                    details: "",
                    keyPhrases: [],
                    order: newOrder
                )
                saved.storyline.points.append(point)
                commitEdit()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 13))
                Text("Add Point")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Color.accentColor)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func deletePoint(at index: Int) {
        saved.storyline.points.remove(at: index)
        reindexPoints()
        commitEdit()
    }

    // MARK: - Helpers

    private func reindexPoints() {
        for i in saved.storyline.points.indices {
            saved.storyline.points[i].order = i
        }
    }

    private func commitEdit() {
        onSave(saved)
    }

    // MARK: - Closing

    private var closingSection: some View {
        GroupBox {
            TextEditor(text: $saved.storyline.closingStatement)
                .font(.system(size: 13))
                .frame(minHeight: 40)
                .scrollContentBackground(.hidden)
                .onChange(of: saved.storyline.closingStatement) { _, _ in commitEdit() }
        } label: {
            Label("Closing Statement", systemImage: "flag.checkered")
                .font(.system(size: 12, weight: .semibold))
        }
    }
}

// MARK: - Drag & Drop Delegate

struct PointDropDelegate: DropDelegate {
    let destinationIndex: Int
    @Binding var draggingIndex: Int?
    @Binding var points: [StorylinePoint]
    let onReorder: () -> Void

    func performDrop(info: DropInfo) -> Bool {
        draggingIndex = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let from = draggingIndex, from != destinationIndex else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            points.move(fromOffsets: IndexSet(integer: from), toOffset: destinationIndex > from ? destinationIndex + 1 : destinationIndex)
            for i in points.indices {
                points[i].order = i
            }
            draggingIndex = destinationIndex
        }
        onReorder()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
