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
        requestRefresh()
    }

    /// Asks the phone to push its current state. Delivered only when the
    /// phone app is running; the persisted application context covers the
    /// rest of the time.
    func requestRefresh() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            return
        }
        session.sendMessage(["requestRefresh": true], replyHandler: nil)
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
