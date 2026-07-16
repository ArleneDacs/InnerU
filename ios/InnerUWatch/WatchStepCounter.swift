import CoreMotion
import Foundation
import WatchConnectivity

/// Counts today's steps using the watch's own motion sensors —
/// independent of the iPhone. The motion chip records all day, so the
/// query includes steps taken while this app was closed.
final class WatchStepCounter: ObservableObject {
    @Published var stepsToday: Int?

    private let pedometer = CMPedometer()

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
        WatchToPhoneSync.shared.reportSteps(steps)
    }

    private func persistForWidget(_ steps: Int) {
        let defaults = UserDefaults(suiteName: SharedStore.appGroupId)
        defaults?.set(steps, forKey: SharedStore.watchStepsKey)
        defaults?.set(WatchState.todayKey(), forKey: SharedStore.watchStepsDateKey)
    }
}

