import Foundation

enum SharedStore {
    static let appGroupId = "group.com.valenin.inneru.watch"
    static let snapshotKey = "watchSnapshot"
    static let watchStepsKey = "watchStepsToday"
    static let watchStepsDateKey = "watchStepsDate"
}

/// Parsed snapshot received from the iPhone. All fields optional —
/// the UI shows placeholders for anything missing.
struct WatchState {
    var steps: Int?
    var stepGoal: Int?
    var stepsDate: String?
    var fastingActive: Bool = false
    var fastingStart: Date?
    var fastingGoalHours: Int?
    var meditatedOn: String?
    var meditationStreak: Int = 0
    var meditationActive: Bool = false
    var meditationEndsAt: Date?
    var mood: String?
    var moodAt: Date?

    struct DayValue {
        let date: String
        let value: Int
    }

    struct MoodLog {
        let mood: String
        let at: Date
    }

    var weeklySteps: [DayValue] = []
    var weeklyMeditation: [DayValue] = []
    var stepStreak: Int = 0
    var stepAwards: [String] = []
    var moodLogs: [MoodLog] = []

    init() {}

    init(dict: [String: Any]) {
        steps = dict["steps"] as? Int
        stepGoal = dict["stepGoal"] as? Int
        stepsDate = dict["stepsDate"] as? String
        fastingActive = dict["fastingActive"] as? Bool ?? false
        if let ms = dict["fastingStartMs"] as? Double {
            fastingStart = Date(timeIntervalSince1970: ms / 1000)
        } else if let ms = dict["fastingStartMs"] as? Int {
            fastingStart = Date(timeIntervalSince1970: Double(ms) / 1000)
        }
        fastingGoalHours = dict["fastingGoalHours"] as? Int
        meditatedOn = dict["meditatedOn"] as? String
        meditationStreak = dict["meditationStreak"] as? Int ?? 0
        meditationActive = dict["meditationActive"] as? Bool ?? false
        if let ms = dict["meditationEndsAtMs"] as? Double {
            meditationEndsAt = Date(timeIntervalSince1970: ms / 1000)
        } else if let ms = dict["meditationEndsAtMs"] as? Int {
            meditationEndsAt = Date(timeIntervalSince1970: Double(ms) / 1000)
        }
        mood = dict["mood"] as? String
        if let ms = dict["moodAtMs"] as? Double {
            moodAt = Date(timeIntervalSince1970: ms / 1000)
        } else if let ms = dict["moodAtMs"] as? Int {
            moodAt = Date(timeIntervalSince1970: Double(ms) / 1000)
        }
        weeklySteps = Self.dayValues(dict["weeklySteps"])
        weeklyMeditation = Self.dayValues(dict["weeklyMeditation"])
        stepStreak = dict["stepStreak"] as? Int ?? 0
        stepAwards = dict["stepAwards"] as? [String] ?? []
        moodLogs = Self.parseMoodLogs(dict["moodLogs"])
    }

    private static func dayValues(_ raw: Any?) -> [DayValue] {
        guard let list = raw as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let date = entry["d"] as? String else { return nil }
            let value = (entry["v"] as? Int) ?? Int(entry["v"] as? Double ?? 0)
            return DayValue(date: date, value: value)
        }
    }

    private static func parseMoodLogs(_ raw: Any?) -> [MoodLog] {
        guard let list = raw as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let mood = entry["m"] as? String else { return nil }
            let ms = (entry["atMs"] as? Double)
                ?? Double(entry["atMs"] as? Int ?? 0)
            guard ms > 0 else { return nil }
            return MoodLog(mood: mood, at: Date(timeIntervalSince1970: ms / 1000))
        }
    }

    /// Short weekday letter for a `yyyy-MM-dd` key ("M", "T", …).
    static func weekdayLetter(for dayKey: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dayKey) else { return "" }
        let letters = ["S", "M", "T", "W", "T", "F", "S"]
        return letters[Calendar.current.component(.weekday, from: date) - 1]
    }

    static func todayKey(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    /// Steps reported by the phone, only if recorded today.
    var stepsToday: Int? {
        stepsDate == Self.todayKey() ? steps : nil
    }

    /// Steps counted by the watch's own sensors, only if from today.
    var watchSteps: Int?
    var watchStepsDate: String?

    var watchStepsToday: Int? {
        watchStepsDate == Self.todayKey() ? watchSteps : nil
    }

    /// What to show: the higher of phone-counted and watch-counted steps.
    /// Both devices count the same walk, so max avoids double counting.
    var displaySteps: Int? {
        switch (stepsToday, watchStepsToday) {
        case let (phone?, watch?): return max(phone, watch)
        case let (phone?, nil): return phone
        case let (nil, watch?): return watch
        default: return nil
        }
    }

    var meditatedToday: Bool {
        meditatedOn == Self.todayKey()
    }

    /// True while a phone meditation session is running and not yet expired.
    func meditationRunning(at now: Date = Date()) -> Bool {
        guard meditationActive, let endsAt = meditationEndsAt else { return false }
        return endsAt > now
    }

    static func loadFromSharedStore() -> WatchState {
        let defaults = UserDefaults(suiteName: SharedStore.appGroupId)
        let dict = defaults?.dictionary(forKey: SharedStore.snapshotKey) ?? [:]
        var state = WatchState(dict: dict)
        if let steps = defaults?.object(forKey: SharedStore.watchStepsKey) as? Int {
            state.watchSteps = steps
            state.watchStepsDate =
                defaults?.string(forKey: SharedStore.watchStepsDateKey)
        }
        return state
    }
}
