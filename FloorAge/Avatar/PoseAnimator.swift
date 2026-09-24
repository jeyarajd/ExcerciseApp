import Foundation
import simd

/// Joint angles in degrees (Euler, applied Y then Z then X) plus the pelvis position in metres.
struct Pose {
    var angles: [String: SIMD3<Float>]
    var pelvis: SIMD3<Float>

    func blended(to other: Pose, by u: Float) -> Pose {
        var angles: [String: SIMD3<Float>] = [:]
        for name in Set(self.angles.keys).union(other.angles.keys) {
            angles[name] = simd_mix(self.angles[name] ?? .zero, other.angles[name] ?? .zero, SIMD3(repeating: u))
        }
        return Pose(angles: angles, pelvis: simd_mix(pelvis, other.pelvis, SIMD3(repeating: u)))
    }
}

/// Forward kinematics and ground contact for the rig. Must stay in step with `tools/pose_preview.py`.
struct PoseSolver {
    struct Joint {
        let name: String
        let parent: String?
        let offset: SIMD3<Float>
    }

    let joints: [Joint]
    let contacts: [String: (joint: String, offset: SIMD3<Float>)]
    /// Toe z with the pelvis at the origin in the standing pose.
    let toeZ: Float
    let hipX: Float

    init(rig: Rig) {
        joints = rig.joints.map { Joint(name: $0.name, parent: $0.parent, offset: SIMD3($0.offset)) }
        var contacts: [String: (joint: String, offset: SIMD3<Float>)] = [:]
        for (name, contact) in rig.contacts {
            contacts[name] = (contact.joint, SIMD3(contact.offset))
        }
        self.contacts = contacts
        toeZ = contacts["lToe"]?.offset.z ?? 0.15
        hipX = joints.first { $0.name == "lHip" }?.offset.x ?? 0.1
    }

    static func localRotation(_ degrees: SIMD3<Float>) -> simd_quatf {
        let r = degrees * (.pi / 180)
        let qx = simd_quatf(angle: r.x, axis: SIMD3(1, 0, 0))
        let qy = simd_quatf(angle: r.y, axis: SIMD3(0, 1, 0))
        let qz = simd_quatf(angle: r.z, axis: SIMD3(0, 0, 1))
        return qx * qz * qy
    }

    func world(_ angles: [String: SIMD3<Float>], pelvis: SIMD3<Float>) -> [String: (q: simd_quatf, p: SIMD3<Float>)] {
        var world: [String: (q: simd_quatf, p: SIMD3<Float>)] = [:]
        for joint in joints {
            let local = Self.localRotation(angles[joint.name] ?? .zero)
            if let parent = joint.parent, let p = world[parent] {
                world[joint.name] = (p.q * local, p.p + p.q.act(joint.offset))
            } else {
                world[joint.name] = (local, pelvis + joint.offset)
            }
        }
        return world
    }

    func contactPoints(_ angles: [String: SIMD3<Float>], pelvis: SIMD3<Float>) -> [String: SIMD3<Float>] {
        let transforms = world(angles, pelvis: pelvis)
        var points: [String: SIMD3<Float>] = [:]
        for (name, contact) in contacts {
            guard let j = transforms[contact.joint] else { continue }
            points[name] = j.p + j.q.act(contact.offset)
        }
        return points
    }

    /// Pelvis position that puts the keyframe's ground contact on the floor.
    func solvePelvis(_ angles: [String: SIMD3<Float>], ground: Keyframe.Ground, seatZ: Float, rootZ: Float) -> SIMD3<Float> {
        let pts = contactPoints(angles, pelvis: .zero)
        func y(_ keys: [String]) -> Float { keys.compactMap { pts[$0]?.y }.min() ?? 0 }

        let anchor: SIMD3<Float>
        let target: SIMD2<Float>  // x, z
        let yMin: Float
        switch ground {
        case .feet:
            anchor = ((pts["lToe"] ?? .zero) + (pts["rToe"] ?? .zero)) / 2
            target = SIMD2(0, toeZ)
            yMin = y(["lHeel", "lToe", "rHeel", "rToe"])
        case .left:
            anchor = pts["lToe"] ?? .zero
            target = SIMD2(hipX, toeZ)
            yMin = y(["lHeel", "lToe"])
        case .right:
            anchor = pts["rToe"] ?? .zero
            target = SIMD2(-hipX, toeZ)
            yMin = y(["rHeel", "rToe"])
        case .seat:
            anchor = pts["seat"] ?? .zero
            target = SIMD2(0, seatZ)
            yMin = pts["seat"]?.y ?? 0
        case .lowest:
            anchor = .zero
            target = SIMD2(0, rootZ)
            yMin = pts.values.map(\.y).min() ?? 0
        }
        return SIMD3(target.x - anchor.x, -yMin, target.y - anchor.z)
    }

    /// Lifts the body if blending between ground modes pushed any contact through the floor.
    func clampToFloor(_ angles: [String: SIMD3<Float>], pelvis: SIMD3<Float>) -> SIMD3<Float> {
        let low = contactPoints(angles, pelvis: pelvis).values.map(\.y).min() ?? 0
        return low < 0 ? pelvis + SIMD3(0, -low, 0) : pelvis
    }
}

/// An exercise's keyframes resolved into joint angles, ready to sample at any time.
struct ExerciseClip {
    struct Frame {
        let t: Double
        let angles: [String: SIMD3<Float>]
        let ground: Keyframe.Ground
        let seatZ: Float
        let rootZ: Float
    }

    let exercise: Exercise
    let frames: [Frame]
    let props: [Prop]
    let solver: PoseSolver

    var duration: Double { frames.last?.t ?? 0 }

    init(exercise: Exercise, library: ExerciseLibrary = .shared, mirrored: Bool = false) {
        self.exercise = exercise
        solver = PoseSolver(rig: library.rig)
        frames = exercise.keyframes.map { kf in
            var raw = library.poses[kf.pose ?? ""] ?? [:]
            for (name, value) in kf.joints ?? [:] { raw[name] = value }
            var angles: [String: SIMD3<Float>] = [:]
            for (name, v) in raw where v.count == 3 {
                var a = SIMD3<Float>(Float(v[0]), Float(v[1]), Float(v[2]))
                var joint = name
                if mirrored {
                    joint = Self.mirroredName(name)
                    a = SIMD3(a.x, -a.y, -a.z)
                }
                angles[joint] = a
            }
            var ground = kf.ground ?? .feet
            if mirrored {
                if ground == .left { ground = .right } else if ground == .right { ground = .left }
            }
            return Frame(t: kf.t, angles: angles, ground: ground, seatZ: kf.seatZ ?? 0, rootZ: kf.rootZ ?? 0)
        }
        props = (exercise.props ?? []).map { prop in
            guard mirrored, prop.position.count == 3 else { return prop }
            return Prop(type: prop.type, position: [-prop.position[0], prop.position[1], prop.position[2]])
        }
    }

    /// "lKnee" <-> "rKnee"; spine joints are unchanged.
    static func mirroredName(_ name: String) -> String {
        guard name.count > 1, let first = name.first, first == "l" || first == "r" else { return name }
        let second = name[name.index(after: name.startIndex)]
        guard second.isUppercase else { return name }
        let side: String = first == "l" ? "r" : "l"
        return side + name.dropFirst()
    }

    /// Pose at time `t` (seconds), looping over the clip.
    func sample(at t: Double) -> Pose {
        guard let first = frames.first else { return Pose(angles: [:], pelvis: .zero) }
        let local = duration > 0 ? t.truncatingRemainder(dividingBy: duration) : 0
        var a = first
        var b = first
        for (fa, fb) in zip(frames, frames.dropFirst()) where fa.t <= local && local <= fb.t {
            a = fa
            b = fb
            break
        }
        let span = b.t - a.t
        let raw = span > 0 ? Float((local - a.t) / span) : 0
        let u = raw * raw * (3 - 2 * raw)

        var angles: [String: SIMD3<Float>] = [:]
        for name in Set(a.angles.keys).union(b.angles.keys) {
            angles[name] = simd_mix(a.angles[name] ?? .zero, b.angles[name] ?? .zero, SIMD3(repeating: u))
        }
        let pa = solver.solvePelvis(angles, ground: a.ground, seatZ: a.seatZ, rootZ: a.rootZ)
        let pb = solver.solvePelvis(angles, ground: b.ground, seatZ: b.seatZ, rootZ: b.rootZ)
        let pelvis = solver.clampToFloor(angles, pelvis: simd_mix(pa, pb, SIMD3(repeating: u)))
        return Pose(angles: angles, pelvis: pelvis)
    }
}
