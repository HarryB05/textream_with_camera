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
        lastAnalyzedLength = 0
        elapsedTime = 0

        for (i, _) in storyline.points.enumerated() {
            pointStatuses[i] = .upcoming
        }

        transcriber.onTranscriptUpdate = { [weak self] fullTranscript in
            guard let self, self.isActive else { return }
            self.transcript = fullTranscript
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
        updateCurrentPoint()
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
