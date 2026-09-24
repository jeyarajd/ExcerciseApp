import CoreGraphics
import Foundation
import simd

/// Turns a camera `BodyPose` (2D joints) into a `Pose` for the 3D coach, so the coach can copy the
/// person's movements live, like a mirror.
///
/// The camera only sees two dimensions, so depth is estimated from bone lengths: a thigh that looks
/// short must be pointing towards or away from the camera. Seen from the front, bones are assumed
/// to point forwards (knees and arms bend forwards). Seen side-on, the picture already shows the
/// forward direction, so the body is turned to face the way the person faces.
///
/// Everything works in view space (x to the screen's right, y up, z towards the viewer), which is
/// the coach's world space when it isn't turned.
struct PoseMirror {
    private let solver: PoseSolver
    private let lengths: [String: Float]

    init(rig: Rig) {
        solver = PoseSolver(rig: rig)
        var lengths: [String: Float] = [:]
        for joint in rig.joints { lengths[joint.name] = simd_length(SIMD3<Float>(joint.offset)) }
        self.lengths = lengths
    }

    /// Bone lengths in metres, from the rig.
    private var thigh: Float { lengths["lKnee"] ?? 0.43 }
    private var shin: Float { lengths["lAnkle"] ?? 0.42 }
    private var upperArm: Float { lengths["lElbow"] ?? 0.28 }
    private var forearm: Float { lengths["lWrist"] ?? 0.25 }
    private var trunk: Float { (lengths["spine"] ?? 0.08) + (lengths["chest"] ?? 0.22) + (lengths["neck"] ?? 0.22) }

    /// `aspect` is the camera frame's width over height (0.5625 for portrait 720 × 1280).
    func pose(from body: BodyPose, aspect: Double) -> Pose? {
        guard let points = viewSpace(body, aspect: aspect) else { return nil }
        var angles: [String: SIMD3<Float>] = [:]

        // Pelvis: faces along (left × up), with up from the hips to the shoulders.
        let hipMid = mid(points[.leftHip], points[.rightHip])!
        let shoulderMid = mid(points[.leftShoulder], points[.rightShoulder]) ?? points[.neck] ?? hipMid + SIMD3(0, trunk, 0)
        var left = simd_normalize((points[.leftHip] ?? hipMid + SIMD3(0.1, 0, 0)) - (points[.rightHip] ?? hipMid - SIMD3(0.1, 0, 0)))
        var up = simd_normalize(shoulderMid - hipMid)
        left = simd_normalize(left - simd_dot(left, up) * up)
        if !left.x.isFinite { left = SIMD3(1, 0, 0) }
        let forward = simd_normalize(simd_cross(left, up))
        up = simd_cross(forward, left)
        let pelvis = simd_quatf(simd_float3x3(columns: (left, up, forward)))
        angles["pelvis"] = Self.eulerDegrees(pelvis)
        // The spine and chest follow the pelvis; the trunk's lean is carried by the pelvis above.
        let chest = pelvis

        func limb(_ joint: String, parent: simd_quatf, from a: BodyJoint, to b: BodyJoint, rest: SIMD3<Float>) -> simd_quatf {
            guard let pa = points[a], let pb = points[b], simd_length(pb - pa) > 0.001 else { return parent }
            let observed = simd_normalize(pb - pa)
            let current = parent.act(rest)
            let world = simd_quatf(from: current, to: observed) * parent
            angles[joint] = Self.eulerDegrees(parent.inverse * world)
            return world
        }

        let down = SIMD3<Float>(0, -1, 0)
        let lShoulder = limb("lShoulder", parent: chest, from: .leftShoulder, to: .leftElbow, rest: down)
        _ = limb("lElbow", parent: lShoulder, from: .leftElbow, to: .leftWrist, rest: down)
        let rShoulder = limb("rShoulder", parent: chest, from: .rightShoulder, to: .rightElbow, rest: down)
        _ = limb("rElbow", parent: rShoulder, from: .rightElbow, to: .rightWrist, rest: down)
        let lHip = limb("lHip", parent: pelvis, from: .leftHip, to: .leftKnee, rest: down)
        _ = limb("lKnee", parent: lHip, from: .leftKnee, to: .leftAnkle, rest: down)
        let rHip = limb("rHip", parent: pelvis, from: .rightHip, to: .rightKnee, rest: down)
        _ = limb("rKnee", parent: rHip, from: .rightKnee, to: .rightAnkle, rest: down)
        // The head turns half as much as the line from neck to nose, which keeps it steady.
        if let neck = points[.neck], let nose = points[.nose], simd_length(nose - neck) > 0.001 {
            let world = simd_quatf(from: chest.act(SIMD3(0, 1, 0)), to: simd_normalize(nose - neck)) * chest
            angles["neck"] = Self.eulerDegrees(simd_slerp(simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), chest.inverse * world, 0.5))
        }

        // Feet on the floor where the exercises put them (so sitting lands on the chair prop), and
        // nothing below the floor.
        let feet = solver.solvePelvis(angles, ground: .feet, seatZ: 0, rootZ: 0)
        return Pose(angles: angles, pelvis: solver.clampToFloor(angles, pelvis: feet))
    }

    // MARK: - Depth

    /// Joint positions in metres in view space, with estimated depth.
    private func viewSpace(_ body: BodyPose, aspect: Double) -> [BodyJoint: SIMD3<Float>]? {
        guard body.hip != nil, body.knee != nil else { return nil }
        // Screen positions with x corrected for the frame's shape, so both axes use the same unit.
        let flat = body.joints.mapValues { SIMD2<Float>(Float(($0.x - 0.5) * aspect), Float($0.y)) }
        func span(_ a: BodyJoint, _ b: BodyJoint) -> Float? {
            guard let p = flat[a], let q = flat[b] else { return nil }
            let d = simd_length(q - p)
            return d > 0.005 ? d : nil
        }
        // Metres per screen unit. A bone never looks longer than it is, so the smallest estimate is
        // the one least tilted towards the camera.
        let estimates: [Float] = [
            span(.leftKnee, .leftAnkle).map { shin / $0 }, span(.rightKnee, .rightAnkle).map { shin / $0 },
            span(.leftHip, .leftKnee).map { thigh / $0 }, span(.rightHip, .rightKnee).map { thigh / $0 },
            span(.leftShoulder, .leftElbow).map { upperArm / $0 }, span(.rightShoulder, .rightElbow).map { upperArm / $0 },
            body.hip.flatMap { h in (body.pair(.leftShoulder, .rightShoulder) ?? body[.neck]).map { s in
                let d = simd_length(SIMD2<Float>(Float((s.x - h.x) * aspect), Float(s.y - h.y)))
                // Vision's hip points sit a little below the pelvis, so hip to shoulder is about the trunk length.
                return d > 0.005 ? trunk / d : .infinity
            } },
        ].compactMap { $0 }
        guard let scale = estimates.min(), scale.isFinite else { return nil }
        let meters = flat.mapValues { $0 * scale }

        // Side-on when the hips look much narrower than they are.
        let hipWidth = abs(solverHipX) * 2
        let seenHipWidth = span(.leftHip, .rightHip).map { $0 * scale } ?? 0
        let sideOn = seenHipWidth < hipWidth * 0.45

        if sideOn {
            // Facing the way the nose (or the knees, when seated) points.
            let hip = meters[.leftHip] ?? meters[.rightHip] ?? .zero
            let cue = meters[.nose].map { $0.x - (meters[.neck]?.x ?? hip.x) } ?? ((body.knee.map { Float(($0.x - 0.5) * aspect) * scale } ?? hip.x) - hip.x)
            let facing: Float = cue >= 0 ? 1 : -1
            // Left = up × forward, so with forward = ±x the left side is at ∓z.
            return meters.mapValues { SIMD3($0.x, $0.y, 0) }.reduce(into: [:]) { result, item in
                let side: Float = item.key.rawValue.hasPrefix("left") ? -facing : item.key.rawValue.hasPrefix("right") ? facing : 0
                result[item.key] = item.value + SIMD3(0, 0, side * solverHipX)
            }
        }

        // From the front: lift each bone towards the viewer by the length it's missing.
        var points = meters.mapValues { SIMD3($0.x, $0.y, 0) }
        let chains: [[(BodyJoint, Float)]] = [
            [(.leftHip, 0), (.leftKnee, thigh), (.leftAnkle, shin)],
            [(.rightHip, 0), (.rightKnee, thigh), (.rightAnkle, shin)],
            [(.leftShoulder, 0), (.leftElbow, upperArm), (.leftWrist, forearm)],
            [(.rightShoulder, 0), (.rightElbow, upperArm), (.rightWrist, forearm)],
        ]
        for chain in chains {
            var depth: Float = 0
            for i in 1..<chain.count {
                let (a, _) = chain[i - 1], (b, length) = chain[i]
                guard let pa = meters[a], let pb = meters[b] else { break }
                let seen = simd_length(pb - pa)
                // Knees come forward as you sit or lift a leg; the shin then hangs down or back.
                let sign: Float = (b == .leftAnkle || b == .rightAnkle) ? -0.4 : 1
                depth += sign * Self.hiddenLength(length, seen: seen)
                points[b]?.z = depth
            }
        }
        // A trunk that looks short is leaning towards the camera.
        if let hip = body.hip, let top = body.pair(.leftShoulder, .rightShoulder) {
            let seen = simd_length(SIMD2<Float>(Float((top.x - hip.x) * aspect), Float(top.y - hip.y))) * scale
            let lean = Self.hiddenLength(trunk, seen: seen)
            for joint in [BodyJoint.leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist, .neck, .nose] {
                points[joint]?.z += lean
            }
        }
        return points
    }

    private var solverHipX: Float { solver.hipX }

    /// How far a bone of `length` must reach towards the camera to look `seen` long. Bodies differ
    /// from the rig, so a bone that looks nearly full length (93%) counts as flat.
    static func hiddenLength(_ length: Float, seen: Float) -> Float {
        let full = length * 0.93
        return sqrt(max(0, full * full - seen * seen))
    }

    private func mid(_ a: SIMD3<Float>?, _ b: SIMD3<Float>?) -> SIMD3<Float>? {
        switch (a, b) {
        case let (a?, b?): (a + b) / 2
        default: a ?? b
        }
    }

    // MARK: - Euler angles

    /// Degrees (x, y, z) for the rig's convention q = qx · qz · qy (see `PoseSolver.localRotation`).
    static func eulerDegrees(_ q: simd_quatf) -> SIMD3<Float> {
        let m = simd_float3x3(q)
        // Row r, column c of the rotation matrix (simd stores columns).
        func r(_ row: Int, _ col: Int) -> Float { m[col][row] }
        let z = asin(max(-1, min(1, -r(0, 1))))
        let x = atan2(r(2, 1), r(1, 1))
        let y = atan2(r(0, 2), r(0, 0))
        return SIMD3(x, y, z) * (180 / .pi)
    }
}
