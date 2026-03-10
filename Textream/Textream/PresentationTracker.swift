import Foundation
import Combine

@Observable
final class PresentationTracker {
    var storyline: Storyline
    var isActive = false

    /// Per-point status derived from keyword matching (instant) and AI analysis (periodic)
    var pointStatuses: [Int: PointStatus] = [:]
    var currentPointIndex: Int = -1
    var suggestion: String = ""
    var transcript: String = ""
    var elapsedTime: TimeInterval = 0

    /// Filler word counts (e.g. "um", "like") from the transcript so far
    var fillerCounts: [String: Int] = [:]

    let transcriber = LiveTranscriber()

    private let ai = AIService.shared
    private var analysisTask: Task<Void, Never>?
    private var elapsedTimer: Timer?
    private var lastAnalyzedLength = 0
    private let analysisThreshold = 80 // chars of new speech before re-analyzing

    init(storyline: Storyline) {
        self.storyline = storyline
        for (i, _) in storyline.points.enumerated() {
            pointStatuses[i] = .upcoming
        }
    }

    func start() {
        isActive = true
        transcript = ""
        fillerCounts = [:]
        lastAnalyzedLength = 0
        elapsedTime = 0

        for (i, _) in storyline.points.enumerated() {
            pointStatuses[i] = .upcoming
        }
        // Show first point as current so user knows what to say and phase advances visibly
        if !storyline.points.isEmpty {
            pointStatuses[0] = .current
            currentPointIndex = 0
        }

        transcriber.onTranscriptUpdate = { [weak self] fullTranscript in
            guard let self, self.isActive else { return }
            self.transcript = fullTranscript
            self.updateFillerCounts(from: fullTranscript)
            self.updateKeywordCoverage()

            let newChars = fullTranscript.count - self.lastAnalyzedLength
            if newChars >= self.analysisThreshold {
                self.scheduleAIAnalysis()
            }
        }

        transcriber.start()

        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.elapsedTime += 1
        }
    }

    func stop() {
        isActive = false
        transcriber.stop()
        analysisTask?.cancel()
        analysisTask = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    // MARK: - Keyword-based instant coverage

    private func updateKeywordCoverage() {
        let statuses = ai.keywordCoverage(storyline: storyline, transcript: transcript)
        for (index, status) in statuses {
            if let existing = pointStatuses[index] {
                // AI analysis results take precedence if already set to covered/missed
                if existing == .upcoming || existing == .current {
                    pointStatuses[index] = status
                }
            } else {
                pointStatuses[index] = status
            }
        }
        // When a point becomes covered, advance the "current" to the next upcoming
        autoAdvanceCurrentIfNeeded()
        updateCurrentPoint()
    }

    /// When the current point is marked covered (by keywords or AI), set next upcoming as current
    private func autoAdvanceCurrentIfNeeded() {
        let current = currentPointIndex
        guard current >= 0, current < storyline.points.count else { return }
        guard pointStatuses[current] == .covered else { return }
        // Find next upcoming point and set it current
        for i in (current + 1)..<storyline.points.count {
            if pointStatuses[i] == .upcoming {
                pointStatuses[i] = .current
                break
            }
        }
    }

    private func updateCurrentPoint() {
        // Find the latest point that is .current, or the first upcoming after covered ones
        var latestCurrent = -1
        for (i, _) in storyline.points.enumerated() {
            if pointStatuses[i] == .current {
                latestCurrent = i
            }
        }
        if latestCurrent >= 0 {
            currentPointIndex = latestCurrent
        }
    }

    // MARK: - Manual advance

    /// Move to the next point manually (mark current as covered, set next as current).
    func advanceToNextPoint() {
        let current = currentPointIndex
        guard current >= 0, current < storyline.points.count else { return }
        pointStatuses[current] = .covered
        for i in (current + 1)..<storyline.points.count {
            if pointStatuses[i] == .upcoming || pointStatuses[i] == .current {
                pointStatuses[i] = .current
                currentPointIndex = i
                return
            }
        }
        currentPointIndex = -1
    }

    // MARK: - Filler word counting

    /// Filler words and variants the speech recogniser might produce (e.g. "umm", "uhm", "eh").
    /// Each label is what we show; forms are all transcript variants we count under that label.
    private static let fillerWordGroups: [(label: String, forms: [String])] = [
        ("um", ["um", "umm", "ummm", "uhm", "umh"]),
        ("uh", ["uh", "uhh", "uhhh"]),
        ("eh", ["eh", "ehm", "ehh"]),
        ("er", ["er", "erm", "err", "errr"]),
        ("ah", ["ah", "ahh", "ahhh"]),
        ("like", ["like"])
    ]

    private static func label(for word: String) -> String? {
        let lower = word.lowercased()
        for group in PresentationTracker.fillerWordGroups {
            if group.forms.contains(lower) { return group.label }
        }
        return nil
    }

    private func updateFillerCounts(from transcript: String) {
        let words = transcript.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        var counts: [String: Int] = [:]
        for word in words {
            if let label = Self.label(for: word) {
                counts[label, default: 0] += 1
            }
        }
        fillerCounts = counts
    }

    // MARK: - AI-powered deep analysis

    private func scheduleAIAnalysis() {
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            guard let self else { return }
            do {
                let analysis = try await self.ai.analyzeCoverage(
                    storyline: self.storyline,
                    transcript: self.transcript
                )

                guard !Task.isCancelled, self.isActive else { return }

                self.lastAnalyzedLength = self.transcript.count
                self.applyAnalysis(analysis)
            } catch {
                // Silently fail -- keyword matching continues working
            }
        }
    }

    private func applyAnalysis(_ analysis: CoverageAnalysis) {
        for index in analysis.coveredIndices {
            if index >= 0 && index < storyline.points.count {
                pointStatuses[index] = .covered
            }
        }
        for index in analysis.missedIndices {
            if index >= 0 && index < storyline.points.count {
                pointStatuses[index] = .missed
            }
        }
        if analysis.currentPointIndex >= 0 && analysis.currentPointIndex < storyline.points.count {
            pointStatuses[analysis.currentPointIndex] = .current
            currentPointIndex = analysis.currentPointIndex
        }
        if !analysis.suggestion.isEmpty {
            suggestion = analysis.suggestion
        }
    }

    // MARK: - Computed helpers

    var coveredPoints: [StorylinePoint] {
        storyline.points.filter { pointStatuses[$0.order] == .covered }
    }

    var missedPoints: [StorylinePoint] {
        storyline.points.filter { pointStatuses[$0.order] == .missed }
    }

    var upcomingPoints: [StorylinePoint] {
        storyline.points.filter { pointStatuses[$0.order] == .upcoming }
    }

    var progress: Double {
        let covered = storyline.points.filter { pointStatuses[$0.order] == .covered }.count
        return Double(covered) / Double(max(1, storyline.points.count))
    }

    var formattedElapsedTime: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
