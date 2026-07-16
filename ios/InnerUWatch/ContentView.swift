import SwiftUI

struct ContentView: View {
    @StateObject private var connector = PhoneConnector()
    @StateObject private var stepCounter = WatchStepCounter()
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
                            tint: .green,
                            title: "Steps",
                            detail: stepsDetail
                        )
                    }

                    NavigationLink {
                        FastingDetailView(connector: connector)
                    } label: {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            CardView(
                                icon: "timer",
                                tint: .orange,
                                title: "Fasting",
                                detail: fastingDetail(at: context.date)
                            )
                        }
                    }

                    NavigationLink {
                        MeditationDetailView(connector: connector)
                    } label: {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            CardView(
                                icon: "leaf.fill",
                                tint: .teal,
                                title: "Meditate",
                                detail: meditationDetail(at: context.date)
                            )
                        }
                    }

                    NavigationLink {
                        MoodDetailView(connector: connector)
                    } label: {
                        CardView(
                            icon: "face.smiling",
                            tint: .purple,
                            title: "Mood",
                            detail: moodDetail
                        )
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 2)
            }
            .navigationTitle("InnerU")
        }
        .onAppear { stepCounter.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                connector.requestRefresh()
                stepCounter.start()
            }
        }
    }

    private var stepsDetail: String {
        let phone = connector.state.stepsToday
        let watch = stepCounter.stepsToday
        let steps = [phone, watch].compactMap { $0 }.max()
        guard let steps else { return "No steps yet today" }
        if let goal = connector.state.stepGoal {
            return "\(steps.formatted()) of \(goal.formatted())"
        }
        return "\(steps.formatted()) steps today"
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
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            tint.opacity(0.16),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}
