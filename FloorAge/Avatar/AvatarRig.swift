import RealityKit
import UIKit

/// Which coach demonstrates: follows the person's gender from their profile (see `AppModel`).
enum CoachLook: String, Codable, CaseIterable, Identifiable {
    case female, male

    var id: String { rawValue }
    var label: String { self == .female ? String(localized: "Woman") : String(localized: "Man") }

    /// Posted when the person changes the gender in their profile, so live coaches restyle.
    static let changed = Notification.Name("CoachLookChanged")

    /// Stored by `AppModel` whenever the profile changes. A `-coachLook male` launch argument
    /// overrides it (screenshots).
    static var current: CoachLook {
        CoachLook(rawValue: UserDefaults.standard.string(forKey: "coachLook") ?? "") ?? .female
    }

    /// The coach for a gender when no coach was chosen: a man for men, otherwise a woman.
    init(matching gender: Gender?) {
        self = gender == .male ? .male : .female
    }

    /// Switches every coach on screen right away (onboarding previews the choice).
    static func preview(_ look: CoachLook) {
        guard look != current else { return }
        UserDefaults.standard.set(look.rawValue, forKey: "coachLook")
        NotificationCenter.default.post(name: changed, object: nil)
    }
}

/// Realistic (MakeHuman) or friendly cartoon coach. Realistic is the default when bundled.
enum CoachStyle: String, CaseIterable, Identifiable {
    case realistic, friendly

    var id: String { rawValue }
    var label: String { self == .realistic ? String(localized: "Realistic") : String(localized: "Friendly cartoon") }

    static let changed = Notification.Name("CoachStyleChanged")

    static var current: CoachStyle {
        get { CoachStyle(rawValue: UserDefaults.standard.string(forKey: "coachStyle") ?? "") ?? .realistic }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "coachStyle")
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }
}

/// Colours and build for the coach figure.
struct AvatarStyle {
    var look: CoachLook
    var skin: UIColor
    var hair: UIColor
    var top: UIColor
    /// Lower panel of the colour-blocked top.
    var panel = UIColor(red: 0.84, green: 0.36, blue: 0.1, alpha: 1)
    var bottom: UIColor
    var shoe = UIColor(white: 0.97, alpha: 1)
    var sole: UIColor
    var accent: UIColor

    static func coach(_ look: CoachLook) -> AvatarStyle {
        let orange = UIColor(red: 0.95, green: 0.52, blue: 0.16, alpha: 1)
        switch look {
        case .female:
            return AvatarStyle(look: .female,
                               skin: UIColor(red: 0.82, green: 0.6, blue: 0.46, alpha: 1),
                               hair: UIColor(red: 0.09, green: 0.06, blue: 0.05, alpha: 1),
                               top: orange,
                               bottom: UIColor(red: 0.2, green: 0.2, blue: 0.38, alpha: 1),
                               sole: orange,
                               accent: UIColor(red: 0.2, green: 0.2, blue: 0.38, alpha: 1))
        case .male:
            return AvatarStyle(look: .male,
                               skin: UIColor(red: 0.73, green: 0.51, blue: 0.37, alpha: 1),
                               hair: UIColor(red: 0.07, green: 0.06, blue: 0.06, alpha: 1),
                               top: orange,
                               bottom: UIColor(red: 0.2, green: 0.22, blue: 0.27, alpha: 1),
                               sole: UIColor(white: 0.55, alpha: 1),
                               accent: UIColor(white: 0.97, alpha: 1))
        }
    }
}

/// The coach figure: one entity per rig joint, with sculpted meshes hung off each joint.
/// Rotating a joint entity swings everything below it, exactly like the preview script's FK.
/// Proportions follow the fixed skeleton in `exercises.json`, so every pose works for both coaches.
/// The look is deliberately stylized (soft shapes, a slightly larger head, a simple friendly face)
/// because near-realistic faces read as eerie.
final class AvatarRig {
    let root = Entity()
    private(set) var joints: [String: Entity] = [:]
    private var parts: [Entity] = []
    private var eyes: [Entity] = []

    init(rig: Rig, style: AvatarStyle = .coach(.current)) {
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

    /// 0 = eyes open, 1 = closed.
    func blink(_ closed: Float) {
        for eye in eyes { eye.scale = [1, max(0.08, 1 - closed), 1] }
    }

    /// Swaps the clothes and body for another coach, keeping the current pose.
    func restyle(_ style: AvatarStyle) {
        parts.forEach { $0.removeFromParent() }
        parts = []
        eyes = []
        dress(style)
    }

    // MARK: - Body

    private func dress(_ style: AvatarStyle) {
        let female = style.look == .female
        let skin = material(style.skin, roughness: 0.62, clearcoat: 0.08)
        let top = material(style.top, roughness: 0.78, sheen: UIColor(white: 0.18, alpha: 1))
        let panel = material(style.panel, roughness: 0.78, sheen: UIColor(white: 0.15, alpha: 1))
        let bottom = material(style.bottom, roughness: 0.72, sheen: UIColor(white: 0.15, alpha: 1))
        let hair = material(style.hair, roughness: 0.4, clearcoat: 0.35)
        let shoe = material(style.shoe, roughness: 0.55)
        let sole = material(style.sole, roughness: 0.65)
        let accent = material(style.accent, roughness: 0.6)

        // Torso: overlapping pieces on pelvis, spine and chest so it bends smoothly.
        let hips: [Ring] = female
            ? [Ring(0.12, 0, 0), Ring(0.11, 0.125, 0.085), Ring(0.05, 0.16, 0.1), Ring(-0.02, 0.178, 0.108, z: -0.008),
               Ring(-0.08, 0.17, 0.104, z: -0.01), Ring(-0.125, 0.13, 0.085, z: -0.006), Ring(-0.15, 0, 0)]
            : [Ring(0.12, 0, 0), Ring(0.11, 0.13, 0.085), Ring(0.05, 0.16, 0.097), Ring(-0.02, 0.172, 0.102, z: -0.005),
               Ring(-0.08, 0.168, 0.1, z: -0.006), Ring(-0.125, 0.13, 0.082), Ring(-0.15, 0, 0)]
        attach("pelvis", MeshKit.lathe(hips), bottom)
        if female {
            // Slim waistband where the top meets the leggings.
            attach("pelvis", MeshKit.lathe([Ring(0.105, 0, 0), Ring(0.1, 0.134, 0.09), Ring(0.07, 0.15, 0.097),
                                            Ring(0.06, 0.153, 0.099), Ring(0.055, 0, 0)]), accent)
        }

        // Where the waist (spine) and ribs (chest) pieces meet, their cross-sections are the same
        // shape, so the join is a level line: the edge of the colour-blocked top.
        let waist: [Ring] = female
            ? [Ring(-0.06, 0, 0), Ring(-0.05, 0.13, 0.088), Ring(0.04, 0.124, 0.085), Ring(0.14, 0.126, 0.086),
               Ring(0.26, 0.128, 0.088), Ring(0.285, 0.1, 0.068), Ring(0.3, 0, 0)]
            : [Ring(-0.06, 0, 0), Ring(-0.05, 0.14, 0.09), Ring(0.04, 0.142, 0.092), Ring(0.14, 0.143, 0.093),
               Ring(0.26, 0.145, 0.094), Ring(0.285, 0.112, 0.073), Ring(0.3, 0, 0)]
        attach("spine", MeshKit.lathe(waist), panel)

        let ribs: [Ring] = female
            ? [Ring(-0.12, 0, 0), Ring(-0.1, 0.1, 0.069), Ring(-0.04, 0.122, 0.084), Ring(0.03, 0.124, 0.085),
               Ring(0.06, 0.132, 0.09), Ring(0.1, 0.145, 0.096, z: 0.008), Ring(0.14, 0.162, 0.092, z: 0.004),
               Ring(0.18, 0.174, 0.082), Ring(0.205, 0.148, 0.066), Ring(0.228, 0.085, 0.052), Ring(0.245, 0.04, 0.035),
               Ring(0.255, 0, 0)]
            : [Ring(-0.12, 0, 0), Ring(-0.1, 0.11, 0.071), Ring(-0.04, 0.138, 0.089), Ring(0.03, 0.141, 0.091),
               Ring(0.06, 0.15, 0.097), Ring(0.1, 0.168, 0.104, z: 0.005), Ring(0.14, 0.19, 0.1, z: 0.003),
               Ring(0.18, 0.2, 0.088), Ring(0.205, 0.172, 0.07), Ring(0.228, 0.1, 0.058), Ring(0.245, 0.05, 0.042),
               Ring(0.255, 0, 0)]
        attach("chest", MeshKit.lathe(ribs), top)

        // Neck, then the head as one group so face and hair scale together.
        let neckR: Float = female ? 0.05 : 0.058
        attach("neck", MeshKit.lathe([Ring(0.1, 0, 0), Ring(0.09, neckR * 0.9, neckR * 0.95), Ring(0.04, neckR, neckR),
                                      Ring(-0.02, neckR * 1.12, neckR * 1.06), Ring(-0.06, 0, 0)]), skin)
        let head = Entity()
        head.scale = SIMD3(repeating: female ? 1.12 : 1.15)
        head.position = [0, -0.022, 0]
        joints["head"]?.addChild(head)
        parts.append(head)
        let skull = [Ring(0.232, 0, 0), Ring(0.222, 0.052, 0.058), Ring(0.196, 0.08, 0.088), Ring(0.155, 0.09, 0.098),
                     Ring(0.115, 0.089, 0.098), Ring(0.075, female ? 0.08 : 0.083, 0.093, z: 0.004),
                     Ring(0.04, female ? 0.066 : 0.076, 0.083, z: 0.009), Ring(0.014, female ? 0.046 : 0.06, 0.066, z: 0.014),
                     Ring(-0.004, 0.026, 0.04, z: 0.016), Ring(-0.01, 0, 0, z: 0.016)]
        attach(head, MeshKit.lathe(skull), skin)
        face(style, in: head, skin: skin, hair: hair)
        hairStyle(style, in: head, hair: hair)

        // Arms.
        let armScale: Float = female ? 0.88 : 1
        for side in ["l", "r"] {
            attach(side + "Shoulder", MeshKit.limb(length: 0.27, radii: [0.046, 0.044, 0.04, 0.036].map { $0 * armScale }, top: -0.02), skin)
            if !female {
                let sleeve = [Ring(0.05, 0, 0), Ring(0.035, 0.047, 0.049), Ring(0.0, 0.053, 0.053), Ring(-0.11, 0.05, 0.05),
                              Ring(-0.118, 0.044, 0.044), Ring(-0.095, 0, 0)]
                attach(side + "Shoulder", MeshKit.lathe(sleeve), top)
            }
            attach(side + "Elbow", MeshKit.limb(length: 0.21, radii: [0.037, 0.038, 0.031, 0.026].map { $0 * armScale }), skin)
            let palm = [Ring(0.012, 0, 0), Ring(0.008, 0.014, 0.022), Ring(-0.02, 0.017, 0.033), Ring(-0.058, 0.016, 0.034),
                        Ring(-0.086, 0.013, 0.027), Ring(-0.102, 0, 0)]
            attach(side + "Wrist", MeshKit.lathe(palm.map { $0.scaled(armScale) }), skin)
            let thumb = attach(side + "Wrist", MeshKit.limb(length: 0.03 * armScale, radii: [0.012, 0.01].map { $0 * armScale }),
                               skin, at: [0, -0.02 * armScale, 0.026 * armScale])
            thumb?.orientation = simd_quatf(angle: -0.55, axis: [1, 0, 0])
        }

        // Legs.
        for side in ["l", "r"] {
            let thigh: [Float] = female ? [0.088, 0.083, 0.07, 0.056, 0.048] : [0.09, 0.085, 0.073, 0.058, 0.05]
            attach(side + "Hip", MeshKit.limb(length: 0.42, radii: thigh), female ? bottom : skin)
            attach(side + "Knee", MeshKit.limb(length: 0.4, radii: female ? [0.047, 0.051, 0.042, 0.033, 0.029] : [0.05, 0.056, 0.046, 0.036, 0.032]),
                   female ? bottom : skin)
            if !female {
                // Shorts that follow the thigh, and ankle socks.
                let shorts = [Ring(0.07, 0, 0), Ring(0.05, 0.088, 0.09), Ring(0.0, 0.097, 0.097), Ring(-0.1, 0.092, 0.092),
                              Ring(-0.19, 0.085, 0.085), Ring(-0.2, 0.074, 0.074), Ring(-0.15, 0, 0)]
                attach(side + "Hip", MeshKit.lathe(shorts), bottom)
                attach(side + "Knee", MeshKit.lathe([Ring(-0.31, 0, 0), Ring(-0.325, 0.036, 0.036), Ring(-0.4, 0.035, 0.035), Ring(-0.43, 0, 0)]),
                       material(.white, roughness: 0.9))
            }
            shoes(side, upper: shoe, sole: sole)
        }
    }

    /// A simple, friendly face: glossy eyes with a sparkle, soft brows and a small smile.
    private func face(_ style: AvatarStyle, in head: Entity, skin: PhysicallyBasedMaterial, hair: PhysicallyBasedMaterial) {
        let female = style.look == .female
        let eye = material(UIColor(red: 0.12, green: 0.08, blue: 0.06, alpha: 1), roughness: 0.15, clearcoat: 1)
        let sparkle = material(.white, roughness: 0.2)
        let mouth = material(UIColor(red: 0.45, green: 0.2, blue: 0.18, alpha: 1), roughness: 0.5)
        for x: Float in [-0.033, 0.033] {
            let group = Entity()
            group.position = [x, 0.118, 0.092]
            head.addChild(group)
            parts.append(group)
            eyes.append(group)
            attach(group, MeshKit.ellipsoid(0.0115, 0.0155, 0.007), eye)
            attach(group, MeshKit.ellipsoid(0.0038, 0.0038, 0.002), sparkle, at: [0.004, 0.005, 0.0062])
            let brow = MeshKit.tube(arc(center: [x, 0.128, 0.1], radius: 0.026, from: 0.33 * .pi, to: 0.67 * .pi, tilt: x > 0 ? -0.12 : 0.12),
                                    radius: female ? 0.0032 : 0.0042)
            attach(head, brow, hair)
            if female {
                attach(head, MeshKit.ellipsoid(0.014, 0.008, 0.003), material(UIColor(red: 0.86, green: 0.5, blue: 0.45, alpha: 1), roughness: 0.8),
                       at: [x > 0 ? 0.052 : -0.052, 0.088, 0.078])
            }
            attach(head, MeshKit.ellipsoid(0.011, 0.02, 0.014), skin, at: [x > 0 ? 0.088 : -0.088, 0.108, 0])
        }
        attach(head, MeshKit.ellipsoid(0.009, 0.011, 0.009), skin, at: [0, 0.094, 0.097])
        attach(head, MeshKit.tube(arc(center: [0, 0.08, 0.097], radius: 0.021, from: 1.22 * .pi, to: 1.78 * .pi), radius: 0.0036), mouth)
    }

    /// Points on a circular arc in the face plane (x, y), pushed onto the curved face.
    private func arc(center: SIMD3<Float>, radius: Float, from: Float, to: Float, tilt: Float = 0) -> [SIMD3<Float>] {
        (0...12).map { i in
            let a = from + (to - from) * Float(i) / 12
            let x = center.x + radius * cos(a), y = center.y + radius * sin(a) + tilt * (x - center.x)
            // Follow the face's curve so the line sits on the skin.
            let z = center.z - 0.35 * (x * x - center.x * center.x) / 0.09
            return [x, y, z]
        }
    }

    private func hairStyle(_ style: AvatarStyle, in head: Entity, hair: PhysicallyBasedMaterial) {
        switch style.look {
        case .male:
            // Classic swept-back quiff: short, neat sides and volume rising at the front.
            let cap = [Ring(0.25, 0, 0), Ring(0.243, 0.056, 0.062, z: -0.006), Ring(0.222, 0.086, 0.097, z: -0.008),
                       Ring(0.185, 0.094, 0.105, z: -0.011), Ring(0.145, 0.094, 0.102, z: -0.019), Ring(0.1, 0.089, 0.091, z: -0.031),
                       Ring(0.075, 0, 0, z: -0.04)]
            attach(head, MeshKit.lathe(cap), hair)
            let quiff = attach(head, MeshKit.ellipsoid(0.066, 0.034, 0.07), hair, at: [0.006, 0.238, 0.028])
            quiff.orientation = simd_quatf(angle: -0.32, axis: [1, 0, 0]) * simd_quatf(angle: 0.08, axis: [0, 0, 1])
            let sweep = attach(head, MeshKit.ellipsoid(0.058, 0.026, 0.075), hair, at: [-0.008, 0.25, -0.02])
            sweep.orientation = simd_quatf(angle: -0.15, axis: [1, 0, 0])
            for x: Float in [-0.085, 0.085] {
                attach(head, MeshKit.ellipsoid(0.009, 0.024, 0.014), hair, at: [x, 0.118, 0.028])
            }
        case .female:
            let cap = [Ring(0.256, 0, 0), Ring(0.247, 0.062, 0.068, z: -0.004), Ring(0.224, 0.092, 0.101, z: -0.005),
                       Ring(0.185, 0.1, 0.108, z: -0.009), Ring(0.13, 0.101, 0.106, z: -0.02), Ring(0.08, 0.094, 0.092, z: -0.03),
                       Ring(0.045, 0.07, 0.07, z: -0.04), Ring(0.03, 0, 0, z: -0.045)]
            attach(head, MeshKit.lathe(cap), hair)
            // Side-swept fringe and a sporty high bun with a hair tie.
            let fringe = attach(head, MeshKit.ellipsoid(0.07, 0.026, 0.05), hair, at: [0.02, 0.208, 0.036])
            fringe.orientation = simd_quatf(angle: 0.3, axis: [0, 0, 1]) * simd_quatf(angle: -0.3, axis: [1, 0, 0])
            attach(head, MeshKit.ellipsoid(0.05, 0.046, 0.046), hair, at: [0, 0.275, -0.055])
            attach(head, MeshKit.ellipsoid(0.034, 0.012, 0.034), material(style.top, roughness: 0.6), at: [0, 0.243, -0.05])
        }
    }

    /// Sneakers from heel (-0.072) to toe (0.165) with the sole on the floor contact (y -0.075).
    private func shoes(_ side: String, upper: PhysicallyBasedMaterial, sole: PhysicallyBasedMaterial) {
        // (length position, half width, top of shoe); bottom is the floor contact.
        let outline: [(Float, Float, Float)] = [(0.168, 0, -0.052), (0.158, 0.03, -0.043), (0.12, 0.045, -0.032),
                                                (0.06, 0.048, -0.02), (0.0, 0.046, -0.004), (-0.04, 0.043, 0.004),
                                                (-0.066, 0.032, -0.008), (-0.074, 0, -0.03)]
        // The lathe runs along Y; rotating +90° about X turns Y into forward Z and ring depth into down.
        func rings(bottom: Float, top: (Float) -> Float, widen: Float) -> [Ring] {
            outline.map { l, w, t in
                let hi = top(t), center = (hi + bottom) / 2
                return Ring(l + (w == 0 ? (l > 0 ? widen : -widen) : 0), w == 0 ? 0 : w + widen, max(0, (hi - bottom) / 2), z: -center)
            }
        }
        let turn = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        attach(side + "Ankle", MeshKit.lathe(rings(bottom: -0.068, top: { $0 }, widen: 0)), upper)?.orientation = turn
        attach(side + "Ankle", MeshKit.lathe(rings(bottom: -0.076, top: { _ in -0.058 }, widen: 0.004)), sole)?.orientation = turn
    }

    // MARK: - Helpers

    private func material(_ color: UIColor, roughness: Float, sheen: UIColor? = nil, clearcoat: Float = 0) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color)
        m.roughness = .init(floatLiteral: roughness)
        m.metallic = .init(floatLiteral: 0)
        if let sheen { m.sheen = .init(tint: sheen) }
        if clearcoat > 0 {
            m.clearcoat = .init(floatLiteral: clearcoat)
            m.clearcoatRoughness = .init(floatLiteral: 0.2)
        }
        return m
    }

    @discardableResult
    private func attach(_ joint: String, _ mesh: MeshResource, _ material: PhysicallyBasedMaterial,
                        at position: SIMD3<Float> = .zero) -> ModelEntity? {
        guard let parent = joints[joint] else { return nil }
        return attach(parent, mesh, material, at: position)
    }

    @discardableResult
    private func attach(_ parent: Entity, _ mesh: MeshResource, _ material: PhysicallyBasedMaterial,
                        at position: SIMD3<Float> = .zero) -> ModelEntity {
        let model = ModelEntity(mesh: mesh, materials: [material])
        model.position = position
        parent.addChild(model)
        parts.append(model)
        return model
    }
}

extension AvatarRig: CoachBody {
    func restyle(_ look: CoachLook) { restyle(AvatarStyle.coach(look)) }
}

/// The studio around the coach: a seamless curved backdrop, a yoga mat and exercise props.
enum AvatarSet {
    static func backgroundColor(dark: Bool) -> UIColor {
        dark ? UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1) : UIColor(red: 0.95, green: 0.93, blue: 0.9, alpha: 1)
    }

    /// Floor that curves up into a back wall, so there's no horizon line behind the coach.
    static func stage(dark: Bool) -> Entity {
        var outline: [SIMD2<Float>] = [[0, 6], [0, -1.2]]
        let radius: Float = 1.4
        for i in 1...12 {
            let a = Float(i) / 12 * .pi / 2
            outline.append([radius - radius * cos(a), -1.2 - radius * sin(a)])
        }
        outline.append([8, -1.2 - radius])
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: dark ? UIColor(white: 0.2, alpha: 1) : UIColor(red: 0.93, green: 0.9, blue: 0.86, alpha: 1))
        m.roughness = .init(floatLiteral: 1)
        m.metallic = .init(floatLiteral: 0)
        let stage = ModelEntity(mesh: MeshKit.sweep(outline, width: 16), materials: [m])
        stage.position = [0, -0.013, 0]
        return stage
    }

    /// A soft round shadow under the coach's feet, so they look grounded on the app background.
    static func contactShadow() -> ModelEntity? {
        let size = 128
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let gradient = CGGradient(colorSpace: CGColorSpaceCreateDeviceGray(),
                                        colorComponents: [1, 1, 0.45, 1, 0, 1], locations: [0, 0.45, 1], count: 3)
        else { return nil }
        let c = CGPoint(x: size / 2, y: size / 2)
        ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(size / 2), options: [])
        // RealityKit reads opacity from the texture's colour, so white means shadow, black means clear.
        guard let image = ctx.makeImage(),
              let mask = try? TextureResource(image: image, options: .init(semantic: .raw)) else { return nil }
        var material = UnlitMaterial(color: .black)
        material.blending = .transparent(opacity: .init(scale: 0.32, texture: .init(mask)))
        let shadow = ModelEntity(mesh: .generatePlane(width: 0.75, depth: 0.55), materials: [material])
        shadow.position = [0, 0.004, 0]
        return shadow
    }

    static func mat() -> Entity {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(red: 0.17, green: 0.6, blue: 0.55, alpha: 1))
        m.roughness = .init(floatLiteral: 0.85)
        m.metallic = .init(floatLiteral: 0)
        let mat = ModelEntity(mesh: .generateBox(size: [0.66, 0.01, 1.8], cornerRadius: 0.005), materials: [m])
        mat.position = [0, -0.007, -0.1]
        return mat
    }

    static func prop(_ prop: Prop) -> Entity? {
        guard prop.type == "chair", prop.position.count == 3 else { return nil }
        var wood = PhysicallyBasedMaterial()
        wood.baseColor = .init(tint: UIColor(red: 0.55, green: 0.37, blue: 0.22, alpha: 1))
        wood.roughness = .init(floatLiteral: 0.55)
        wood.metallic = .init(floatLiteral: 0)
        wood.clearcoat = .init(floatLiteral: 0.4)
        let chair = Entity()
        let top = prop.position[1]
        chair.position = [prop.position[0], 0, prop.position[2]]

        let seat = ModelEntity(mesh: .generateBox(size: [0.46, 0.04, 0.42], cornerRadius: 0.015), materials: [wood])
        seat.position = [0, top - 0.02, 0]
        chair.addChild(seat)
        for x: Float in [-0.2, 0.2] {
            for z: Float in [-0.18, 0.18] {
                let leg = ModelEntity(mesh: MeshKit.limb(length: top - 0.06, radii: [0.02, 0.017]), materials: [wood])
                leg.position = [x, top - 0.03, z]
                chair.addChild(leg)
            }
            let post = ModelEntity(mesh: MeshKit.limb(length: 0.42, radii: [0.017, 0.018]), materials: [wood])
            post.position = [x, top + 0.44, -0.19]
            chair.addChild(post)
        }
        for y: Float in [0.3, 0.42] {
            let rail = ModelEntity(mesh: .generateBox(size: [0.44, 0.06, 0.025], cornerRadius: 0.01), materials: [wood])
            rail.position = [0, top + y, -0.19]
            chair.addChild(rail)
        }
        return chair
    }
}
