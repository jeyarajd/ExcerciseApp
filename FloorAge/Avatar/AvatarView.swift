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

    private let library = ExerciseLibrary.shared
    private lazy var rig = AvatarRig(rig: library.rig)
    private var clip: ExerciseClip?
    private var time: Double = 0
    private var blendFrom: Pose?
    private var blendTime: Double = 0
    private var lastPose: Pose?
    private var propsAnchor = Entity()
    private var updateSubscription: Cancellable?
    private var yaw: Float = 0.45
    private var distance: Float = 3.4
    private let camera = PerspectiveCamera()
    private let turntable = Entity()
    private weak var view: ARView?

    init(exerciseID: String? = nil) {
        super.init()
        if let id = exerciseID, let exercise = library.exercise(id) {
            play(exercise)
        }
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

    func seek(to t: Double) {
        time = t
        blendFrom = nil
    }

    // MARK: - View

    func makeView(dark: Bool) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(dark ? UIColor(white: 0.1, alpha: 1) : UIColor(red: 0.97, green: 0.95, blue: 0.91, alpha: 1))

        let world = AnchorEntity(world: .zero)
        world.addChild(AvatarSet.floor(dark: dark))
        turntable.addChild(AvatarSet.mat())
        turntable.addChild(rig.root)
        turntable.addChild(propsAnchor)
        world.addChild(turntable)

        let sun = DirectionalLight()
        sun.light.intensity = 2800
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 6, depthBias: 2)
        sun.look(at: .zero, from: [1.2, 3.2, 2.4], relativeTo: nil)
        world.addChild(sun)

        let fill = DirectionalLight()
        fill.light.intensity = 900
        fill.look(at: .zero, from: [-2.5, 1.5, 1], relativeTo: nil)
        world.addChild(fill)

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

    private func tick(_ dt: TimeInterval) {
        guard let clip else { return }
        if isPlaying {
            let previous = time
            time += dt * speed
            if let repTime = clip.exercise.repTime, crossed(repTime, from: previous, to: time, duration: clip.duration) {
                onRep?()
            }
        }
        var pose = clip.sample(at: time)
        if let from = blendFrom {
            blendTime += dt
            let u = Float(min(blendTime / 0.6, 1))
            pose = from.blended(to: pose, by: u * u * (3 - 2 * u))
            if u >= 1 { blendFrom = nil }
        }
        rig.apply(pose)
        lastPose = pose
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
        let target = SIMD3<Float>(0, 0.8, 0)
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
