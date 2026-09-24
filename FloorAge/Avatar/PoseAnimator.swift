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

extension Pose {
    /// A slow shift of weight from foot to foot (±1.5° pelvis roll over 4 s), with the chest
    /// countering most of it so the head stays level. `amount` 0–1 fades it in and out.
    func withWeightShift(time: Double, amount: Float) -> Pose {
        guard amount > 0 else { return self }
        var pose = self
        let roll = 1.5 * Float(sin(time * 2 * .pi / 4)) * amount
        pose.angles["pelvis", default: .zero].z += roll
        pose.angles["chest", default: .zero].z -= roll * 0.8
        return pose
    }

    /// Turns the head towards the viewer when the body is turned `bodyYaw` degrees, by at most
    /// `limit` degrees. `amount` 0–1 fades it in and out.
    func lookingAtViewer(bodyYaw: Float, limit: Float = 20, amount: Float) -> Pose {
        guard amount > 0 else { return self }
        var pose = self
        pose.angles["neck", default: .zero].y += max(-limit, min(limit, -bodyYaw)) * amount
        return pose
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
    /// Joint angle speed (degrees per second) at each keyframe, for smooth motion through keys.
    let slopes: [[String: SIMD3<Float>]]

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
        slopes = Self.slopes(for: frames)
        props = (exercise.props ?? []).map { prop in
            guard mirrored, prop.position.count == 3 else { return prop }
            return Prop(type: prop.type, position: [-prop.position[0], prop.position[1], prop.position[2]])
        }
    }

    /// Monotone cubic slopes: motion flows through a keyframe when both sides move the same way,
    /// and eases to a stop where it turns round or holds, so it never overshoots a pose. The first
    /// and last keyframes ease in and out. With every slope zero this is plain smoothstep.
    static func slopes(for frames: [Frame]) -> [[String: SIMD3<Float>]] {
        let names = Set(frames.flatMap { $0.angles.keys })
        return frames.indices.map { i in
            guard i > 0, i < frames.count - 1 else { return [:] }
            let h0 = Float(frames[i].t - frames[i - 1].t), h1 = Float(frames[i + 1].t - frames[i].t)
            guard h0 > 0, h1 > 0 else { return [:] }
            var slopes: [String: SIMD3<Float>] = [:]
            for name in names {
                let p0 = frames[i - 1].angles[name] ?? .zero, p1 = frames[i].angles[name] ?? .zero, p2 = frames[i + 1].angles[name] ?? .zero
                let d0 = (p1 - p0) / h0, d1 = (p2 - p1) / h1
                var m = SIMD3<Float>.zero
                for k in 0..<3 where d0[k] * d1[k] > 0 {
                    let w0 = 2 * h1 + h0, w1 = h1 + 2 * h0
                    m[k] = (w0 + w1) / (w0 / d0[k] + w1 / d1[k])
                }
                slopes[name] = m
            }
            return slopes
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
        guard !frames.isEmpty else { return Pose(angles: [:], pelvis: .zero) }
        let local = duration > 0 ? t.truncatingRemainder(dividingBy: duration) : 0
        var ia = 0
        for i in 0..<(frames.count - 1) where frames[i].t <= local && local <= frames[i + 1].t {
            ia = i
            break
        }
        let ib = min(ia + 1, frames.count - 1)
        let a = frames[ia], b = frames[ib]
        let span = Float(b.t - a.t)
        let raw = span > 0 ? Float(local - a.t) / span : 0
        let u = raw * raw * (3 - 2 * raw)

        // Cubic Hermite: smoothstep between the two poses plus the keyframe slopes.
        let s2 = raw * raw, s3 = s2 * raw
        let h10 = (s3 - 2 * s2 + raw) * span, h11 = (s3 - s2) * span
        var angles: [String: SIMD3<Float>] = [:]
        for name in Set(a.angles.keys).union(b.angles.keys) {
            let pa = a.angles[name] ?? .zero, pb = b.angles[name] ?? .zero
            let ma = slopes[ia][name] ?? .zero, mb = slopes[ib][name] ?? .zero
            angles[name] = simd_mix(pa, pb, SIMD3(repeating: u)) + h10 * ma + h11 * mb
        }
        let pa = solver.solvePelvis(angles, ground: a.ground, seatZ: a.seatZ, rootZ: a.rootZ)
        let pb = solver.solvePelvis(angles, ground: b.ground, seatZ: b.seatZ, rootZ: b.rootZ)
        let pelvis = solver.clampToFloor(angles, pelvis: simd_mix(pa, pb, SIMD3(repeating: u)))
        return Pose(angles: angles, pelvis: pelvis)
    }
}
