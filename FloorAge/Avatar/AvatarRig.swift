import RealityKit
import UIKit

/// Colours for the coach figure.
struct AvatarStyle {
    var skin = UIColor(red: 0.55, green: 0.36, blue: 0.24, alpha: 1)
    var hair = UIColor(red: 0.08, green: 0.07, blue: 0.07, alpha: 1)
    var shirt = UIColor(red: 0.95, green: 0.55, blue: 0.16, alpha: 1)
    var pants = UIColor(red: 0.13, green: 0.17, blue: 0.29, alpha: 1)
    var shoes = UIColor(white: 0.95, alpha: 1)
}

/// The coach figure: one entity per rig joint, with simple rounded meshes hung off each joint.
/// Rotating a joint entity swings everything below it, exactly like the preview script's FK.
final class AvatarRig {
    let root = Entity()
    private(set) var joints: [String: Entity] = [:]

    init(rig: Rig, style: AvatarStyle = AvatarStyle()) {
        for joint in rig.joints {
            let entity = Entity()
            entity.name = joint.name
            entity.position = SIMD3(joint.offset)
            if let parent = joint.parent, let parentEntity = joints[parent] {
                parentEntity.addChild(entity)
            } else {
                root.addChild(entity)
            }
            joints[joint.name] = entity
        }
        dress(style)
    }

    func apply(_ pose: Pose) {
        for (name, entity) in joints {
            entity.transform.rotation = PoseSolver.localRotation(pose.angles[name] ?? .zero)
        }
        joints["pelvis"]?.position = pose.pelvis
    }

    // MARK: - Meshes

    private func dress(_ style: AvatarStyle) {
        let skin = material(style.skin)
        let shirt = material(style.shirt)
        let pants = material(style.pants)
        let shoes = material(style.shoes)
        let hair = material(style.hair, roughness: 0.9)

        attach("pelvis", box([0.30, 0.17, 0.19]), pants, at: [0, -0.03, 0])
        attach("spine", box([0.30, 0.26, 0.18]), shirt, at: [0, 0.11, 0])
        attach("chest", box([0.38, 0.27, 0.21]), shirt, at: [0, 0.12, 0])
        attach("neck", box([0.08, 0.10, 0.08]), skin, at: [0, 0.03, 0])

        attach("head", .generateSphere(radius: 0.11), skin, at: [0, 0.1, 0])
        attach("head", .generateSphere(radius: 0.114), hair, at: [0, 0.135, -0.012], scale: [1, 0.72, 1])
        for x: Float in [-0.037, 0.037] {
            attach("head", .generateSphere(radius: 0.012), material(.black), at: [x, 0.11, 0.1])
        }
        attach("head", .generateSphere(radius: 0.016), skin, at: [0, 0.085, 0.108])

        for side in ["l", "r"] {
            attach(side + "Shoulder", .generateSphere(radius: 0.065), shirt, at: [0, -0.01, 0])
            attach(side + "Shoulder", box([0.12, 0.13, 0.12]), shirt, at: [0, -0.06, 0])
            attach(side + "Shoulder", box([0.085, 0.29, 0.085]), skin, at: [0, -0.14, 0])
            attach(side + "Elbow", .generateSphere(radius: 0.042), skin, at: .zero)
            attach(side + "Elbow", box([0.072, 0.26, 0.072]), skin, at: [0, -0.125, 0])
            attach(side + "Wrist", .generateSphere(radius: 0.045), skin, at: [0, -0.05, 0], scale: [0.8, 1.3, 0.55])

            attach(side + "Hip", .generateSphere(radius: 0.075), pants, at: .zero)
            attach(side + "Hip", box([0.14, 0.45, 0.14]), pants, at: [0, -0.215, 0])
            attach(side + "Knee", .generateSphere(radius: 0.062), pants, at: .zero)
            attach(side + "Knee", box([0.11, 0.43, 0.11]), pants, at: [0, -0.21, 0])
            attach(side + "Ankle", box([0.1, 0.075, 0.24]), shoes, at: [0, -0.04, 0.05])
        }
    }

    private func box(_ size: SIMD3<Float>) -> MeshResource {
        let corner = min(size.x, size.y, size.z) * 0.45
        return .generateBox(size: size, cornerRadius: corner)
    }

    private func material(_ color: UIColor, roughness: Float = 0.65) -> SimpleMaterial {
        SimpleMaterial(color: color, roughness: .float(roughness), isMetallic: false)
    }

    private func attach(_ joint: String, _ mesh: MeshResource, _ material: SimpleMaterial,
                        at position: SIMD3<Float>, scale: SIMD3<Float> = .one) {
        guard let parent = joints[joint] else { return }
        let model = ModelEntity(mesh: mesh, materials: [material])
        model.position = position
        model.scale = scale
        parent.addChild(model)
    }
}

/// Floor mat and exercise props (chair) around the coach.
enum AvatarSet {
    static func mat() -> Entity {
        let mat = ModelEntity(
            mesh: .generateBox(size: [0.9, 0.012, 1.9], cornerRadius: 0.005),
            materials: [SimpleMaterial(color: UIColor(red: 0.16, green: 0.62, blue: 0.56, alpha: 1), roughness: .float(0.9), isMetallic: false)]
        )
        mat.position = [0, -0.006, -0.1]
        return mat
    }

    static func floor(dark: Bool) -> Entity {
        let colour = dark ? UIColor(white: 0.16, alpha: 1) : UIColor(red: 0.93, green: 0.9, blue: 0.85, alpha: 1)
        let floor = ModelEntity(
            mesh: .generatePlane(width: 8, depth: 8),
            materials: [SimpleMaterial(color: colour, roughness: .float(1), isMetallic: false)]
        )
        floor.position = [0, -0.013, 0]
        return floor
    }

    static func prop(_ prop: Prop) -> Entity? {
        guard prop.type == "chair", prop.position.count == 3 else { return nil }
        let wood = SimpleMaterial(color: UIColor(red: 0.6, green: 0.42, blue: 0.25, alpha: 1), roughness: .float(0.8), isMetallic: false)
        let chair = Entity()
        let top = prop.position[1]
        chair.position = [prop.position[0], 0, prop.position[2]]

        let seat = ModelEntity(mesh: .generateBox(size: [0.46, 0.04, 0.42], cornerRadius: 0.01), materials: [wood])
        seat.position = [0, top - 0.02, 0]
        chair.addChild(seat)
        for x: Float in [-0.2, 0.2] {
            for z: Float in [-0.18, 0.18] {
                let leg = ModelEntity(mesh: .generateBox(size: [0.035, top - 0.04, 0.035]), materials: [wood])
                leg.position = [x, (top - 0.04) / 2, z]
                chair.addChild(leg)
            }
        }
        let back = ModelEntity(mesh: .generateBox(size: [0.46, 0.45, 0.035], cornerRadius: 0.01), materials: [wood])
        back.position = [0, top + 0.24, -0.2]
        chair.addChild(back)
        return chair
    }
}
