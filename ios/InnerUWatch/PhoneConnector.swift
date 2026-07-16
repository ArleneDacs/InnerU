import Foundation
import WatchConnectivity
import WidgetKit

/// Receives application-context snapshots from the iPhone, publishes them
/// to the UI, and persists them for the watch-face widget.
final class PhoneConnector: NSObject, ObservableObject, WCSessionDelegate {
    @Published var state = WatchState.loadFromSharedStore()

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let context = session.receivedApplicationContext
        if !context.isEmpty {
            apply(context)
        }
    }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        apply(applicationContext)
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        apply(message)
    }

    private func apply(_ dict: [String: Any]) {
        DispatchQueue.main.async {
            self.state = WatchState(dict: dict)
            UserDefaults(suiteName: SharedStore.appGroupId)?
                .set(dict, forKey: SharedStore.snapshotKey)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
