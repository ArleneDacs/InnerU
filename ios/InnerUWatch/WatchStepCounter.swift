import CoreMotion
import Foundation
import WatchConnectivity

/// Counts today's steps using the watch's own motion sensors —
/// independent of the iPhone. The motion chip records all day, so the
/// query includes steps taken while this app was closed.
final class WatchStepCounter: ObservableObject {
    @Published var stepsToday: Int?

    private let pedometer = CMPedometer()
    private let reporter = WatchStepReporter()

    func start() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        pedometer.queryPedometerData(from: startOfDay, to: Date()) { [weak self] data, _ in
            guard let steps = data?.numberOfSteps.intValue else { return }
            DispatchQueue.main.async { self?.update(steps) }
        }
        pedometer.startUpdates(from: startOfDay) { [weak self] data, _ in
            guard let steps = data?.numberOfSteps.intValue else { return }
            DispatchQueue.main.async { self?.update(steps) }
        }
    }

    func stop() {
        pedometer.stopUpdates()
    }

    private func update(_ steps: Int) {
        stepsToday = steps
        persistForWidget(steps)
        reporter.report(steps: steps)
    }

    private func persistForWidget(_ steps: Int) {
        let defaults = UserDefaults(suiteName: SharedStore.appGroupId)
        defaults?.set(steps, forKey: SharedStore.watchStepsKey)
        defaults?.set(WatchState.todayKey(), forKey: SharedStore.watchStepsDateKey)
    }
}

/// Sends the watch's step count to the iPhone. Live message when the
/// phone is reachable; otherwise the application context persists the
/// latest count and iOS delivers it when the devices reconnect.
final class WatchStepReporter {
    private var lastSent = -1
    private var lastSentAt = Date.distantPast

    func report(steps: Int) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        let payload: [String: Any] = [
            "watchSteps": steps,
            "watchStepsDate": WatchState.todayKey(),
            "watchStepsAtMs": Int(Date().timeIntervalSince1970 * 1000),
        ]

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil)
            lastSent = steps
            lastSentAt = Date()
            return
        }

        // Not reachable: queue via context, throttled — only the latest
        // count matters and iOS keeps exactly one pending context.
        let dueBySteps = steps - lastSent >= 25
        let dueByTime = Date().timeIntervalSince(lastSentAt) >= 300
        guard dueBySteps || dueByTime else { return }
        try? session.updateApplicationContext(payload)
        lastSent = steps
        lastSentAt = Date()
    }
}
