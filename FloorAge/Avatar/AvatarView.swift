import Combine
import RealityKit
import SwiftUI
import UIKit

/// Drives one coach avatar: which exercise is playing, speed, pause, and rep callbacks.
final class AvatarController: NSObject, ObservableObject {
    @Published private(set) var exercise: Exercise?
    @Published var isPlaying = true
    @Published var speed: Double = 1

    /// Called on the main thread each time the animation passes the exercise's `repTime`.
    var onRep: (() -> Void)?
    /// Called on the main thread when the animation reaches a keyframe with a `cue`.
    var onCue: ((String) -> Void)?

    private let library = ExerciseLibrary.shared
    private lazy var rig: CoachBody = Self.makeBody(library.rig)
    private var styleObserver: NSObjectProtocol?
    private var clip: ExerciseClip?
    private var time: Double = 0
    private var blendFrom: Pose?
    private var blendTime: Double = 0
    private var lastPose: Pose?
    private let contactShadow = AvatarSet.contactShadow()
    /// Always-running clock for breathing and blinking, even while paused.
    private var lifeTime: Double = 0
    private var nextBlink: Double = 2
    private var propsAnchor = Entity()
    private var updateSubscription: Cancellable?
    private var lookObserver: NSObjectProtocol?
    private var yaw: Float = 0.45
    private var distance: Float = 3.4
    private var cameraHeight: Float = 0.8
    private let camera = PerspectiveCamera()
    private let turntable = Entity()
    private weak var view: ARView?
    /// While set, the coach copies this pose (from the camera) instead of playing the exercise.
    private var live: Pose?
    private var yawBeforeLive: Float?

    init(exerciseID: String? = nil) {
        super.init()
        if let id = exerciseID, let exercise = library.exercise(id) {
            play(exercise)
        }
        lookObserver = NotificationCenter.default.addObserver(forName: CoachLook.changed, object: nil, queue: .main) { [weak self] _ in
            self?.rig.restyle(.current)
        }
        styleObserver = NotificationCenter.default.addObserver(forName: CoachStyle.changed, object: nil, queue: .main) { [weak self] _ in
            self?.swapBody()
        }
    }

    deinit {
        [lookObserver, styleObserver].compactMap { $0 }.forEach(NotificationCenter.default.removeObserver)
    }

    /// The realistic coach when it's bundled and chosen, otherwise the stylized one.
    private static func makeBody(_ rig: Rig) -> CoachBody {
        if CoachStyle.current == .realistic, let body = RealisticCoach(look: .current, rig: rig) { return body }
        return AvatarRig(rig: rig)
    }

    private func swapBody() {
        let parent = rig.root.parent
        rig.root.removeFromParent()
        rig = Self.makeBody(library.rig)
        parent?.addChild(rig.root)
        if let lastPose { rig.apply(lastPose) }
    }

    func play(_ exercise: Exercise, mirrored: Bool = false) {
        blendFrom = lastPose
        blendTime = 0
        clip = ExerciseClip(exercise: exercise, library: library, mirrored: mirrored)
        time = 0
        self.exercise = exercise
        rebuildProps()
    }

    func play(id: String, mirrored: Bool = false) {
        if let exercise = library.exercise(id) { play(exercise, mirrored: mirrored) }
    }

    func restart() {
        time = 0
    }

    /// Frames the camera: `distance` from the coach, looking at `height` (metres). Close-ups use
    /// about 1.1 and 1.55.
    func setCamera(distance: Float, height: Float) {
        self.distance = distance
        cameraHeight = height
        updateCamera()
    }

    /// Makes the coach copy a live pose, like a mirror (turned to face the viewer). Pass nil to go
    /// back to demonstrating the exercise. The exercise's props, such as the chair, stay in place.
    func follow(_ pose: Pose?) {
        if let pose {
            if live == nil {
                yawBeforeLive = yaw
                yaw = 0
                updateCamera()
            }
            live = pose
        } else if live != nil {
            live = nil
            blendFrom = lastPose
            blendTime = 0
            if let yawBeforeLive { yaw = yawBeforeLive }
            updateCamera()
        }
    }

    func seek(to t: Double) {
        time = t
        blendFrom = nil
    }

    // MARK: - View

    func makeView(dark: Bool) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        // Transparent, so the coach stands on the app's own background (AppBackground).
        view.environment.background = .color(.clear)
        view.backgroundColor = .clear
        view.isOpaque = false
        if let light = Self.studioLight {
            view.environment.lighting.resource = light
            view.environment.lighting.intensityExponent = 0.6
        }

        let world = AnchorEntity(world: .zero)

        turntable.addChild(AvatarSet.mat())
        if let contactShadow {
            turntable.addChild(contactShadow)
        }
        turntable.addChild(rig.root)
        turntable.addChild(propsAnchor)
        world.addChild(turntable)

        // Soft key light with a shadow, a gentle fill, and a rim light to lift the coach off the backdrop.
        let key = DirectionalLight()
        key.light.intensity = 2200
        key.shadow = DirectionalLightComponent.Shadow(maximumDistance: 5, depthBias: 1.5)
        key.look(at: [0, 0.8, 0], from: [1.6, 3.4, 2.6], relativeTo: nil)
        world.addChild(key)

        let fill = DirectionalLight()
        fill.light.intensity = 600
        fill.look(at: [0, 0.8, 0], from: [-2.5, 1.4, 1.5], relativeTo: nil)
        world.addChild(fill)

        let rim = DirectionalLight()
        rim.light.intensity = 900
        rim.look(at: [0, 1, 0], from: [-0.8, 2.2, -3], relativeTo: nil)
        world.addChild(rim)

        camera.camera.fieldOfViewInDegrees = 38
        world.addChild(camera)
        view.scene.addAnchor(world)
        updateCamera()

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let reset = UITapGestureRecognizer(target: self, action: #selector(handleReset))
        reset.numberOfTapsRequired = 2
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(reset)

        updateSubscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.tick(event.deltaTime)
        }
        self.view = view
        if let clip { rig.apply(clip.sample(at: 0)) }
        return view
    }

    /// Image-based lighting from a generated warm studio sky: soft light from above, darker below.
    private static let studioLight: EnvironmentResource? = {
        let width = 128, height = 64
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let gradient = CGGradient(colorSpace: CGColorSpaceCreateDeviceRGB(), colorComponents: [
                  1.0, 0.98, 0.94, 1,   // sky
                  0.95, 0.9, 0.84, 1,   // horizon
                  0.45, 0.4, 0.36, 1,   // floor
              ], locations: [0, 0.5, 1], count: 3) else { return nil }
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: .zero, options: [])
        guard let image = ctx.makeImage() else { return nil }
        return try? EnvironmentResource(equirectangular: image)
    }()

    private func tick(_ dt: TimeInterval) {
        if let live {
            // Ease towards each new camera pose so small jitters don't show.
            let pose = lastPose.map { $0.blended(to: live, by: Float(min(dt * 14, 1))) } ?? live
            lastPose = pose
            rig.apply(alive(pose, dt: dt))
            contactShadow?.position = [pose.pelvis.x, 0.004, pose.pelvis.z + 0.04]
            return
        }
        guard let clip else { return }
        if isPlaying {
            let previous = time
            time += dt * speed
            if let repTime = clip.exercise.repTime, crossed(repTime, from: previous, to: time, duration: clip.duration) {
                onRep?()
            }
            for keyframe in clip.exercise.keyframes {
                guard let cue = keyframe.cue else { continue }
                // A cue at the start of the clip also fires when it loops back round.
                let mark = keyframe.t <= 0 ? clip.duration : keyframe.t
                if crossed(mark, from: previous, to: time, duration: clip.duration) || (previous == 0 && keyframe.t <= 0) {
                    onCue?(cue)
                }
            }
        }
        var pose = clip.sample(at: time)
        if let from = blendFrom {
            blendTime += dt
            let u = Float(min(blendTime / 0.6, 1))
            pose = from.blended(to: pose, by: u * u * (3 - 2 * u))
            if u >= 1 { blendFrom = nil }
        }
        lastPose = pose
        rig.apply(alive(pose, dt: dt))
        // The contact shadow follows the body over the floor.
        contactShadow?.position = [pose.pelvis.x, 0.004, pose.pelvis.z + 0.04]
    }

    /// Small layers that make the coach feel alive: breathing through the chest and shoulders,
    /// and a natural blink every few seconds.
    private func alive(_ pose: Pose, dt: TimeInterval) -> Pose {
        lifeTime += dt
        var pose = pose
        let breath = Float(sin(lifeTime * 2 * .pi / 3.8))
        pose.angles["chest", default: .zero].x -= 1.3 * breath
        pose.angles["neck", default: .zero].x += 0.7 * breath
        pose.angles["lShoulder", default: .zero].z += 0.8 * breath
        pose.angles["rShoulder", default: .zero].z -= 0.8 * breath

        let sinceBlink = lifeTime - nextBlink
        if sinceBlink >= 0.16 {
            nextBlink = lifeTime + Double.random(in: 2.5...5.5)
            rig.blink(0)
        } else if sinceBlink >= 0 {
            rig.blink(Float(1 - abs(sinceBlink / 0.08 - 1)))  // close then open over 0.16 s
        }
        return pose
    }

    private func crossed(_ mark: Double, from a: Double, to b: Double, duration: Double) -> Bool {
        guard duration > 0, b > a else { return false }
        if b - a >= duration { return true }
        let la = a.truncatingRemainder(dividingBy: duration)
        let lb = b.truncatingRemainder(dividingBy: duration)
        if lb >= la { return la < mark && mark <= lb }
        // wrapped past the end of the clip
        return mark > la || mark <= lb
    }

    private func rebuildProps() {
        for child in propsAnchor.children.map({ $0 }) { child.removeFromParent() }
        for prop in clip?.props ?? [] {
            if let entity = AvatarSet.prop(prop) { propsAnchor.addChild(entity) }
        }
    }

    private func updateCamera() {
        turntable.transform.rotation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        let target = SIMD3<Float>(0, cameraHeight, 0)
        camera.look(at: target, from: target + SIMD3(0, 0.35, distance), relativeTo: nil)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let dx = Float(gesture.translation(in: gesture.view).x)
        gesture.setTranslation(.zero, in: gesture.view)
        yaw += dx * 0.01
        updateCamera()
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        distance = max(2.0, min(6.0, distance / Float(gesture.scale)))
        gesture.scale = 1
        updateCamera()
    }

    @objc private func handleReset() {
        yaw = 0.45
        distance = 3.4
        updateCamera()
    }
}

extension AvatarController: UIGestureRecognizerDelegate {
    /// Only horizontal drags turn the coach, so vertical drags still scroll the screen.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let v = pan.velocity(in: pan.view)
        return abs(v.x) > abs(v.y)
    }
}

/// SwiftUI wrapper around the RealityKit view. Drag to turn the coach, pinch to zoom, double-tap to reset.
struct AvatarView: UIViewRepresentable {
    @ObservedObject var controller: AvatarController
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> ARView {
        controller.makeView(dark: colorScheme == .dark)
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
