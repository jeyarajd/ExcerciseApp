import Foundation
import RealityKit


/// A body the avatar controller can pose: the realistic coach (or `MissingBody` if its model can't load).
protocol CoachBody: AnyObject {
    var root: Entity { get }
    func apply(_ pose: Pose)
    func blink(_ closed: Float)
    func restyle(_ look: CoachLook)
    /// How much bigger the body is than the skeleton in exercises.json (the man coach is taller),
    /// so the camera can keep the whole of it in view.
    var scale: Float { get }
    /// How far the top of the head (with hair) sits above the head joint, before `scale`.
    var headHeight: Float { get }
}

/// Realistic coach built with MakeHuman (CC0, see tools/build_coach.py), bundled as
/// `coach_female.usdz` / `coach_male.usdz`. Its skeleton (MPFB "game_engine" rig) is driven by the
/// poses in exercises.json: our forward kinematics gives each joint's rotation, which is
/// applied to the matching bone on top of that bone's rest pose.
final class RealisticCoach: CoachBody {
    let root = Entity()

    /// Our rig joint -> model bone.
    private static let boneFor: [String: String] = [
        "pelvis": "pelvis", "spine": "spine_01", "chest": "spine_03", "neck": "neck_01", "head": "head",
        "lShoulder": "upperarm_l", "lElbow": "lowerarm_l", "lWrist": "hand_l",
        "rShoulder": "upperarm_r", "rElbow": "lowerarm_r", "rWrist": "hand_r",
        "lHip": "thigh_l", "lKnee": "calf_l", "lAnkle": "foot_l",
        "rHip": "thigh_r", "rKnee": "calf_r", "rAnkle": "foot_r",
    ]
    /// Limb bones and the bone each points at in the rest pose. They're straightened to our rest
    /// pose (arms and legs hanging straight down); the spine and neck keep their natural curve.
    private static let aimAt: [String: String] = [
        "upperarm_l": "lowerarm_l", "lowerarm_l": "hand_l", "hand_l": "middle_01_l",
        "upperarm_r": "lowerarm_r", "lowerarm_r": "hand_r", "hand_r": "middle_01_r",
        "thigh_l": "calf_l", "calf_l": "foot_l", "thigh_r": "calf_r", "calf_r": "foot_r",
    ]

    private static var cache: [CoachLook: Entity] = [:]
    /// Blender (Z up, facing -Y) to the app (Y up, facing +Z).
    private static let fromBlender = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])

    private let solver: PoseSolver
    private var model: ModelEntity
    private var bones: [String] = []
    private var parent: [Int?] = []
    private var restLocal: [Transform] = []
    private var restRotation: [simd_quatf] = []
    private var restPosition: [SIMD3<Float>] = []
    private var align: [Int: simd_quatf] = [:]
    private var index: [String: Int] = [:]
    private var jointFor: [Int: String] = [:]
    /// Model contact points: (bone, offset in that bone's rest frame), keyed like `Rig.contacts`.
    private var contacts: [String: (bone: Int, offset: SIMD3<Float>)] = [:]
    /// How much further the model's pelvis moves than ours (leg length ratio).
    private var legRatio: Float = 1
    var scale: Float { legRatio }
    var headHeight: Float { 0.28 }
    private var ourRestPelvis: SIMD3<Float> = .zero
    /// Finger and thumb bones' local rotations for a relaxed, softly curled hand (instead of the
    /// model's straight, splayed rest pose).
    private var relaxed: [Int: simd_quatf] = [:]
    /// Where the "EyesClosed" weight sits in the model's blend shape weights, and its current value.
    private var eyelids: (set: Int, weight: Int)?
    private var shownClosed: Float = -1

    init?(look: CoachLook, rig: Rig) {
        solver = PoseSolver(rig: rig)
        guard let model = Self.loadModel(look) else { return nil }
        self.model = model
        root.addChild(model)
        guard prepare() else { return nil }
    }

    /// Whether the realistic models are in the app bundle.
    static var isAvailable: Bool {
        Bundle.main.url(forResource: "coach_female", withExtension: "usdz") != nil
    }

    func restyle(_ look: CoachLook) {
        guard let fresh = Self.loadModel(look) else { return }
        model.removeFromParent()
        model = fresh
        root.addChild(model)
        _ = prepare()
    }

    func blink(_ closed: Float) {
        // Called every frame, so only touch the component when the eyelids actually move.
        guard let eyelids, abs(closed - shownClosed) > 0.01,
              var component = model.components[BlendShapeWeightsComponent.self] else { return }
        shownClosed = closed
        component.weightSet[eyelids.set].weights[eyelids.weight] = closed
        model.components.set(component)
    }

    // MARK: - Loading

    private static func loadModel(_ look: CoachLook) -> ModelEntity? {
        if cache[look] == nil {
            guard let url = Bundle.main.url(forResource: "coach_\(look.rawValue)", withExtension: "usdz"),
                  let entity = try? Entity.load(contentsOf: url) else { return nil }
            cache[look] = entity
        }
        guard let skinned = cache[look].flatMap(findSkinned) else { return nil }
        let copy = skinned.clone(recursive: true)
        tidyMaterials(copy)
        return copy
    }

    private static func findSkinned(_ entity: Entity) -> ModelEntity? {
        if let model = entity as? ModelEntity, !model.jointNames.isEmpty { return model }
        for child in entity.children {
            if let found = findSkinned(child) { return found }
        }
        return nil
    }

    /// RealityKit imports every USD material as blended. Parts with an opacity mask (hair, brows,
    /// lashes) become alpha-tested cut-outs, everything else solid; see tools/build_coach.py.
    private static func tidyMaterials(_ model: ModelEntity) {
        guard var materials = model.model?.materials else { return }
        for i in materials.indices {
            guard var pbr = materials[i] as? PhysicallyBasedMaterial else { continue }
            if case .transparent(let opacity) = pbr.blending, opacity.texture != nil {
                pbr.blending = .opaque
                pbr.opacityThreshold = 0.5
                pbr.faceCulling = .none
            } else {
                pbr.blending = .opaque
                pbr.opacityThreshold = nil
            }
            materials[i] = pbr
        }
        model.model?.materials = materials
    }

    /// Reads the skeleton and works out rest directions, contacts and scale.
    private func prepare() -> Bool {
        let paths = model.jointNames
        bones = paths.map { String($0.split(separator: "/").last ?? "") }
        index = Dictionary(bones.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let pathIndex = Dictionary(paths.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        parent = paths.map { path in
            let parts = path.split(separator: "/")
            return parts.count > 1 ? pathIndex[parts.dropLast().joined(separator: "/")] : nil
        }
        restLocal = model.jointTransforms
        guard let pelvis = index["pelvis"], restLocal.count == bones.count else { return false }

        // Rest pose in model space.
        restRotation = Array(repeating: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), count: bones.count)
        restPosition = Array(repeating: .zero, count: bones.count)
        for i in bones.indices {
            if let p = parent[i] {
                restRotation[i] = restRotation[p] * restLocal[i].rotation
                restPosition[i] = restPosition[p] + restRotation[p].act(restLocal[i].translation)
            } else {
                restRotation[i] = Self.fromBlender * restLocal[i].rotation
                restPosition[i] = Self.fromBlender.act(restLocal[i].translation)
            }
        }

        // Our rest pose: arms and legs straight down, spine and neck straight up, feet flat.
        jointFor = [:]
        align = [:]
        for (joint, bone) in Self.boneFor {
            guard let i = index[bone] else { continue }
            jointFor[i] = joint
            guard let target = Self.aimAt[bone].flatMap({ index[$0] }) else { continue }
            let restDirection = normalize(restPosition[target] - restPosition[i])
            align[i] = simd_quatf(from: restDirection, to: [0, -1, 0])
        }

        // Contacts matching exercises.json, from the model's own feet, hands and knees.
        func bone(_ name: String) -> Int? { index[name] }
        func offset(_ i: Int, world: SIMD3<Float>) -> SIMD3<Float> { restRotation[i].inverse.act(world - restPosition[i]) }
        contacts = [:]
        for side in ["l", "r"] {
            let key = side == "l" ? "l" : "r"
            if let foot = bone("foot_" + side) {
                let p = restPosition[foot]
                contacts[key + "Heel"] = (foot, offset(foot, world: [p.x, 0, p.z - 0.05]))
            }
            if let ball = bone("ball_" + side) {
                let p = restPosition[ball]
                contacts[key + "Toe"] = (ball, offset(ball, world: [p.x, 0, p.z + 0.05]))
            }
            if let calf = bone("calf_" + side) {
                contacts[key + "KneeCap"] = (calf, offset(calf, world: restPosition[calf] + [0, 0, 0.06]))
            }
            if let hand = bone("hand_" + side), let tip = bone("middle_01_" + side) {
                contacts[key + "Hand"] = (hand, offset(hand, world: restPosition[tip]))
            }
        }
        if let thigh = bone("thigh_l") {
            contacts["seat"] = (pelvis, offset(pelvis, world: [0, restPosition[thigh].y - 0.07, restPosition[pelvis].z - 0.03]))
        }

        // Match our standing pelvis to the model's, scaling movement by leg length.
        let zero: [String: SIMD3<Float>] = [:]
        ourRestPelvis = solver.solvePelvis(zero, ground: .feet, seatZ: 0, rootZ: 0)
        legRatio = max(0.5, restPosition[pelvis].y / max(ourRestPelvis.y, 0.1))
        prepareEyelids()
        prepareHands()
        return true
    }

    /// Curls each finger joint towards the palm (more in the middle joint), and the thumb a little.
    private func prepareHands() {
        relaxed = [:]
        let curl: [(String, [Float])] = [("index", [12, 22, 14]), ("middle", [15, 26, 16]), ("ring", [18, 28, 16]),
                                         ("pinky", [21, 30, 16]), ("thumb", [6, 12, 8])]
        for side in ["l", "r"] {
            guard let hand = index["hand_" + side], let first = index["index_01_" + side], let last = index["pinky_01_" + side]
            else { continue }
            // The palm faces this way at rest.
            var palm = normalize(cross(restPosition[first] - restPosition[hand], restPosition[last] - restPosition[hand]))
            if side == "r" { palm = -palm }
            palm *= Self.palmSide
            for (finger, degrees) in curl {
                for (k, angle) in degrees.enumerated() {
                    guard let i = index["\(finger)_0\(k + 1)_\(side)"] else { continue }
                    let next = index["\(finger)_0\(k + 2)_\(side)"] ?? i
                    let parentBone = parent[i] ?? i
                    let along = next != i ? restPosition[next] - restPosition[i] : restPosition[i] - restPosition[parentBone]
                    let axis = normalize(cross(normalize(along), palm))
                    guard axis.x.isFinite else { continue }
                    let local = restRotation[i].inverse.act(axis)
                    relaxed[i] = restLocal[i].rotation * simd_quatf(angle: angle * .pi / 180, axis: local)
                }
            }
        }
    }

    /// Which way "towards the palm" is for the MakeHuman hands (checked on camera).
    private static let palmSide: Float = -1

    /// Finds the "EyesClosed" blend shape that tools/build_coach.py bakes from the MakeHuman
    /// eyelid bones (older models without it just don't blink).
    private func prepareEyelids() {
        eyelids = nil
        shownClosed = -1
        guard let mesh = model.model?.mesh else { return }
        let component = BlendShapeWeightsComponent(weightsMapping: BlendShapeWeightsMapping(meshResource: mesh))
        for (set, data) in component.weightSet.enumerated() {
            if let weight = data.weightNames.firstIndex(where: { $0.hasSuffix("EyesClosed") }) {
                model.components.set(component)
                eyelids = (set, weight)
                return
            }
        }
    }

    // MARK: - Posing

    func apply(_ pose: Pose) {
        guard !bones.isEmpty else { return }
        let ours = solver.world(pose.angles, pelvis: pose.pelvis)
        var rotation = restRotation
        var position = restPosition
        var local = restLocal
        var solved = Array(repeating: false, count: bones.count)

        func solve(_ i: Int) {
            guard !solved[i] else { return }
            if let p = parent[i] { solve(p) }
            if let joint = jointFor[i], let q = ours[joint]?.q {
                rotation[i] = q * (align[i] ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)) * restRotation[i]
            } else if let p = parent[i] {
                rotation[i] = rotation[p] * (relaxed[i] ?? restLocal[i].rotation)
                if let lift = shoulderLift(bones[i], ours) { rotation[i] = lift * rotation[i] }
            }
            if bones[i] == "pelvis" {
                position[i] = restPosition[i] + (pose.pelvis - ourRestPelvis) * legRatio
            } else if let p = parent[i] {
                position[i] = position[p] + rotation[p].act(restLocal[i].translation)
            }
            solved[i] = true
        }
        // spine_02 sits halfway between spine_01 and spine_03 so the back bends smoothly.
        for i in bones.indices { solve(i) }
        if let s1 = index["spine_01"], let s2 = index["spine_02"], let s3 = index["spine_03"] {
            rotation[s2] = simd_slerp(rotation[s1], rotation[s3], 0.5)
            for i in bones.indices where isBelow(i, s2) {
                if let p = parent[i], i != s2 {
                    if jointFor[i] == nil {
                        rotation[i] = rotation[p] * (relaxed[i] ?? restLocal[i].rotation)
                        if let lift = shoulderLift(bones[i], ours) { rotation[i] = lift * rotation[i] }
                    }
                    position[i] = position[p] + rotation[p].act(restLocal[i].translation)
                }
            }
        }

        // Put the same body part on the floor as our solver did.
        let ourContacts = solver.contactPoints(pose.angles, pelvis: pose.pelvis)
        if let lowest = ourContacts.min(by: { $0.value.y < $1.value.y }), let contact = contacts[lowest.key] {
            let point = position[contact.bone] + rotation[contact.bone].act(contact.offset)
            let dy = lowest.value.y - point.y
            for i in bones.indices { position[i].y += dy }
        }

        flattenToes(&rotation, position)

        for i in bones.indices {
            if let p = parent[i] {
                local[i].rotation = rotation[p].inverse * rotation[i]
                local[i].translation = rotation[p].inverse.act(position[i] - position[p])
            } else {
                // The root joint carries the Blender-to-app axis change, so it takes app-space values.
                local[i].rotation = rotation[i]
                local[i].translation = position[i]
            }
        }
        model.jointTransforms = local
        lastPositions = Dictionary(uniqueKeysWithValues: bones.indices.map { (bones[$0], position[$0]) })
    }

    /// The shoulders rise a little as the arms lift past 60 degrees, like a real shoulder blade:
    /// a quarter of the extra lift, at most 15 degrees. Left is +X, so the left collarbone turns
    /// the other way about the forward axis from the right.
    private func shoulderLift(_ bone: String, _ ours: [String: (q: simd_quatf, p: SIMD3<Float>)]) -> simd_quatf? {
        guard bone == "clavicle_l" || bone == "clavicle_r",
              let arm = ours[bone == "clavicle_l" ? "lShoulder" : "rShoulder"] else { return nil }
        let direction = arm.q.act([0, -1, 0])
        let raised = acos(max(-1, min(1, -direction.y))) * 180 / .pi
        guard raised > 60 else { return nil }
        let degrees = min((raised - 60) * 0.25, 15)
        return simd_quatf(angle: degrees * .pi / 180 * (bone == "clavicle_l" ? 1 : -1), axis: [0, 0, 1])
    }

    /// On tiptoe (heel up, ball of the foot on the floor) the toes stay flat on the floor,
    /// bending at the ball instead of the whole shoe tipping onto its point.
    private func flattenToes(_ rotation: inout [simd_quatf], _ position: [SIMD3<Float>]) {
        for side in ["l", "r"] {
            guard let ball = index["ball_" + side], position[ball].y < 0.06 else { continue }
            let toes = (rotation[ball] * restRotation[ball].inverse).act([0, 0, 1])
            guard toes.y < -0.02 else { continue }
            let flat = normalize(SIMD3<Float>(toes.x, 0, toes.z))
            let angle = acos(max(-1, min(1, dot(normalize(toes), flat))))
            let fix = simd_quatf(from: normalize(toes), to: flat)
            rotation[ball] = (angle > 1.05 ? simd_slerp(simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), fix, 1.05 / angle) : fix) * rotation[ball]
        }
    }

    /// World positions of every bone from the last `apply`, in the app's space (tests and debugging).
    private(set) var lastPositions: [String: SIMD3<Float>] = [:]

    /// Whether bone `i` is `ancestor` or below it in the skeleton.
    private func isBelow(_ i: Int, _ ancestor: Int) -> Bool {
        var current: Int? = i
        while let c = current {
            if c == ancestor { return true }
            current = parent[c]
        }
        return false
    }
}

/// Stands in for the coach if the bundled model can't be loaded.
final class MissingBody: CoachBody {
    let root = Entity()
    var scale: Float { 1 }
    var headHeight: Float { 0.25 }
    func apply(_ pose: Pose) {}
    func blink(_ closed: Float) {}
    func restyle(_ look: CoachLook) {}
}
