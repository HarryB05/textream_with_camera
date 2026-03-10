import SwiftUI

struct StorylineBuilderView: View {
    @Binding var chatMessages: [ChatMessage]
    @Binding var isReadyToGenerate: Bool
    let onStorylineGenerated: (Storyline) -> Void

    @State private var inputText = ""
    @State private var isStreaming = false
    @State private var streamingContent = ""
    @State private var errorMessage: String?
    @State private var isGeneratingStoryline = false
    @State private var didGenerate = false

    private let ai = AIService.shared

    var body: some View {
        VStack(spacing: 0) {
            chatArea
            Divider()
            inputBar
        }
        .onAppear {
            if chatMessages.isEmpty {
                sendInitialGreeting()
            }
        }
    }

    // MARK: - Chat Area

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(chatMessages) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }

                    if isStreaming {
                        ChatBubble(message: ChatMessage(role: .assistant, content: streamingContent.isEmpty ? "..." : streamingContent))
                            .id("streaming")
                    }

                    if isGeneratingStoryline {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Building your storyline...")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .id("generating")
                    }

                    if let error = errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
                .padding(.vertical, 16)
            }
            .onChange(of: chatMessages.count) { _, _ in
                withAnimation {
                    proxy.scrollTo(chatMessages.last?.id, anchor: .bottom)
                }
            }
            .onChange(of: streamingContent) { _, _ in
                withAnimation {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Type your answer...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1...4)
                .onSubmit {
                    if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        sendMessage()
                    }
                }

            if isReadyToGenerate && !didGenerate && !isGeneratingStoryline {
                Button {
                    generateStoryline()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                        Text("Generate")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.purple)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.3))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
    }

    // MARK: - Actions

    private func sendInitialGreeting() {
        ai.startBuilderSession()
        Task {
            do {
                var accumulated = ""
                isStreaming = true
                streamingContent = ""

                let stream = ai.streamBuilderMessage("Hello, I'd like help preparing a presentation.")
                for try await delta in stream {
                    accumulated += delta
                    streamingContent = accumulated
                }

                let finalMessage = ChatMessage(role: .assistant, content: accumulated)
                chatMessages.append(finalMessage)
                isStreaming = false
                streamingContent = ""
            } catch {
                isStreaming = false
                streamingContent = ""
                errorMessage = error.localizedDescription
            }
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: text)
        chatMessages.append(userMessage)
        inputText = ""
        errorMessage = nil

        Task {
            do {
                var accumulated = ""
                isStreaming = true
                streamingContent = ""

                let stream = ai.streamBuilderMessage(text)
                for try await delta in stream {
                    accumulated += delta
                    streamingContent = accumulated
                }

                let finalMessage = ChatMessage(role: .assistant, content: accumulated)
                chatMessages.append(finalMessage)
                isStreaming = false
                streamingContent = ""

                if accumulated.contains("READY_TO_GENERATE") {
                    isReadyToGenerate = true
                }
            } catch {
                isStreaming = false
                streamingContent = ""
                errorMessage = error.localizedDescription
            }
        }
    }

    private func generateStoryline() {
        isGeneratingStoryline = true
        errorMessage = nil

        Task {
            do {
                let generated = try await ai.generateStoryline(from: chatMessages)
                isGeneratingStoryline = false
                didGenerate = true
                onStorylineGenerated(generated)
            } catch {
                isGeneratingStoryline = false
                errorMessage = "Failed to generate storyline: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(displayContent)
                    .font(.system(size: 14))
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(message.role == .user ? Color.accentColor : Color.primary.opacity(0.08))
            )

            if message.role == .assistant { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 16)
    }

    private var displayContent: String {
        message.content.replacingOccurrences(of: "READY_TO_GENERATE", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Flow Layout for key phrases

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(subviews: subviews, containerWidth: proposal.width ?? .infinity)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(subviews: subviews, containerWidth: bounds.width)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(subviews: Subviews, containerWidth: CGFloat) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > containerWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x)
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
