import SwiftUI

struct StepsDetailView: View {
    @ObservedObject var connector: PhoneConnector
    @ObservedObject var stepCounter: WatchStepCounter

    private var steps: Int? {
        [connector.state.stepsToday, stepCounter.stepsToday]
            .compactMap { $0 }
            .max()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("\((steps ?? 0).formatted())")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)

                Text("steps today")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let goal = connector.state.stepGoal, goal > 0 {
                    Gauge(value: Double(min(steps ?? 0, goal)), in: 0...Double(goal)) {
                        EmptyView()
                    }
                    .tint(.green)
                    Text("Goal: \(goal.formatted())")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let watch = stepCounter.stepsToday {
                    Label("\(watch.formatted()) from watch sensor", systemImage: "applewatch")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Steps")
    }
}

struct FastingDetailView: View {
    @ObservedObject var connector: PhoneConnector

    var body: some View {
        ScrollView {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 8) {
                    if connector.state.fastingActive,
                       let start = connector.state.fastingStart {
                        let seconds = max(0, Int(context.date.timeIntervalSince(start)))
                        Text(String(format: "%d:%02d:%02d",
                                    seconds / 3600, (seconds / 60) % 60, seconds % 60))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                        Text("fasting")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let goal = connector.state.fastingGoalHours, goal > 0 {
                            let total = Double(goal * 3600)
                            Gauge(value: min(Double(seconds), total), in: 0...total) {
                                EmptyView()
                            }
                            .tint(.orange)
                            Text("Goal: \(goal)h")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Image(systemName: "timer")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text("No active fast")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("Start a fast from the phone app")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .navigationTitle("Fasting")
    }
}

struct MeditationDetailView: View {
    @ObservedObject var connector: PhoneConnector

    var body: some View {
        ScrollView {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 8) {
                    if connector.state.meditationRunning(at: context.date),
                       let endsAt = connector.state.meditationEndsAt {
                        let seconds = max(0, Int(endsAt.timeIntervalSince(context.date)))
                        Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(.teal)
                        Text("remaining")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "leaf.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.teal)
                        Text(connector.state.meditatedToday
                             ? "Meditated today"
                             : "Not yet today")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if connector.state.meditationStreak > 0 {
                            Label("\(connector.state.meditationStreak)-day streak",
                                  systemImage: "flame.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .navigationTitle("Meditate")
    }
}

struct MoodDetailView: View {
    @ObservedObject var connector: PhoneConnector

    private var moodEmoji: String {
        switch connector.state.mood?.lowercased() {
        case "happy": return "😊"
        case "sad": return "😢"
        case "angry": return "😠"
        case "anxious": return "😰"
        case "neutral": return "😐"
        case "excited": return "🤩"
        case "tired": return "😴"
        default: return "🙂"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let mood = connector.state.mood {
                    Text(moodEmoji)
                        .font(.system(size: 44))
                    Text(mood.capitalized)
                        .font(.headline)
                    if let at = connector.state.moodAt {
                        Text("Logged at \(at.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "face.smiling")
                        .font(.largeTitle)
                        .foregroundStyle(.purple)
                    Text("No check-in yet")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Log your mood from the phone app")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Mood")
    }
}
