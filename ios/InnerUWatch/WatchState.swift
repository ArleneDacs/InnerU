import Foundation

enum SharedStore {
    static let appGroupId = "group.com.valenin.inneru.watch"
    static let snapshotKey = "watchSnapshot"
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
    var mood: String?
    var moodAt: Date?

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
        mood = dict["mood"] as? String
        if let ms = dict["moodAtMs"] as? Double {
            moodAt = Date(timeIntervalSince1970: ms / 1000)
        } else if let ms = dict["moodAtMs"] as? Int {
            moodAt = Date(timeIntervalSince1970: Double(ms) / 1000)
        }
    }

    static func todayKey(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    /// Steps only count if they were recorded today.
    var stepsToday: Int? {
        stepsDate == Self.todayKey() ? steps : nil
    }

    var meditatedToday: Bool {
        meditatedOn == Self.todayKey()
    }

    static func loadFromSharedStore() -> WatchState {
        let dict = UserDefaults(suiteName: SharedStore.appGroupId)?
            .dictionary(forKey: SharedStore.snapshotKey) ?? [:]
        return WatchState(dict: dict)
    }
}
