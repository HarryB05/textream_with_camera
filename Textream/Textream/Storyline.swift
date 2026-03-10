import Foundation
import FoundationModels

// MARK: - Storyline Data Model

@Generable
struct StorylinePoint: Identifiable, Codable, Hashable {
    @Guide(description: "A short title for this talking point")
    var title: String
    @Guide(description: "Detailed notes about what to say for this point")
    var details: String
    @Guide(description: "Key words and phrases the speaker is likely to say when covering this point")
    var keyPhrases: [String]
    @Guide(description: "Order index of this point in the storyline, starting from 0")
    var order: Int

    var id: String { "\(order)-\(title)" }
}

@Generable
struct Storyline: Codable {
    @Guide(description: "The title of the presentation")
    var title: String
    @Guide(description: "An engaging opening hook to start the presentation")
    var openingHook: String
    @Guide(description: "The ordered list of talking points")
    var points: [StorylinePoint]
    @Guide(description: "A strong closing statement to end the presentation")
    var closingStatement: String
}

// MARK: - Coverage Analysis

enum PointStatus: String, Codable {
    case upcoming
    case current
    case covered
    case missed
}

@Generable
struct CoverageAnalysis: Codable {
    @Guide(description: "Index of the point currently being discussed, or -1 if between points")
    var currentPointIndex: Int
    @Guide(description: "Indices of points that have been adequately covered")
    var coveredIndices: [Int]
    @Guide(description: "Indices of points that were skipped or insufficiently covered")
    var missedIndices: [Int]
    @Guide(description: "A brief, encouraging suggestion for what to mention next (1 sentence max)")
    var suggestion: String
}

// MARK: - Saved Storyline (persistence wrapper)

struct SavedStoryline: Identifiable, Codable {
    let id: UUID
    var storyline: Storyline
    var createdAt: Date
    var updatedAt: Date

    init(storyline: Storyline, id: UUID = UUID(), createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.storyline = storyline
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Chat Message

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    var content: String
    let timestamp = Date()

    enum Role {
        case user
        case assistant
    }
}
