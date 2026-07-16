import SwiftUI

/// Colors matched to the InnerU phone app's dark-navy dashboard.
enum InnerUTheme {
    static let background = LinearGradient(
        colors: [
            Color(red: 0.04, green: 0.07, blue: 0.15),
            Color(red: 0.07, green: 0.11, blue: 0.22),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    static let card = Color(red: 0.11, green: 0.17, blue: 0.30)
    static let accent = Color(red: 0.45, green: 0.72, blue: 1.0)
    static let steps = Color(red: 0.38, green: 0.85, blue: 0.56)
    static let fasting = Color(red: 1.0, green: 0.62, blue: 0.29)
    static let meditate = Color(red: 0.42, green: 0.86, blue: 0.83)
    static let mood = Color(red: 0.98, green: 0.48, blue: 0.60)
}

struct ContentView: View {
    @StateObject private var connector = PhoneConnector()
    @StateObject private var stepCounter = WatchStepCounter()
    @StateObject private var meditationSession = WatchMeditationSession()
    @StateObject private var trackRecorder = WatchTrackRecorder()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    NavigationLink {
                        StepsDetailView(connector: connector, stepCounter: stepCounter)
                    } label: {
                        CardView(
                            icon: "figure.walk",
                            tint: InnerUTheme.steps,
                            title: "Steps",
                            detail: stepsDetail
                        )
                    }

                    NavigationLink {
                        TrackMapView(recorder: trackRecorder)
                    } label: {
                        CardView(
                            icon: "map.fill",
                            tint: InnerUTheme.accent,
                            title: "Track",
                            detail: trackDetail
                        )
                    }

                    NavigationLink {
                        FastingDetailView(connector: connector)
                    } label: {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            CardView(
                                icon: "timer",
                                tint: InnerUTheme.fasting,
                                title: "Fasting",
                                detail: fastingDetail(at: context.date)
                            )
                        }
                    }

                    NavigationLink {
                        MeditationDetailView(
                            connector: connector,
                            session: meditationSession
                        )
                    } label: {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            CardView(
                                icon: "leaf.fill",
                                tint: InnerUTheme.meditate,
                                title: "Meditate",
                                detail: meditationDetail(at: context.date)
                            )
                        }
                    }

                    NavigationLink {
                        MoodDetailView(connector: connector)
                    } label: {
                        CardView(
                            icon: "heart.fill",
                            tint: InnerUTheme.mood,
                            title: "Mood",
                            detail: moodDetail
                        )
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 2)
            }
            .containerBackground(InnerUTheme.background, for: .navigation)
            .navigationTitle {
                Text("InnerU")
                    .foregroundStyle(InnerUTheme.accent)
            }
        }
        .onAppear { stepCounter.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                connector.requestRefresh()
                stepCounter.start()
                meditationSession.reconcile()
            }
        }
    }

    private var stepsDetail: String {
        let phone = connector.state.stepsToday
        let watch = stepCounter.stepsToday
        let steps = [phone, watch].compactMap { $0 }.max()
        guard let steps else { return "No steps yet today" }
        let goal = connector.state.stepGoal ?? 5000
        let km = Double(steps) * 0.67 / 1000
        return String(
            format: "%@ of %@ · %.2f km",
            steps.formatted(), goal.formatted(), km
        )
    }

    private var trackDetail: String {
        guard trackRecorder.isTracking else { return "Record a walk route" }
        let km = trackRecorder.distanceMeters / 1000
        return String(format: "Tracking · %.2f km", km)
    }

    private func fastingDetail(at now: Date) -> String {
        guard connector.state.fastingActive,
              let start = connector.state.fastingStart else {
            return "No active fast"
        }
        let minutes = max(0, Int(now.timeIntervalSince(start)) / 60)
        let elapsed = "\(minutes / 60)h \(minutes % 60)m"
        if let goal = connector.state.fastingGoalHours {
            return "\(elapsed) of \(goal)h"
        }
        return "\(elapsed) elapsed"
    }

    private func meditationDetail(at now: Date) -> String {
        if let endsAt = meditationSession.endsAt, endsAt > now {
            let seconds = max(0, Int(endsAt.timeIntervalSince(now)))
            return String(format: "%d:%02d left · on watch", seconds / 60, seconds % 60)
        }
        if connector.state.meditationRunning(at: now),
           let endsAt = connector.state.meditationEndsAt {
            let seconds = max(0, Int(endsAt.timeIntervalSince(now)))
            return String(format: "%d:%02d left", seconds / 60, seconds % 60)
        }
        guard connector.state.meditatedToday else {
            return "Not yet today"
        }
        let streak = connector.state.meditationStreak
        return streak > 1 ? "Done today · \(streak)-day streak" : "Done today"
    }

    private var moodDetail: String {
        guard let mood = connector.state.mood else {
            return "No check-in yet"
        }
        var detail = mood.capitalized
        if let at = connector.state.moodAt {
            detail += " · \(at.formatted(date: .omitted, time: .shortened))"
        }
        return detail
    }
}

struct CardView: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            InnerUTheme.card.opacity(0.85),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}
