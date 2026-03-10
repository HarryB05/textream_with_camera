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
    You are analyzing a live presentation transcript against a planned storyline. Your job is to \
    classify each storyline point (by index) as covered, current, or missed.

    Rules:
    - COVERED: The speaker has clearly finished this point. They have said enough about it \
    (semantic meaning, not exact words) and have moved on or wrapped it up. Be generous: if the \
    gist was said, mark it covered even if wording differed.
    - MISSED: The speaker has moved past this point without covering it. For example, they \
    covered point 0 and then talked about point 2; point 1 is missed. Any point that should \
    have been discussed before the current topic but was skipped belongs in missedIndices.
    - CURRENT: The point the speaker is on right now (or the next point they should address \
    if they are between points). Only one point should be current; use currentPointIndex for it.

    Points are in order. Once a point is covered, later points can be current or missed; earlier \
    points that were never addressed are missed. Return coveredIndices, missedIndices, and \
    currentPointIndex accordingly. Give a brief suggestion (suggestion) for what to say next \
    if relevant.
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

    // MARK: - Document Import Generation

    func generateStorylineFromDocument(_ text: String) async throws -> Storyline {
        isGenerating = true
        defer { isGenerating = false }

        let session = LanguageModelSession(
            instructions: """
            You are a presentation coach. Given a document (which may be notes, an article, \
            a markdown outline, or raw text), extract and organize it into a structured \
            presentation storyline. Identify the main theme, break the content into clearly \
            ordered talking points, and create an engaging opening hook and closing statement. \
            Each talking point should have a concise title, detailed notes on what to say, \
            and 3-5 key phrases the speaker would naturally use. Preserve the author's \
            intent and ordering where possible.
            """
        )

        let prompt = """
        DOCUMENT CONTENT:
        \(text.prefix(12000))

        Generate a presentation storyline from this content.
        """

        let response = try await session.respond(
            to: prompt,
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
        STORYLINE POINTS (index, title, details, key phrases):
        \(storylineDescription)

        LIVE TRANSCRIPT:
        \(transcript)

        From the transcript, list which point indices are covered, which are missed (skipped), \
        which single index is current (the one being spoken now or next), and a one-sentence suggestion.
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
