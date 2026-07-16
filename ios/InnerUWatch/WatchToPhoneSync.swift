import Foundation
import WatchConnectivity

/// Single watch→phone channel. Merges the step count and any queued
/// commands into one application-context payload (iOS keeps exactly one
/// pending context, so every sender must go through here or they clobber
/// each other). Commands also go as instant messages when the phone is
/// reachable; the phone dedupes by command id, so double delivery is safe.
final class WatchToPhoneSync {
    static let shared = WatchToPhoneSync()

    private let commandsKey = "pendingPhoneCommands"
    private var lastSentSteps = -1
    private var lastSentAt = Date.distantPast

    private var steps: Int?
    private var stepsDate: String?

    // MARK: Steps

    func reportSteps(_ count: Int) {
        steps = count
        stepsDate = WatchState.todayKey()

        let session = WCSession.default
        guard session.activationState == .activated else { return }

        if session.isReachable {
            session.sendMessage(stepsPayload(), replyHandler: nil)
            lastSentSteps = count
            lastSentAt = Date()
            return
        }

        let dueBySteps = count - lastSentSteps >= 25
        let dueByTime = Date().timeIntervalSince(lastSentAt) >= 300
        guard dueBySteps || dueByTime else { return }
        pushContext()
        lastSentSteps = count
        lastSentAt = Date()
    }

    /// Force-sends the current state regardless of throttles.
    func flush() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(stepsPayload(), replyHandler: nil)
            session.sendMessage(["requestRefresh": true], replyHandler: nil)
        }
        pushContext()
    }

    // MARK: Commands

    /// Queues a command for the phone (start fast, log mood, …) and sends
    /// it immediately when reachable. Queued commands survive the watch
    /// app closing and deliver when the devices reconnect.
    func sendCommand(_ type: String, _ payload: [String: Any] = [:]) {
        var command: [String: Any] = payload
        command["id"] = UUID().uuidString
        command["type"] = type
        command["atMs"] = Int(Date().timeIntervalSince1970 * 1000)

        var pending = storedCommands()
        pending.append(command)
        UserDefaults.standard.set(pending, forKey: commandsKey)

        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(["command": command], replyHandler: nil)
        }
        pushContext()
    }

    // MARK: Payload assembly

    private func stepsPayload() -> [String: Any] {
        var payload: [String: Any] = [:]
        if let steps, let stepsDate {
            payload["watchSteps"] = steps
            payload["watchStepsDate"] = stepsDate
            payload["watchStepsAtMs"] = Int(Date().timeIntervalSince1970 * 1000)
        }
        return payload
    }

    private func storedCommands() -> [[String: Any]] {
        let all = UserDefaults.standard.array(forKey: commandsKey)
            as? [[String: Any]] ?? []
        // Keep only the last 48h; the phone dedupes re-delivered ids.
        let cutoff = Int(Date().timeIntervalSince1970 * 1000) - 48 * 3600 * 1000
        return all.filter { ($0["atMs"] as? Int ?? 0) > cutoff }
    }

    private func pushContext() {
        var payload = stepsPayload()
        let pending = storedCommands()
        if !pending.isEmpty {
            payload["pendingCommands"] = pending
        }
        UserDefaults.standard.set(pending, forKey: commandsKey)
        guard !payload.isEmpty else { return }
        try? WCSession.default.updateApplicationContext(payload)
    }
}
