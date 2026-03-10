import Foundation
import FoundationModels

@Observable
final class AIService {
    static let shared = AIService()

    var isGenerating = false

    private var builderSession: LanguageModelSession?
    private var coachingSession: LanguageModelSession?

    private let builderSystemPrompt = """
    You are a presentation coach helping someone prepare a talk. Your job is to ask \
    clarifying questions one at a time to understand their presentation topic, audience, \
    key messages, and structure. Be conversational and encouraging.

    Ask questions like:
    - What is the main topic or thesis of your presentation?
    - Who is your audience?
    - What are the 2-4 key takeaways you want them to remember?
    - How long is the presentation?
    - Is there a specific call to action?
    - What supporting evidence, stories, or examples do you have?

    Ask ONE question at a time. After each answer, ask a follow-up or move to the next area. \
    When you feel you have enough context (typically after 4-6 exchanges), say exactly \
    "READY_TO_GENERATE" on its own line at the end of your message (you can still include \
    a brief summary before it). Do not ask more than 8 questions total.
    """

    private let coverageSystemPrompt = """
    You are analyzing a live presentation transcript against a planned storyline. \
    Determine which points have been covered, which is currently being discussed, \
    and which have been missed or skipped. Be generous in matching — the speaker \
    won't use exact words from the plan. Focus on semantic meaning.
    """

    // MARK: - Builder Chat

    func startBuilderSession() {
        builderSession = LanguageModelSession(
            instructions: builderSystemPrompt
        )
    }

    func sendBuilderMessage(_ text: String) async throws -> String {
        guard let session = builderSession else {
            startBuilderSession()
            return try await sendBuilderMessage(text)
        }

        isGenerating = true
        defer { isGenerating = false }

        let response = try await session.respond(to: text)
        return response.content
    }

    func streamBuilderMessage(_ text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    if builderSession == nil {
                        startBuilderSession()
                    }
                    guard let session = builderSession else {
                        continuation.finish(throwing: AIServiceError.sessionNotAvailable)
                        return
                    }

                    isGenerating = true
                    var accumulated = ""

                    let stream = session.streamResponse(to: text)
                    for try await partial in stream {
                        let newContent = partial.content
                        if newContent.count > accumulated.count {
                            let delta = String(newContent.dropFirst(accumulated.count))
                            accumulated = newContent
                            continuation.yield(delta)
                        }
                    }

                    isGenerating = false
                    continuation.finish()
                } catch {
                    isGenerating = false
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Storyline Generation

    func generateStoryline(from chatHistory: [ChatMessage]) async throws -> Storyline {
        isGenerating = true
        defer { isGenerating = false }

        let conversationSummary = chatHistory.map { msg in
            let role = msg.role == .user ? "User" : "Coach"
            return "\(role): \(msg.content)"
        }.joined(separator: "\n\n")

        let session = LanguageModelSession(
            instructions: """
            Based on the following conversation between a presentation coach and a speaker, \
            generate a structured presentation storyline. Include an engaging opening hook, \
            clearly ordered talking points with details and key phrases the speaker would use, \
            and a strong closing statement. Each point should have 3-5 key phrases that the \
            speaker is likely to say when covering that topic.
            """
        )

        let response = try await session.respond(
            to: conversationSummary,
            generating: Storyline.self
        )
        return response.content
    }

    // MARK: - Coverage Analysis

    func analyzeCoverage(
        storyline: Storyline,
        transcript: String
    ) async throws -> CoverageAnalysis {
        let storylineDescription = storyline.points.enumerated().map { i, point in
            "[\(i)] \(point.title): \(point.details) (key phrases: \(point.keyPhrases.joined(separator: ", ")))"
        }.joined(separator: "\n")

        let session = LanguageModelSession(
            instructions: coverageSystemPrompt
        )

        let prompt = """
        STORYLINE POINTS:
        \(storylineDescription)

        TRANSCRIPT SO FAR:
        \(transcript)

        Analyze which points have been covered, which is current, and which were missed.
        """

        let response = try await session.respond(
            to: prompt,
            generating: CoverageAnalysis.self
        )
        return response.content
    }

    // MARK: - Quick keyword-based coverage (no AI, instant)

    func keywordCoverage(
        storyline: Storyline,
        transcript: String
    ) -> [Int: PointStatus] {
        let lowerTranscript = transcript.lowercased()
        var statuses: [Int: PointStatus] = [:]
        var lastCoveredIndex = -1

        for (i, point) in storyline.points.enumerated() {
            let matched = point.keyPhrases.filter { phrase in
                lowerTranscript.contains(phrase.lowercased())
            }
            let coverage = Double(matched.count) / Double(max(1, point.keyPhrases.count))

            if coverage >= 0.4 {
                statuses[i] = .covered
                lastCoveredIndex = i
            } else if coverage > 0 {
                statuses[i] = .current
                lastCoveredIndex = i
            } else {
                statuses[i] = i < lastCoveredIndex ? .missed : .upcoming
            }
        }

        return statuses
    }

    func resetSessions() {
        builderSession = nil
        coachingSession = nil
    }
}

enum AIServiceError: LocalizedError {
    case sessionNotAvailable

    var errorDescription: String? {
        switch self {
        case .sessionNotAvailable:
            return "AI session is not available. Make sure Apple Intelligence is enabled."
        }
    }
}
