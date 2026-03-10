import SwiftUI

// MARK: - Coaching Overlay (for notch/floating panel)

struct CoachingOverlayView: View {
    @Bindable var tracker: PresentationTracker
    let onStop: () -> Void
    var menuBarHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            if menuBarHeight > 0 {
                HStack {
                    Spacer()
                    Text(tracker.formattedElapsedTime)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.trailing, 12)
                }
                .frame(height: menuBarHeight)
            }

            VStack(spacing: 8) {
                progressBar
                currentPointView
                fillerCountView
                missedPointsView
                suggestionView
            }
            .padding(.horizontal, 14)
            .padding(.top, menuBarHeight > 0 ? 2 : 10)
            .padding(.bottom, 6)

            transcriptView

            bottomBar
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: 3) {
            ForEach(Array(tracker.storyline.points.enumerated()), id: \.offset) { i, _ in
                let status = tracker.pointStatuses[i] ?? .upcoming
                RoundedRectangle(cornerRadius: 2)
                    .fill(colorForStatus(status))
                    .frame(height: 4)
                    .animation(.easeInOut(duration: 0.3), value: status)
            }
        }
    }

    // MARK: - Current Point

    private var currentPointView: some View {
        Group {
            if tracker.currentPointIndex >= 0,
               tracker.currentPointIndex < tracker.storyline.points.count {
                let point = tracker.storyline.points[tracker.currentPointIndex]
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                    Text(point.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        tracker.advanceToNextPoint()
                    } label: {
                        Text("Next")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            } else {
                let nextUpcoming = tracker.upcomingPoints.first
                if let next = nextUpcoming {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("Next: \(next.title)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Live Transcript

    private var transcriptView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                Text(tracker.transcript.isEmpty ? " " : tracker.transcript)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .id("bottom")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: tracker.transcript) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .background(Color.black.opacity(0.3))
    }

    // MARK: - Filler Word Counter

    private var fillerCountView: some View {
        Group {
            let fillers = tracker.fillerCounts.filter { $0.value > 0 }
                .sorted(by: { $0.key < $1.key })
            if !fillers.isEmpty {
                HStack(spacing: 10) {
                    ForEach(fillers, id: \.key) { word, count in
                        Text("\(word): \(count)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.orange.opacity(0.9))
                    }
                }
            }
        }
    }

    // MARK: - Missed Points

    private var missedPointsView: some View {
        Group {
            let missed = tracker.missedPoints
            if !missed.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(missed.prefix(2)) { point in
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                            Text("Missed: \(point.title)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    // MARK: - AI Suggestion

    private var suggestionView: some View {
        Group {
            if !tracker.suggestion.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9))
                        .foregroundStyle(.purple)
                    Text(tracker.suggestion)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.purple.opacity(0.15))
                )
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 6) {
            if let error = tracker.transcriber.error {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundStyle(.red.opacity(0.9))
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                AudioLevelIndicator(levels: tracker.transcriber.audioLevels)
                    .frame(width: 60, height: 20)

                Spacer()

                Text(tracker.formattedElapsedTime)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))

            Button {
                if tracker.transcriber.isListening {
                    tracker.transcriber.stop()
                } else {
                    tracker.transcriber.start()
                }
            } label: {
                Image(systemName: tracker.transcriber.isListening ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tracker.transcriber.isListening ? .yellow.opacity(0.8) : .white.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(0.15))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Button(action: onStop) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(0.15))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }

    private func colorForStatus(_ status: PointStatus) -> Color {
        switch status {
        case .upcoming: return .white.opacity(0.2)
        case .current:  return .blue
        case .covered:  return .green
        case .missed:   return .orange
        }
    }


// MARK: - Floating Coaching Overlay

struct FloatingCoachingOverlayView: View {
    @Bindable var tracker: PresentationTracker
    let onStop: () -> Void

    @State private var appeared = false
    @State private var isDismissing = false

    var body: some View {
        VStack(spacing: 0) {
            CoachingOverlayView(tracker: tracker, onStop: {
                dismissAndStop()
            })
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.black)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.9)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                appeared = true
            }
        }
    }

    private func dismissAndStop() {
        withAnimation(.easeIn(duration: 0.25)) {
            appeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onStop()
        }
    }
}

// MARK: - Audio Level Indicator

struct AudioLevelIndicator: View {
    let levels: [CGFloat]

    var body: some View {
        HStack(alignment: .center, spacing: 1.5) {
            ForEach(Array(levels.suffix(20).enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.green.opacity(0.4 + Double(level) * 0.6))
                    .frame(width: 2, height: max(2, level * 18))
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
    }
}
