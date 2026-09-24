import Foundation

/// Counts chair stands from an Apple Watch on the wrist, arms crossed on the chest so the wrist
/// rises and falls with the body.
///
/// Feed it vertical acceleration (in g, gravity removed, up positive). Standing up pushes up then
/// brakes at the top (+ then −); sitting down drops then lands (− then +). A stand is counted on a
/// clear upward push followed by the braking dip. The landing jolt that follows sitting never
/// counts on its own, because it isn't followed by a dip in the right time window.
struct WristRepCounter {
    static let threshold = 0.12
    static let minRise: TimeInterval = 0.2
    static let maxRise: TimeInterval = 1.6
    static let minBetween: TimeInterval = 1.0

    private(set) var count = 0
    private var filtered: Double?
    private var previous: (t: TimeInterval, a: Double)?
    private var beforePrevious: Double?
    private var lastPush: TimeInterval?
    private var lastCount: TimeInterval = -.infinity

    /// Feeds one sample. Returns true when it completes a stand.
    mutating func add(verticalAcceleration a: Double, at t: TimeInterval) -> Bool {
        // A light low-pass filter smooths the wrist's small shakes.
        let smooth = filtered.map { $0 + 0.3 * (a - $0) } ?? a
        filtered = smooth
        defer {
            beforePrevious = previous?.a
            previous = (t, smooth)
        }
        guard let previous, let beforePrevious else { return false }
        let isPeak = previous.a > beforePrevious && previous.a >= smooth && previous.a > Self.threshold
        let isDip = previous.a < beforePrevious && previous.a <= smooth && previous.a < -Self.threshold
        if isPeak {
            lastPush = previous.t
        } else if isDip, let push = lastPush {
            let rise = previous.t - push
            lastPush = nil
            if rise >= Self.minRise, rise <= Self.maxRise, previous.t - lastCount >= Self.minBetween {
                count += 1
                lastCount = previous.t
                return true
            }
        }
        return false
    }
}
