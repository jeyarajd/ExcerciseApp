import CoreMotion
import WatchKit

/// Wrist movement for the chair stand, kept running with the wrist lowered by an extended runtime
/// session (physical therapy), so the screen can sleep while the arms are crossed.
final class WristMotionSensor: NSObject, ObservableObject, WKExtendedRuntimeSessionDelegate {
    @Published private(set) var stands = 0

    private let motion = CMMotionManager()
    private var counter = WristRepCounter()
    private var runtime: WKExtendedRuntimeSession?
    private var startTime: TimeInterval = 0

    var isAvailable: Bool { motion.isDeviceMotionAvailable }

    func start() {
        stands = 0
        counter = WristRepCounter()
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        session.start()
        runtime = session
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 50
        startTime = ProcessInfo.processInfo.systemUptime
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            // Upward acceleration: the part of the movement pointing away from gravity.
            let g = data.gravity, a = data.userAcceleration
            let up = -(a.x * g.x + a.y * g.y + a.z * g.z)
            if self.counter.add(verticalAcceleration: up, at: data.timestamp - self.startTime) {
                self.stands = self.counter.count
                WKInterfaceDevice.current().play(.click)
            }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        runtime?.invalidate()
        runtime = nil
    }

    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}
    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}
    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                                didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {}
}
