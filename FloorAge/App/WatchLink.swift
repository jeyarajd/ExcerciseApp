import Foundation
import WatchConnectivity

/// The iPhone's side of the Apple Watch companion: sends the progress summary and the live session
/// to the Watch, and receives remote-control taps and tests done on the Watch.
final class WatchLink: NSObject, ObservableObject {
    static let shared = WatchLink()

    /// The latest remote-control tap, with an id so the same command twice still registers.
    @Published private(set) var command: (WatchCommand, UUID)?
    /// The latest test result from the Watch.
    @Published private(set) var testResult: WatchTestResult?
    /// A paired Watch with Floor Age installed.
    @Published private(set) var isWatchReady = false

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }
    private var lastStatus: SessionStatus?

    func activate() {
        guard let session, session.delegate == nil else { return }
        session.delegate = self
        session.activate()
    }

    func send(_ snapshot: FloorAgeSnapshot) {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let data = snapshot.watchData else { return }
        try? session.updateApplicationContext([WatchKey.snapshot: data])
    }

    /// Live session status for the Watch remote; only sent when something visible changed.
    func send(_ status: SessionStatus?) {
        guard status != lastStatus else { return }
        lastStatus = status
        guard let session, session.activationState == .activated, session.isReachable else { return }
        let payload: [String: Any] = status.flatMap { $0.watchData }.map { [WatchKey.session: $0] } ?? [WatchKey.session: Data()]
        session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
    }

    private func receive(_ message: [String: Any]) {
        DispatchQueue.main.async {
            if let raw = message[WatchKey.command] as? String, let command = WatchCommand(rawValue: raw) {
                self.command = (command, UUID())
            }
            if let result = WatchTestResult.fromWatch(message[WatchKey.result]) {
                self.testResult = result
            }
        }
    }

    private func updateReadiness() {
        let ready = session.map { $0.activationState == .activated && $0.isPaired && $0.isWatchAppInstalled } ?? false
        DispatchQueue.main.async { self.isWatchReady = ready }
    }
}

extension WatchLink: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        updateReadiness()
        if let snapshot = FloorAgeSnapshot.load() { send(snapshot) }
    }

    func sessionWatchStateDidChange(_ session: WCSession) { updateReadiness() }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { receive(message) }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { receive(userInfo) }
}
