import SwiftUI
import WatchKit

// MARK: - Shared components

/// Seven-day mini bar chart used by the Steps and Meditate details.
struct WeeklyBars: View {
    let data: [WatchState.DayValue]
    let tint: Color

    var body: some View {
        let peak = max(data.map(\.value).max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(data.enumerated()), id: \.offset) { _, day in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(day.value > 0 ? tint : tint.opacity(0.2))
                        .frame(height: max(3, 28 * CGFloat(day.value) / CGFloat(peak)))
                    Text(WatchState.weekdayLetter(for: day.date))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Steps

struct StepsDetailView: View {
    @ObservedObject var connector: PhoneConnector
    @ObservedObject var stepCounter: WatchStepCounter
    @ObservedObject var trackRecorder: WatchTrackRecorder
    @State private var synced = false

    /// Same formulas as the phone app's step tracker (tracking.dart).
    private static let strideMetersPerStep = 0.67
    private static let kcalPerStep = 0.04
    private static let defaultGoal = 5000

    private var steps: Int {
        [connector.state.stepsToday, stepCounter.stepsToday]
            .compactMap { $0 }
            .max() ?? 0
    }

    private var goal: Int {
        connector.state.stepGoal ?? Self.defaultGoal
    }

    private var distanceKm: Double {
        Double(steps) * Self.strideMetersPerStep / 1000
    }

    private var calories: Int {
        Int((Double(steps) * Self.kcalPerStep).rounded())
    }

    private var distanceText: String {
        String(format: distanceKm >= 10 ? "%.1f km" : "%.2f km", distanceKm)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("\(steps.formatted())")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(InnerUTheme.steps)
                    .contentTransition(.numericText())

                Text("steps today")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Gauge(value: Double(min(steps, goal)), in: 0...Double(max(goal, 1))) {
                    EmptyView()
                }
                .tint(InnerUTheme.steps)
                Text("Goal: \(goal.formatted())")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    statTile(
                        icon: "map.fill",
                        value: distanceText,
                        label: "distance",
                        tint: InnerUTheme.accent
                    )
                    statTile(
                        icon: "flame.fill",
                        value: "\(calories)",
                        label: "kcal",
                        tint: InnerUTheme.fasting
                    )
                }

                if let watch = stepCounter.stepsToday {
                    Label("\(watch.formatted()) from watch sensor", systemImage: "applewatch")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                NavigationLink {
                    TrackMapView(recorder: trackRecorder)
                } label: {
                    Label(
                        trackRecorder.isTracking ? "Tracking…" : "Track walk",
                        systemImage: "map.fill"
                    )
                }
                .tint(InnerUTheme.accent)

                if !connector.state.weeklySteps.isEmpty {
                    sectionHeader("This week")
                    WeeklyBars(data: connector.state.weeklySteps, tint: InnerUTheme.steps)
                    Text("\(weeklyTotal.formatted()) steps · \(weeklyGoalDays) days on goal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if connector.state.stepStreak > 0 || !connector.state.stepAwards.isEmpty {
                    sectionHeader("Awards")
                    if connector.state.stepStreak > 0 {
                        Label("\(connector.state.stepStreak)-day streak",
                              systemImage: "flame.fill")
                            .font(.caption)
                            .foregroundStyle(InnerUTheme.fasting)
                    }
                    ForEach(connector.state.stepAwards, id: \.self) { award in
                        Label(award, systemImage: "medal.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }

                Button {
                    WatchToPhoneSync.shared.flush()
                    synced = true
                } label: {
                    Label(synced ? "Synced" : "Sync to phone", systemImage: "arrow.triangle.2.circlepath")
                }
                .tint(InnerUTheme.steps)
            }
            .padding(.horizontal, 4)
        }
        .containerBackground(InnerUTheme.background, for: .navigation)
        .navigationTitle("Steps")
    }

    private var weeklyTotal: Int {
        connector.state.weeklySteps.reduce(0) { $0 + $1.value }
    }

    private var weeklyGoalDays: Int {
        connector.state.weeklySteps.filter { $0.value >= goal }.count
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    private func statTile(icon: String, value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            InnerUTheme.card.opacity(0.7),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }
}

// MARK: - Fasting

struct FastingDetailView: View {
    @ObservedObject var connector: PhoneConnector
    @State private var goalHours = 16
    @State private var sent = false

    private let goalOptions = [12, 14, 16, 18, 20, 24]

    var body: some View {
        ScrollView {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 8) {
                    if connector.state.fastingActive,
                       let start = connector.state.fastingStart {
                        activeView(start: start, now: context.date)
                    } else {
                        startView
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .containerBackground(InnerUTheme.background, for: .navigation)
        .navigationTitle("Fasting")
        .onChange(of: connector.state.fastingActive) { _, _ in
            sent = false
        }
    }

    private func activeView(start: Date, now: Date) -> some View {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return VStack(spacing: 8) {
            Text(String(format: "%d:%02d:%02d",
                        seconds / 3600, (seconds / 60) % 60, seconds % 60))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(InnerUTheme.fasting)
            Text("fasting")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let goal = connector.state.fastingGoalHours, goal > 0 {
                let total = Double(goal * 3600)
                Gauge(value: min(Double(seconds), total), in: 0...total) {
                    EmptyView()
                }
                .tint(InnerUTheme.fasting)
                Text("Goal: \(goal)h")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button(role: .destructive) {
                WatchToPhoneSync.shared.sendCommand("endFast")
                sent = true
            } label: {
                Label(sent ? "Ending…" : "End Fast", systemImage: "stop.fill")
            }
        }
    }

    private var startView: some View {
        VStack(spacing: 8) {
            Picker("Goal", selection: $goalHours) {
                ForEach(goalOptions, id: \.self) { hours in
                    Text("\(hours) hours").tag(hours)
                }
            }
            .frame(height: 55)

            Button {
                WatchToPhoneSync.shared.sendCommand(
                    "startFast",
                    ["goalHours": goalHours]
                )
                sent = true
            } label: {
                Label(sent ? "Starting…" : "Start Fast", systemImage: "play.fill")
            }
            .tint(InnerUTheme.fasting)

            if sent {
                Text("Sent to phone — timer starts in a moment")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Meditation

/// Runs a meditation session on the watch itself. On completion the
/// phone is told to record it (streak, daily tracker) — queued if the
/// phone is away.
final class WatchMeditationSession: ObservableObject {
    @Published private(set) var endsAt: Date?

    private var totalSeconds = 0
    private var timer: Timer?
    private let endsAtKey = "watchMeditationEndsAt"
    private let totalKey = "watchMeditationTotalSeconds"

    init() {
        let stored = UserDefaults.standard.double(forKey: endsAtKey)
        totalSeconds = UserDefaults.standard.integer(forKey: totalKey)
        if stored > 0 {
            endsAt = Date(timeIntervalSince1970: stored)
            reconcile()
        }
    }

    func start(minutes: Int) {
        totalSeconds = minutes * 60
        let end = Date().addingTimeInterval(Double(totalSeconds))
        endsAt = end
        UserDefaults.standard.set(end.timeIntervalSince1970, forKey: endsAtKey)
        UserDefaults.standard.set(totalSeconds, forKey: totalKey)
        scheduleTimer()
    }

    func cancel() {
        clear()
    }

    /// Completes a session whose end passed while the app was inactive.
    func reconcile() {
        guard let end = endsAt else { return }
        if end <= Date() {
            complete()
        } else {
            scheduleTimer()
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        guard let end = endsAt else { return }
        timer = Timer.scheduledTimer(
            withTimeInterval: max(0.5, end.timeIntervalSinceNow),
            repeats: false
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.complete() }
        }
    }

    private func complete() {
        let seconds = totalSeconds
        clear()
        WatchToPhoneSync.shared.sendCommand(
            "meditationCompleted",
            ["seconds": seconds]
        )
        WKInterfaceDevice.current().play(.success)
    }

    private func clear() {
        timer?.invalidate()
        timer = nil
        endsAt = nil
        UserDefaults.standard.removeObject(forKey: endsAtKey)
        UserDefaults.standard.removeObject(forKey: totalKey)
    }
}

struct MeditationDetailView: View {
    @ObservedObject var connector: PhoneConnector
    @ObservedObject var session: WatchMeditationSession
    @State private var minutes = 10

    private let durationOptions = [5, 10, 15, 20, 30]

    var body: some View {
        ScrollView {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 8) {
                    if let endsAt = session.endsAt, endsAt > context.date {
                        runningView(endsAt: endsAt, now: context.date)
                    } else if connector.state.meditationRunning(at: context.date),
                              let endsAt = connector.state.meditationEndsAt {
                        phoneRunningView(endsAt: endsAt, now: context.date)
                    } else {
                        startView
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .containerBackground(InnerUTheme.background, for: .navigation)
        .navigationTitle("Meditate")
    }

    private func runningView(endsAt: Date, now: Date) -> some View {
        let seconds = max(0, Int(endsAt.timeIntervalSince(now)))
        return VStack(spacing: 8) {
            Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(InnerUTheme.meditate)
            Text("breathe…")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button(role: .destructive) {
                session.cancel()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
        }
    }

    private func phoneRunningView(endsAt: Date, now: Date) -> some View {
        let seconds = max(0, Int(endsAt.timeIntervalSince(now)))
        return VStack(spacing: 8) {
            Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(InnerUTheme.meditate)
            Label("Running on phone", systemImage: "iphone")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var startView: some View {
        VStack(spacing: 8) {
            if connector.state.meditatedToday {
                Label(
                    connector.state.meditationStreak > 1
                        ? "\(connector.state.meditationStreak)-day streak"
                        : "Done today",
                    systemImage: "flame.fill"
                )
                .font(.caption)
                .foregroundStyle(InnerUTheme.fasting)
            }

            Picker("Duration", selection: $minutes) {
                ForEach(durationOptions, id: \.self) { value in
                    Text("\(value) min").tag(value)
                }
            }
            .frame(height: 55)

            Button {
                session.start(minutes: minutes)
            } label: {
                Label("Begin", systemImage: "play.fill")
            }
            .tint(InnerUTheme.meditate)

            if !connector.state.weeklyMeditation.isEmpty {
                Text("This week")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                WeeklyBars(
                    data: connector.state.weeklyMeditation,
                    tint: InnerUTheme.meditate
                )
                Text("\(weeklyMinutes) min · \(weeklyDays) days")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var weeklyMinutes: Int {
        connector.state.weeklyMeditation.reduce(0) { $0 + $1.value }
    }

    private var weeklyDays: Int {
        connector.state.weeklyMeditation.filter { $0.value > 0 }.count
    }
}

// MARK: - Mood

struct MoodDetailView: View {
    @ObservedObject var connector: PhoneConnector
    @State private var loggedMood: String?

    private let moods: [(name: String, emoji: String)] = [
        ("happy", "😊"),
        ("neutral", "😐"),
        ("sad", "😢"),
        ("angry", "😠"),
    ]

    private var currentMood: String? {
        loggedMood ?? connector.state.mood
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let mood = currentMood {
                    Text(emoji(for: mood))
                        .font(.system(size: 36))
                    Text(mood.capitalized)
                        .font(.headline)
                        .foregroundStyle(.white)
                    if loggedMood != nil {
                        Text("Logged from watch ✓")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("How do you feel?")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(moods, id: \.name) { mood in
                        Button {
                            WatchToPhoneSync.shared.sendCommand(
                                "logMood",
                                ["mood": mood.name]
                            )
                            loggedMood = mood.name
                            WKInterfaceDevice.current().play(.click)
                        } label: {
                            VStack(spacing: 2) {
                                Text(mood.emoji).font(.title3)
                                Text(mood.name.capitalized).font(.caption2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                InnerUTheme.card.opacity(
                                    currentMood == mood.name ? 1.0 : 0.6
                                ),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !connector.state.moodLogs.isEmpty {
                    Text("Today's log")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                    ForEach(
                        Array(connector.state.moodLogs.reversed().enumerated()),
                        id: \.offset
                    ) { _, log in
                        HStack {
                            Text(emoji(for: log.mood))
                            Text(log.mood.capitalized)
                                .font(.caption2)
                                .foregroundStyle(.white)
                            Spacer()
                            Text(log.at.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(
                            InnerUTheme.card.opacity(0.5),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .containerBackground(InnerUTheme.background, for: .navigation)
        .navigationTitle("Mood")
    }

    private func emoji(for mood: String) -> String {
        moods.first { $0.name == mood.lowercased() }?.emoji ?? "🙂"
    }
}
