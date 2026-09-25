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

    /// A stretch of warm plaster wall with a skirting board, for the wall sit. `position` is
    /// [x, height, z of the wall's face]. One-sided (faces the coach, back faces culled), so
    /// turning the coach round never puts a wall between the camera and the coach.
    private static func wall(_ prop: Prop) -> Entity {
        var plaster = PhysicallyBasedMaterial()
        plaster.baseColor = .init(tint: UIColor(red: 0.96, green: 0.92, blue: 0.86, alpha: 1))
        plaster.roughness = .init(floatLiteral: 0.9)
        plaster.metallic = .init(floatLiteral: 0)
        var skirting = plaster
        skirting.baseColor = .init(tint: UIColor(red: 0.88, green: 0.83, blue: 0.76, alpha: 1))
        let height = prop.position[1], width: Float = 1.4
        let wall = Entity()
        wall.position = [prop.position[0], 0, prop.position[2]]
        let panel = ModelEntity(mesh: .generatePlane(width: width, height: height), materials: [plaster])
        panel.position = [0, height / 2, 0]
        wall.addChild(panel)
        let board = ModelEntity(mesh: .generatePlane(width: width, height: 0.1), materials: [skirting])
        board.position = [0, 0.05, 0.003]
        wall.addChild(board)
        return wall
    }

    static func mat() -> Entity {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(red: 0.17, green: 0.6, blue: 0.55, alpha: 1))
        m.roughness = .init(floatLiteral: 0.85)
        m.metallic = .init(floatLiteral: 0)
        let mat = ModelEntity(mesh: .generateBox(size: [0.66, 0.01, matLength], cornerRadius: 0.005), materials: [m])
        mat.transform = matTransform(endingAt: nil)
        return mat
    }

    private static let matLength: Float = 1.8
    private static let matFront: Float = 0.8

    /// The mat's placement: from its front edge back to `wallZ` when there's a wall, otherwise
    /// its full length.
    static func matTransform(endingAt wallZ: Float?) -> Transform {
        let back = max(wallZ ?? matFront - matLength, matFront - matLength)
        let length = matFront - back
        return Transform(scale: [1, 1, length / matLength], rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                         translation: [0, -0.007, (matFront + back) / 2])
    }

    static func prop(_ prop: Prop) -> Entity? {
        guard prop.position.count == 3 else { return nil }
        if prop.type == "wall" { return wall(prop) }
        guard prop.type == "chair" else { return nil }
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
