import SwiftUI
import WidgetKit

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let state: WatchState
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, state: WatchState())
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (SnapshotEntry) -> Void
    ) {
        completion(SnapshotEntry(date: .now, state: .loadFromSharedStore()))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<SnapshotEntry>) -> Void
    ) {
        let state = WatchState.loadFromSharedStore()
        var entries = [SnapshotEntry(date: .now, state: state)]
        if state.fastingActive || state.meditationRunning() {
            // Tick the countdown/elapsed line once a minute for 30 minutes.
            for minute in 1...30 {
                entries.append(SnapshotEntry(
                    date: .now.addingTimeInterval(Double(minute) * 60),
                    state: state
                ))
            }
        }
        let refresh = Date.now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

struct InnerUWidgetView: View {
    var entry: SnapshotEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("InnerU")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.green)
            Text(stepsLine)
                .font(.system(size: 13, weight: .medium))
            Text(bottomLine)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.clear }
    }

    private var stepsLine: String {
        guard let steps = entry.state.stepsToday else { return "No steps yet" }
        return "\(steps.formatted()) steps"
    }

    private var bottomLine: String {
        if entry.state.meditationRunning(at: entry.date),
           let endsAt = entry.state.meditationEndsAt {
            let minutes = max(1, Int(endsAt.timeIntervalSince(entry.date)) / 60)
            return "Meditating · \(minutes)m left"
        }
        if entry.state.fastingActive, let start = entry.state.fastingStart {
            let minutes = max(0, Int(entry.date.timeIntervalSince(start)) / 60)
            return "Fasting \(minutes / 60)h \(minutes % 60)m"
        }
        if entry.state.meditatedToday {
            let streak = entry.state.meditationStreak
            return streak > 1 ? "Meditated · \(streak)-day streak" : "Meditated today"
        }
        return "No meditation yet"
    }
}

@main
struct InnerUWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "InnerUWatchWidget",
            provider: SnapshotProvider()
        ) { entry in
            InnerUWidgetView(entry: entry)
        }
        .configurationDisplayName("InnerU")
        .description("Steps, fasting, and meditation at a glance.")
        .supportedFamilies([.accessoryRectangular])
    }
}
