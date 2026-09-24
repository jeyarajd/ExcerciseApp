import CoreGraphics
import Foundation

/// Body joints the camera tracks (a subset of Vision's body pose joints).
enum BodyJoint: String, CaseIterable {
    case nose, neck, leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist
    case leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle
}

/// One camera frame's joints, in normalized image coordinates with the origin at the bottom
/// left (Vision's convention), so larger y is higher up. Joints Vision isn't sure of are left out.
struct BodyPose: Equatable {
    var joints: [BodyJoint: CGPoint]

    subscript(_ joint: BodyJoint) -> CGPoint? { joints[joint] }

    /// The midpoint of a left/right pair, or whichever side is visible.
    func pair(_ left: BodyJoint, _ right: BodyJoint) -> CGPoint? {
        switch (joints[left], joints[right]) {
        case let (l?, r?): CGPoint(x: (l.x + r.x) / 2, y: (l.y + r.y) / 2)
        case let (l?, nil): l
        case let (nil, r?): r
        default: nil
        }
    }

    var hip: CGPoint? { pair(.leftHip, .rightHip) }
    var knee: CGPoint? { pair(.leftKnee, .rightKnee) }
    var ankle: CGPoint? { pair(.leftAnkle, .rightAnkle) }
    /// The lower hand, for the toe reach.
    var lowestWrist: CGPoint? { [joints[.leftWrist], joints[.rightWrist]].compactMap { $0 }.min { $0.y < $1.y } }

    /// Hips, knees and ankles are all in view: enough to score the tests.
    var legsVisible: Bool { hip != nil && knee != nil && ankle != nil }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double { Double(hypot(a.x - b.x, a.y - b.y)) }
}

/// Keeps a reading only once it has been seen for a few frames in a row, so one wobbly frame
/// doesn't count as a stand or a foot touching down.
struct Debounce<Value: Equatable> {
    let frames: Int
    private(set) var value: Value
    private var candidate: Value
    private var seen = 0

    init(_ value: Value, frames: Int = 3) {
        self.value = value
        candidate = value
        self.frames = frames
    }

    /// Feeds one frame's reading; returns true when the settled value changes.
    mutating func feed(_ reading: Value) -> Bool {
        if reading == value {
            candidate = value
            seen = 0
            return false
        }
        if reading == candidate {
            seen += 1
        } else {
            candidate = reading
            seen = 1
        }
        guard seen >= frames else { return false }
        value = reading
        seen = 0
        return true
    }
}

/// Counts full stands in the 30-second chair stand.
///
/// "Rise" is how far the hips are above the knees, measured in shin lengths (knee to ankle, which
/// stays the same length whatever the posture). Seated, the thighs are level and rise is near 0;
/// standing, the hips are a thigh's length above the knees and rise is about 1. This works with the
/// person side-on or facing the phone.
struct ChairStandCounter {
    enum Posture { case unknown, seated, standing }

    static let standingAbove = 0.7
    static let seatedBelow = 0.35

    private(set) var count = 0
    private var posture = Debounce(Posture.unknown)

    var current: Posture { posture.value }

    static func rise(_ pose: BodyPose) -> Double? {
        guard let hip = pose.hip, let knee = pose.knee, let ankle = pose.ankle else { return nil }
        let shin = BodyPose.distance(knee, ankle)
        guard shin > 0.01 else { return nil }
        return Double(hip.y - knee.y) / shin
    }

    /// Feeds one frame. Returns true when it completes a stand (seated, then fully up).
    mutating func update(_ pose: BodyPose) -> Bool {
        guard let rise = Self.rise(pose) else { return false }
        let reading: Posture = rise > Self.standingAbove ? .standing : rise < Self.seatedBelow ? .seated : posture.value
        let before = posture.value
        guard posture.feed(reading) else { return false }
        // Only a stand that started from sitting counts, so starting on your feet adds nothing.
        if before == .seated, posture.value == .standing {
            count += 1
            return true
        }
        return false
    }
}

/// Notices when one foot comes off the floor and when it touches down again, for the one-leg
/// balance timer. Compares the two ankles' heights against the length of the leg.
struct BalanceDetector {
    enum Event: Equatable { case lifted, down }

    static let liftedAbove = 0.15
    static let downBelow = 0.06

    private var lifted = Debounce(false)

    var isLifted: Bool { lifted.value }

    static func footGap(_ pose: BodyPose) -> Double? {
        guard let left = pose[.leftAnkle], let right = pose[.rightAnkle], let hip = pose.hip else { return nil }
        let leg = BodyPose.distance(hip, CGPoint(x: (left.x + right.x) / 2, y: min(left.y, right.y)))
        guard leg > 0.01 else { return nil }
        return abs(Double(left.y - right.y)) / leg
    }

    mutating func update(_ pose: BodyPose) -> Event? {
        guard let gap = Self.footGap(pose) else { return nil }
        let reading = gap > Self.liftedAbove ? true : gap < Self.downBelow ? false : lifted.value
        guard lifted.feed(reading) else { return nil }
        return lifted.value ? .lifted : .down
    }
}

/// Suggests how far the person reached in the toe reach, from the lowest point their hand got to
/// (best seen side-on). Depth is the wrist's height above the ankle in shin lengths; the wrist sits
/// about a hand's length above the fingertips, which sets the bands below.
struct ReachEstimator {
    private(set) var deepest: Double?

    static func depth(_ pose: BodyPose) -> Double? {
        guard let wrist = pose.lowestWrist, let knee = pose.knee, let ankle = pose.ankle, let hip = pose.hip,
              let neck = pose[.neck] ?? pose.pair(.leftShoulder, .rightShoulder) else { return nil }
        // Only while folded forward (the trunk tipped more than 60°): standing with arms down
        // also puts the hands below the hips.
        let trunk = BodyPose.distance(neck, hip)
        guard trunk > 0.01, Double(neck.y - hip.y) / trunk < 0.5 else { return nil }
        let shin = Double(knee.y - ankle.y)
        guard shin > 0.01 else { return nil }
        return Double(wrist.y - ankle.y) / shin
    }

    static func level(depth: Double) -> ReachLevel {
        switch depth {
        case ..<(-0.02): .palmsFlat
        case ..<0.16: .fingersToFloor
        case ..<0.33: .toes
        case ..<0.67: .ankles
        case ..<1.16: .shins
        default: .knees
        }
    }

    var level: ReachLevel? { deepest.map(Self.level(depth:)) }

    mutating func update(_ pose: BodyPose) {
        guard let depth = Self.depth(pose) else { return }
        deepest = min(deepest ?? depth, depth)
    }
}

extension BodyPose {
    /// A made-up skeleton, for tests and the Debug demo screens. Seen from the front unless `fold`
    /// is above 0, which shows a forward fold side-on (facing right) until the wrists reach
    /// `wristDepth` shin lengths above the ankles. `rise` 1 is standing and 0 seated; `lift` raises
    /// the left foot (0–1); `armsCrossed` folds the arms over the chest, as in the chair stand;
    /// `armSpread` holds the arms out a little, as for balance.
    static func sample(rise: Double = 1, lift: Double = 0, fold: Double = 0, wristDepth: Double = 1.4,
                       armsCrossed: Bool = false, armSpread: Double = 0) -> BodyPose {
        let ankleY = 0.12, shin = 0.2, torso = 0.26
        let kneeY = ankleY + shin
        let hipY = kneeY + shin * rise
        if fold > 0 {
            // Side-on: left and right overlap, and the trunk tips forward from the hips.
            let x = 0.45
            let tilt = fold * 1.8
            let neck = CGPoint(x: x + torso * sin(tilt), y: hipY + torso * cos(tilt))
            let shoulder = CGPoint(x: neck.x - 0.01 * sin(tilt), y: neck.y - 0.01 * cos(tilt))
            let wristY = min(ankleY + shin * (wristDepth + (1 - fold) * 2), shoulder.y - 0.05)
            let wrist = CGPoint(x: shoulder.x + 0.03, y: wristY)
            let elbow = CGPoint(x: (shoulder.x + wrist.x) / 2 + 0.01, y: (shoulder.y + wrist.y) / 2)
            let head = tilt + 0.3
            return BodyPose(joints: [
                .nose: CGPoint(x: neck.x + 0.07 * sin(head), y: neck.y + 0.07 * cos(head)),
                .neck: neck,
                .leftShoulder: shoulder, .rightShoulder: CGPoint(x: shoulder.x - 0.004, y: shoulder.y),
                .leftElbow: elbow, .rightElbow: CGPoint(x: elbow.x - 0.004, y: elbow.y),
                .leftWrist: wrist, .rightWrist: CGPoint(x: wrist.x - 0.004, y: wrist.y + 0.005),
                .leftHip: CGPoint(x: x, y: hipY), .rightHip: CGPoint(x: x - 0.004, y: hipY),
                .leftKnee: CGPoint(x: x + 0.005, y: kneeY), .rightKnee: CGPoint(x: x + 0.001, y: kneeY),
                .leftAnkle: CGPoint(x: x, y: ankleY), .rightAnkle: CGPoint(x: x - 0.004, y: ankleY),
            ])
        }
        let neck = CGPoint(x: 0.5, y: hipY + torso)
        let leftShoulder = CGPoint(x: neck.x + 0.08, y: neck.y - 0.01)
        let rightShoulder = CGPoint(x: neck.x - 0.08, y: neck.y - 0.01)
        let leftWrist, rightWrist, leftElbow, rightElbow: CGPoint
        if armsCrossed {
            // Each hand on the opposite shoulder, elbows out and down.
            leftWrist = CGPoint(x: neck.x - 0.06, y: neck.y - 0.08)
            rightWrist = CGPoint(x: neck.x + 0.06, y: neck.y - 0.09)
            leftElbow = CGPoint(x: neck.x + 0.1, y: neck.y - 0.15)
            rightElbow = CGPoint(x: neck.x - 0.1, y: neck.y - 0.15)
        } else {
            leftWrist = CGPoint(x: 0.6 + armSpread, y: hipY - 0.02 + armSpread * 0.5)
            rightWrist = CGPoint(x: 0.4 - armSpread, y: hipY - 0.01 + armSpread * 0.5)
            leftElbow = CGPoint(x: (leftShoulder.x + leftWrist.x) / 2 + 0.02, y: (leftShoulder.y + leftWrist.y) / 2)
            rightElbow = CGPoint(x: (rightShoulder.x + rightWrist.x) / 2 - 0.02, y: (rightShoulder.y + rightWrist.y) / 2)
        }
        return BodyPose(joints: [
            .nose: CGPoint(x: neck.x, y: neck.y + 0.07),
            .neck: neck,
            .leftShoulder: leftShoulder,
            .rightShoulder: rightShoulder,
            .leftElbow: leftElbow,
            .rightElbow: rightElbow,
            .leftWrist: leftWrist,
            .rightWrist: rightWrist,
            .leftHip: CGPoint(x: 0.55, y: hipY),
            .rightHip: CGPoint(x: 0.45, y: hipY),
            .leftKnee: CGPoint(x: 0.56, y: kneeY + lift * 0.1),
            .rightKnee: CGPoint(x: 0.44, y: kneeY),
            .leftAnkle: CGPoint(x: 0.56, y: ankleY + lift * 0.14),
            .rightAnkle: CGPoint(x: 0.44, y: ankleY),
        ])
    }
}
