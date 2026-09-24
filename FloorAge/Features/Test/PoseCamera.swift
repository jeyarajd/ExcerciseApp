import AVFoundation
import SwiftUI
import Vision

/// The front camera plus Apple's on-device body pose detection. Frames are analysed on the phone
/// and thrown away: nothing is recorded, saved or sent.
final class PoseCamera: NSObject, ObservableObject {
    enum Status: Equatable { case off, starting, running, denied, unavailable }

    /// Scripted movement for the Debug demo screens (no camera needed).
    enum Demo { case chairStand, balance, reach }

    @Published private(set) var status = Status.off
    @Published private(set) var pose: BodyPose?
    /// Size of the (portrait) frames, to line the skeleton up with the preview.
    @Published private(set) var frameSize = CGSize(width: 720, height: 1280)
    /// Called on the main thread with every detected pose.
    var onPose: ((BodyPose) -> Void)?

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "floorage.posecamera")
    private let output = AVCaptureVideoDataOutput()
    private var configured = false
    private let demo: Demo?
    private var demoTimer: Timer?
    private var demoStart = Date()

    init(demo: Demo? = nil) {
        self.demo = demo
    }

    var isDemo: Bool { demo != nil }

    func start() {
        guard status == .off || status == .denied else { return }
        if let demo {
            startDemo(demo)
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            status = .starting
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.run() } else { self.status = .denied }
                }
            }
        default:
            status = .denied
        }
    }

    func stop() {
        demoTimer?.invalidate()
        demoTimer = nil
        pose = nil
        guard status != .off else { return }
        status = .off
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func run() {
        status = .starting
        queue.async { [self] in
            if !configured {
                guard configure() else {
                    DispatchQueue.main.async { self.status = .unavailable }
                    return
                }
                configured = true
            }
            session.startRunning()
            DispatchQueue.main.async { if self.status == .starting { self.status = .running } }
        }
    }

    /// Front camera, portrait, mirrored like a mirror so moving left moves left on screen.
    private func configure() -> Bool {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        guard session.canAddInput(input), session.canAddOutput(output) else { return false }
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
        return true
    }

    private func publish(_ pose: BodyPose?, size: CGSize? = nil) {
        if let size, size != frameSize { frameSize = size }
        self.pose = pose
        if let pose { onPose?(pose) }
    }

    // MARK: - Demo

    private func startDemo(_ demo: Demo) {
        status = .running
        demoStart = Date()
        demoTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            let t = Date().timeIntervalSince(self.demoStart)
            let pose: BodyPose = switch demo {
            case .chairStand:
                // Sit, stand, sit… about one stand every 2.4 seconds.
                .sample(rise: (1 - cos(t / 2.4 * 2 * .pi)) / 2)
            case .balance:
                .sample(lift: t > 1 ? min((t - 1) * 2, 1) : 0)
            case .reach:
                .sample(fold: min(t / 3, 1), wristDepth: 0.25)
            }
            self.publish(pose)
        }
    }
}

extension PoseCamera: AVCaptureVideoDataOutputSampleBufferDelegate {
    private static let joints: [(VNHumanBodyPoseObservation.JointName, BodyJoint)] = [
        (.nose, .nose), (.neck, .neck), (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
        (.leftElbow, .leftElbow), (.rightElbow, .rightElbow), (.leftWrist, .leftWrist), (.rightWrist, .rightWrist), (.leftHip, .leftHip), (.rightHip, .rightHip),
        (.leftKnee, .leftKnee), (.rightKnee, .rightKnee), (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle),
    ]

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let size = CMSampleBufferGetImageBuffer(sampleBuffer).map {
            CGSize(width: CVPixelBufferGetWidth($0), height: CVPixelBufferGetHeight($0))
        }
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up)
        var pose: BodyPose?
        if (try? handler.perform([request])) != nil,
           let observation = request.results?.first,
           let points = try? observation.recognizedPoints(.all) {
            var joints: [BodyJoint: CGPoint] = [:]
            for (name, joint) in Self.joints {
                if let point = points[name], point.confidence > 0.3 { joints[joint] = point.location }
            }
            if !joints.isEmpty { pose = BodyPose(joints: joints) }
        }
        DispatchQueue.main.async { self.publish(pose, size: size) }
    }
}

// MARK: - Views

/// The live camera with the tracked skeleton drawn on top. The whole frame is shown (not cropped),
/// so people can check their feet are in view.
struct CameraStage: View {
    @ObservedObject var camera: PoseCamera
    let feature: Feature
    /// Joints this test measures, highlighted on the figure.
    var focus: Set<BodyJoint> = []
    /// What the camera currently reads ("Seated", "Foot up"…), shown top right.
    var reading: String?

    var body: some View {
        ZStack {
            Color.black
            if camera.isDemo {
                LinearGradient(colors: [Color(white: 0.16), Color(white: 0.3)], startPoint: .top, endPoint: .bottom)
                    .aspectRatio(camera.frameSize, contentMode: .fit)
            } else {
                CameraPreview(session: camera.session)
            }
            BodyOverlay(pose: camera.pose, frameSize: camera.frameSize, feature: feature, focus: focus)
            if let reading, camera.pose?.legsVisible == true {
                Text(reading)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(feature.gradient, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 1))
                    .shadow(color: feature.colors.last!.opacity(0.5), radius: 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 44)
                    .padding(.trailing, 14)
                    .animation(.snappy, value: reading)
            }
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// A glowing figure over the camera image: a head, a torso and rounded limbs in the test's
/// colours, with the joints the test measures pulsing. Mapped the same way the preview fits the frame.
private struct BodyOverlay: View {
    let pose: BodyPose?
    let frameSize: CGSize
    let feature: Feature
    let focus: Set<BodyJoint>

    private static let limbs: [[BodyJoint]] = [
        [.leftShoulder, .leftElbow, .leftWrist], [.rightShoulder, .rightElbow, .rightWrist],
        [.leftHip, .leftKnee, .leftAnkle], [.rightHip, .rightKnee, .rightAnkle],
    ]

    var body: some View {
        TimelineView(.animation(paused: focus.isEmpty || pose == nil)) { timeline in
            let pulse = (sin(timeline.date.timeIntervalSinceReferenceDate * 4) + 1) / 2
            Canvas { context, size in
                guard let pose else { return }
                draw(pose, in: &context, size: size, pulse: pulse)
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(_ pose: BodyPose, in context: inout GraphicsContext, size: CGSize, pulse: Double) {
        let scale = min(size.width / frameSize.width, size.height / frameSize.height)
        let drawn = CGSize(width: frameSize.width * scale, height: frameSize.height * scale)
        func place(_ joint: BodyJoint) -> CGPoint? {
            pose[joint].map {
                CGPoint(x: $0.x * drawn.width - (drawn.width - size.width) / 2,
                        y: (1 - $0.y) * drawn.height - (drawn.height - size.height) / 2)
            }
        }
        func mid(_ a: CGPoint?, _ b: CGPoint?) -> CGPoint? {
            switch (a, b) {
            case let (a?, b?): CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            default: a ?? b
            }
        }

        // Size everything from the body, so a person far away gets a slimmer figure. The shin keeps
        // its length whether standing, sitting or folded, so it steadies the trunk measure.
        let shoulders = mid(place(.leftShoulder), place(.rightShoulder)) ?? place(.neck)
        let hips = mid(place(.leftHip), place(.rightHip))
        let knee = mid(place(.leftKnee), place(.rightKnee)), ankle = mid(place(.leftAnkle), place(.rightAnkle))
        let shin = knee.flatMap { k in ankle.map { hypot(k.x - $0.x, k.y - $0.y) } } ?? 0
        let trunk = max(shoulders.flatMap { s in hips.map { hypot(s.x - $0.x, s.y - $0.y) } } ?? 120, shin * 1.3)
        let limbWidth = min(max(trunk * 0.16, 7), 24)
        let shading = GraphicsContext.Shading.linearGradient(Gradient(colors: feature.colors),
                                                             startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: size.height))

        var limbs = Path()
        for chain in Self.limbs {
            let points = chain.compactMap(place)
            guard points.count >= 2 else { continue }
            limbs.addLines(points)
        }
        if let neck = place(.neck) ?? shoulders, let hips {
            limbs.move(to: neck)
            limbs.addLine(to: hips)
        }

        var torso = Path()
        let corners = [place(.leftShoulder), place(.rightShoulder), place(.rightHip), place(.leftHip)].compactMap { $0 }
        if corners.count == 4 {
            torso.addLines(corners)
            torso.closeSubpath()
        }

        var head = Path()
        if let nose = place(.nose) ?? place(.neck).map({ CGPoint(x: $0.x, y: $0.y - trunk * 0.25) }) {
            let r = max(trunk * 0.2, 9)
            head.addEllipse(in: CGRect(x: nose.x - r, y: nose.y - r * 1.1, width: r * 2, height: r * 2.2))
        }

        let style = StrokeStyle(lineWidth: limbWidth, lineCap: .round, lineJoin: .round)
        // Soft glow underneath.
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: limbWidth * 0.9))
            glow.opacity = 0.75
            glow.stroke(limbs, with: shading, style: StrokeStyle(lineWidth: limbWidth * 1.8, lineCap: .round, lineJoin: .round))
            glow.fill(torso, with: shading)
            glow.fill(head, with: shading)
        }
        context.fill(torso, with: shading)
        context.opacity = 0.9
        context.fill(torso, with: .color(.white.opacity(0.12)))
        context.opacity = 1
        context.stroke(limbs, with: shading, style: style)
        // A light core down each limb gives the figure some depth.
        context.stroke(limbs, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: limbWidth * 0.3, lineCap: .round, lineJoin: .round))
        context.fill(head, with: shading)
        context.stroke(head, with: .color(.white.opacity(0.85)), lineWidth: 2)
        context.stroke(torso, with: .color(.white.opacity(0.5)), lineWidth: 1.5)

        for joint in [BodyJoint.leftElbow, .rightElbow, .leftWrist, .rightWrist, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle, .leftHip, .rightHip] {
            guard let p = place(joint) else { continue }
            if focus.contains(joint) {
                let ring = limbWidth * (0.9 + 0.6 * pulse)
                context.stroke(Path(ellipseIn: CGRect(x: p.x - ring, y: p.y - ring, width: ring * 2, height: ring * 2)),
                               with: .color(.white.opacity(0.9 - 0.5 * pulse)), lineWidth: 2.5)
                let dot = limbWidth * 0.45
                context.fill(Path(ellipseIn: CGRect(x: p.x - dot, y: p.y - dot, width: dot * 2, height: dot * 2)), with: .color(.white))
            } else {
                let dot = limbWidth * 0.28
                context.fill(Path(ellipseIn: CGRect(x: p.x - dot, y: p.y - dot, width: dot * 2, height: dot * 2)), with: .color(.white.opacity(0.9)))
            }
        }
    }
}
