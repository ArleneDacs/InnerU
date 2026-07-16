import SwiftUI

struct ContentView: View {
    @StateObject private var connector = PhoneConnector()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("InnerU")
                    .font(.system(size: 24, weight: .bold, design: .rounded))

                Text("Quick check-in")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                card(title: "Steps", detail: stepsDetail)
                fastingCard
                meditationCard
                card(title: "Mood", detail: moodDetail)
            }
            .padding(.horizontal, 4)
        }
    }

    private var stepsDetail: String {
        guard let steps = connector.state.stepsToday else {
            return "No steps yet today"
        }
        let formatted = steps.formatted()
        if let goal = connector.state.stepGoal {
            return "\(formatted) of \(goal.formatted()) steps"
        }
        return "\(formatted) steps today"
    }

    private var fastingCard: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            card(title: "Fasting", detail: fastingDetail(at: context.date))
        }
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

    private var meditationCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            card(title: "Meditate", detail: meditationDetail(at: context.date))
        }
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

    private func card(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.green.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
