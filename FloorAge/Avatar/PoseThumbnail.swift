import CoreGraphics
import simd

/// A flat picture of an exercise's key position for the "Next up" card: the keyframe furthest
/// from plain standing (the bottom of a squat, the raised knee), turned to the exercise's camera
/// angle and projected to 2D joints (y down) that `Mannequin` draws. Uses the same FK and ground
/// solver as the 3D coach.
enum PoseThumbnail {
    /// The keyframe that differs most from the "stand" pose.
    static func keyFrame(of clip: ExerciseClip, library: ExerciseLibrary = .shared) -> ExerciseClip.Frame? {
        let stand = (library.poses["stand"] ?? [:]).compactMapValues { v in
            v.count == 3 ? SIMD3<Float>(Float(v[0]), Float(v[1]), Float(v[2])) : nil
        }
        func distance(_ frame: ExerciseClip.Frame) -> Float {
            Set(frame.angles.keys).union(stand.keys).reduce(0) { sum, name in
                sum + simd_length((frame.angles[name] ?? .zero) - (stand[name] ?? .zero))
            }
        }
        return clip.frames.max { distance($0) < distance($1) }
    }

    /// Where each rig joint shows up in the picture, and the point on it that stands in for it.
    private static let joints: [BodyJoint: (name: String, offset: SIMD3<Float>)] = [
        .nose: ("head", SIMD3(0, 0.1, 0.03)), .neck: ("neck", .zero),
        .leftShoulder: ("lShoulder", .zero), .rightShoulder: ("rShoulder", .zero),
        .leftElbow: ("lElbow", .zero), .rightElbow: ("rElbow", .zero),
        .leftWrist: ("lWrist", .zero), .rightWrist: ("rWrist", .zero),
        .leftHip: ("lHip", .zero), .rightHip: ("rHip", .zero),
        .leftKnee: ("lKnee", .zero), .rightKnee: ("rKnee", .zero),
        .leftAnkle: ("lAnkle", .zero), .rightAnkle: ("rAnkle", .zero),
    ]

    /// Nearly side-on, where bends, squats and lifted knees read best in a small flat picture;
    /// face-on for moves out to the side (the coach's own camera angle is under 15° for those).
    static func angle(for exercise: Exercise) -> Double {
        let yaw = exercise.cameraYaw ?? 25
        return yaw < 15 ? yaw : 70
    }

    /// Joint positions fitted into `size` (points, y down), leaving room for the drawn body's
    /// width, head and feet.
    static func joints(for exercise: Exercise, size: CGSize, yaw: Double? = nil, library: ExerciseLibrary = .shared) -> [BodyJoint: CGPoint] {
        let clip = ExerciseClip(exercise: exercise, library: library)
        guard let frame = keyFrame(of: clip, library: library) else { return [:] }
        let pelvis = clip.solver.solvePelvis(frame.angles, ground: frame.ground, seatZ: frame.seatZ, rootZ: frame.rootZ)
        let world = clip.solver.world(frame.angles, pelvis: pelvis)
        let turn = simd_quatf(angle: Float((yaw ?? angle(for: exercise)) * .pi / 180), axis: SIMD3(0, 1, 0))
        func flat(_ name: String, _ offset: SIMD3<Float>) -> SIMD2<Float>? {
            guard let j = world[name] else { return nil }
            let p = turn.act(j.p + j.q.act(offset))
            return SIMD2(p.x, -p.y)
        }

        var points: [BodyJoint: SIMD2<Float>] = [:]
        for (joint, source) in joints { points[joint] = flat(source.name, source.offset) }
        // The top of the head and the soles set the height; the limbs' width pads the sides.
        let extents = [flat("head", SIMD3(0, 0.22, 0)), flat("lAnkle", SIMD3(0, -0.09, 0)), flat("rAnkle", SIMD3(0, -0.09, 0))]
        let all = Array(points.values) + extents.compactMap { $0 }
        guard var lo = all.first else { return [:] }
        var hi = lo
        for p in all {
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }
        let pad = SIMD2<Float>(0.16, 0.06)
        lo -= pad
        hi += pad
        let span = simd_max(hi - lo, SIMD2(0.01, 0.01))
        let scale = min(Float(size.width) / span.x, Float(size.height) / span.y)
        let offset = (SIMD2(Float(size.width), Float(size.height)) - span * scale) / 2
        return points.mapValues { p in
            let q = (p - lo) * scale + offset
            return CGPoint(x: CGFloat(q.x), y: CGFloat(q.y))
        }
    }
}
