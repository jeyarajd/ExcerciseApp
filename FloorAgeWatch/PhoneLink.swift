import Foundation
import WatchConnectivity

/// The Watch's side of the link to the iPhone: receives the progress summary and the live session,
/// and sends remote taps and test results.
final class PhoneLink: NSObject, ObservableObject {
    @Published private(set) var snapshot: FloorAgeSnapshot?
    @Published private(set) var session: SessionStatus?

    private let key = "lastSnapshot"

    override init() {
        super.init()
        snapshot = FloorAgeSnapshot.load(from: .standard)
    }

    func activate() {
        guard WCSession.isSupported(), WCSession.default.delegate == nil else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ command: WatchCommand) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage([WatchKey.command: command.rawValue], replyHandler: nil, errorHandler: nil)
    }

    /// Sends a test result now if the iPhone is reachable, otherwise queues it for later.
    func send(_ result: WatchTestResult) {
        guard let data = result.watchData else { return }
        let payload = [WatchKey.result: data]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil) { _ in WCSession.default.transferUserInfo(payload) }
        } else {
            WCSession.default.transferUserInfo(payload)
        }
    }

    private func receive(_ values: [String: Any]) {
        DispatchQueue.main.async {
            if let snapshot = FloorAgeSnapshot.fromWatch(values[WatchKey.snapshot]) {
                self.snapshot = snapshot
                snapshot.save(to: .standard)
            }
            if let raw = values[WatchKey.session] as? Data {
                self.session = raw.isEmpty ? nil : SessionStatus.fromWatch(raw)
            }
        }
    }
}

extension PhoneLink: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        receive(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { receive(applicationContext) }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { receive(message) }

    func sessionReachabilityDidChange(_ session: WCSession) {
        if !session.isReachable { DispatchQueue.main.async { self.session = nil } }
    }
}
