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
    /// The eyes are shut for an eyes-closed hold and must open again when it ends.
    private var eyesHeldShut = false
    private var propsAnchor = Entity()
    private let mat = AvatarSet.mat()
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
    /// Turn the head towards the viewer (session intros and rests).
    var looksAtCamera = false
    /// Onboarding: the coach turns slowly on the spot so you see them from every side. When it
    /// stops, the view eases back to the exercise's best angle.
    var turnsSlowly = false {
        didSet {
            guard oldValue, !turnsSlowly, let exercise else { return }
            // Take the short way back round.
            yaw = yaw.truncatingRemainder(dividingBy: 2 * .pi)
            if yaw > .pi { yaw -= 2 * .pi }
            turnToBestAngle(for: exercise)
        }
    }
    private var lookAmount: Float = 0
    private var relaxAmount: Float = 0
    /// The camera easing to the current exercise's best angle.
    private var yawAnimation: (from: Float, to: Float, t: Double)?
    private var userTurned = false
    /// Set by a pinch: the person's own zoom wins over the automatic fit until a double-tap reset.
    private var userZoomed = false
    /// The distance `setCamera` chose, for the double-tap reset.
    private var baseDistance: Float = 3.4
    /// Where the camera aims across the screen, following the middle of the body so a fold or a
    /// lunge stays in frame.
    private var framingX: Float = 0
    /// How much further back the camera sits so outstretched arms, a raised leg or a chair fit
    /// the view's width (eased, like `framingX`).
    private var fitDistance: Float = 0
    /// Head, hands, feet and pelvis across the whole clip, plus the corners of its props: what
    /// the camera keeps in view. Measured once per exercise, so the view doesn't pump with each rep.
    private var framePoints: [SIMD3<Float>] = []
    /// Off for close-ups (the portrait), which frame the face on purpose.
    private var fitsWholeBody = true
    /// Off for small coaches in cards: no mat and no wall, just the coach and any chair.
    private var showsScenery = true
    private lazy var solver = PoseSolver(rig: library.rig)

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
        measureFrame()
        turnToBestAngle(for: exercise)
    }

    /// Eases the view round to the angle that shows this exercise best, unless the person has
    /// turned the coach themselves or the coach is copying the camera. Instant with Reduce Motion.
    private func turnToBestAngle(for exercise: Exercise) {
        guard live == nil, !userTurned, let degrees = exercise.cameraYaw else { return }
        let target = Float(degrees * .pi / 180)
        guard abs(target - yaw) > 0.01 else { return }
        if UIAccessibility.isReduceMotionEnabled || view == nil {
            yaw = target
            yawAnimation = nil
            updateCamera()
        } else {
            yawAnimation = (yaw, target, 0)
        }
    }

    func play(id: String, mirrored: Bool = false) {
        if let exercise = library.exercise(id) { play(exercise, mirrored: mirrored) }
    }

    func restart() {
        time = 0
    }

    /// Frames the camera: `distance` from the coach, looking at `height` (metres). Close-ups use
    /// about 1.1 and 1.55.
    func setCamera(distance: Float, height: Float, fitsWholeBody: Bool = true) {
        self.distance = distance
        baseDistance = distance
        cameraHeight = height
        self.fitsWholeBody = fitsWholeBody
        updateCamera()
    }

    /// Makes the coach copy a live pose, like a mirror (turned to face the viewer). Pass nil to go
    /// back to demonstrating the exercise. The exercise's props, such as the chair, stay in place.
    func follow(_ pose: Pose?) {
        if let pose {
            if live == nil {
                yawBeforeLive = yaw
                yaw = 0
                yawAnimation = nil
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

    #if DEBUG
    /// The audit's view from a chosen side, as if the person had turned the coach.
    func turn(toDegrees degrees: Double) {
        userTurned = true
        yawAnimation = nil
        yaw = Float(degrees * .pi / 180)
        updateCamera()
    }
    #endif

    func seek(to t: Double) {
        time = t
        blendFrom = nil
    }

    // MARK: - View

    /// `interactive` false leaves out the turn, zoom and reset gestures and lets touches through
    /// (small coaches inside cards). `showsMat` false leaves out the exercise mat and the wall.
    func makeView(dark: Bool, interactive: Bool = true, showsMat: Bool = true) -> ARView {
        showsScenery = showsMat
        rebuildProps()
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        // Transparent, so the coach stands on the app's own background (AppBackground).
        view.environment.background = .color(.clear)
        view.backgroundColor = .clear
        view.isOpaque = false
        if let light = Self.studioLight {
            view.environment.lighting.resource = light
            view.environment.lighting.intensityExponent = dark ? 0.75 : 0.6
        }

        let world = AnchorEntity(world: .zero)

        if showsMat {
            turntable.addChild(mat)
            fitMatToWall()
        }
        if let contactShadow {
            turntable.addChild(contactShadow)
        }
        turntable.addChild(rig.root)
        turntable.addChild(propsAnchor)
        world.addChild(turntable)

        // Soft key light with a shadow, a gentle fill, and a rim light to lift the coach off the backdrop.
        let key = DirectionalLight()
        // Softer key and a stronger rim keep darker skin tones shaped against the warm background.
        key.light.intensity = 1800
        key.shadow = DirectionalLightComponent.Shadow(maximumDistance: 5, depthBias: 1.5)
        key.look(at: [0, 0.8, 0], from: [1.6, 3.4, 2.6], relativeTo: nil)
        world.addChild(key)

        let fill = DirectionalLight()
        fill.light.intensity = 600
        fill.look(at: [0, 0.8, 0], from: [-2.5, 1.4, 1.5], relativeTo: nil)
        world.addChild(fill)

        let rim = DirectionalLight()
        rim.light.intensity = 1200
        rim.look(at: [0, 1, 0], from: [-0.8, 2.2, -3], relativeTo: nil)
        world.addChild(rim)

        camera.camera.fieldOfViewInDegrees = 38
        world.addChild(camera)
        view.scene.addAnchor(world)
        updateCamera()

        if interactive {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.delegate = self
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            let reset = UITapGestureRecognizer(target: self, action: #selector(handleReset))
            reset.numberOfTapsRequired = 2
            view.addGestureRecognizer(pan)
            view.addGestureRecognizer(pinch)
            view.addGestureRecognizer(reset)
        } else {
            view.isUserInteractionEnabled = false
        }

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
        if turnsSlowly, yawAnimation == nil {
            yaw += Float(dt) * 0.3  // one turn in about 20 s
            updateCamera()
        }
        if var animation = yawAnimation {
            animation.t += dt
            let u = Float(min(animation.t / 0.6, 1))
            yaw = animation.from + (animation.to - animation.from) * u * u * (3 - 2 * u)
            yawAnimation = u < 1 ? animation : nil
            updateCamera()
        }
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
        frame(pose, dt: dt)
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

        // Standing at ease: a slow weight shift. Talking to you: the head turns your way.
        let ease = Float(min(dt * 3, 1))
        let relaxed = live == nil && exercise?.id == "idle"
        relaxAmount += ((relaxed ? 1 : 0) - relaxAmount) * ease
        lookAmount += ((looksAtCamera && live == nil ? 1 : 0) - lookAmount) * ease
        pose = pose.withWeightShift(time: lifeTime, amount: relaxAmount)
            .lookingAtViewer(bodyYaw: yaw * 180 / .pi, amount: lookAmount)

        // Eyes shut through the held part of an eyes-closed exercise.
        if let clip, clip.exercise.eyesClosed == true, live == nil, clip.frames.count > 2, clip.duration > 0 {
            let local = time.truncatingRemainder(dividingBy: clip.duration)
            if local >= clip.frames[1].t, local <= clip.frames[clip.frames.count - 2].t {
                rig.blink(1)
                eyesHeldShut = true
                return pose
            }
        }
        // The hold is over (or another exercise started): open the eyes and blink normally again.
        if eyesHeldShut {
            eyesHeldShut = false
            rig.blink(0)
            nextBlink = lifeTime + Double.random(in: 2.5...5.5)
        }

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
        for prop in clip?.props ?? [] where showsScenery || prop.type != "wall" {
            if let entity = AvatarSet.prop(prop) { propsAnchor.addChild(entity) }
        }
        fitMatToWall()
    }

    /// With a wall behind the coach, the mat ends at the wall's face instead of running into it.
    private func fitMatToWall() {
        let wallZ = clip?.props.first { $0.type == "wall" && $0.position.count == 3 }?.position[2]
        mat.transform = AvatarSet.matTransform(endingAt: wallZ)
    }

    private func measureFrame() {
        guard let clip else { return framePoints = [] }
        var points: [SIMD3<Float>] = []
        let steps = 24
        for i in 0...steps {
            let pose = clip.sample(at: clip.duration * Double(i) / Double(steps))
            let world = solver.world(pose.angles, pelvis: pose.pelvis)
            points += ["head", "lWrist", "rWrist", "lAnkle", "rAnkle", "pelvis"].compactMap { world[$0]?.p }
        }
        // Chairs are kept in view; a wall behind the coach is scenery and may run off the edges.
        for prop in clip.props where prop.type == "chair" && prop.position.count == 3 {
            let centre = SIMD3<Float>(prop.position[0], 0, prop.position[2])
            for dx: Float in [-0.25, 0.25] {
                for dz: Float in [-0.22, 0.22] { points.append(centre + SIMD3(dx, 0, dz)) }
            }
        }
        framePoints = points
    }

    /// Keeps the whole exercise in view as the coach is turned: the camera aims at the middle of
    /// the head, hands, feet and props, and backs off when they're wider than the view.
    private func frame(_ pose: Pose, dt: TimeInterval) {
        let scale = rig.scale
        let xs = framePoints.map { ($0.x * cos(yaw) + $0.z * sin(yaw)) * scale }
        guard let low = xs.min(), let high = xs.max() else { return }
        let target = (low + high) / 2
        var fit: Float = 0
        if fitsWholeBody, !userZoomed, let bounds = view?.bounds, bounds.height > 0 {
            // What the view shows per metre of distance, up and across (the field of view is vertical).
            let halfHeight = tan(Float(camera.camera.fieldOfViewInDegrees) * .pi / 360)
            let halfWidth = halfHeight * Float(bounds.width / bounds.height)
            // Fingers, hair and the chair's depth reach past the joints, plus a little air.
            let across = ((high - low) / 2 + 0.32) / max(halfWidth, 0.01)
            let top = ((framePoints.map(\.y).max() ?? 1.5) + rig.headHeight) * scale
            let up = (top - cameraHeight + 0.2) / halfHeight
            fit = max(0, max(across, up) - distance)
        }
        let ease = Float(min(dt * 2.5, 1))
        let step = (target - framingX) * ease, fitStep = (fit - fitDistance) * ease
        guard abs(step) > 0.0005 || abs(fitStep) > 0.001 else { return }
        framingX += step
        fitDistance += fitStep
        updateCamera()
    }

    private func updateCamera() {
        turntable.transform.rotation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        let target = SIMD3<Float>(framingX, cameraHeight, 0)
        camera.look(at: target, from: target + SIMD3(0, 0.35, distance + fitDistance), relativeTo: nil)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let dx = Float(gesture.translation(in: gesture.view).x)
        gesture.setTranslation(.zero, in: gesture.view)
        yaw += dx * 0.01
        yawAnimation = nil
        userTurned = true
        updateCamera()
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        // Start from where the fit put the camera, then hand the zoom to the person.
        distance = max(2.0, min(6.0, (distance + fitDistance) / Float(gesture.scale)))
        fitDistance = 0
        userZoomed = true
        gesture.scale = 1
        updateCamera()
    }

    @objc private func handleReset() {
        userTurned = false
        userZoomed = false
        yawAnimation = nil
        yaw = exercise?.cameraYaw.map { Float($0 * .pi / 180) } ?? 0.45
        distance = baseDistance
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

/// SwiftUI wrapper around the RealityKit view. Drag to turn the coach, pinch to zoom, double-tap to
/// reset, unless `interactive` is false.
struct AvatarView: UIViewRepresentable {
    @ObservedObject var controller: AvatarController
    var interactive = true
    var showsMat = true
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> ARView {
        controller.makeView(dark: colorScheme == .dark, interactive: interactive, showsMat: showsMat)
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
