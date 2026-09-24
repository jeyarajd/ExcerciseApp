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
        // `-demoPhase <seconds>` starts the scripted movement further along (for screenshots).
        demoStart = Date().addingTimeInterval(-UserDefaults.standard.double(forKey: "demoPhase"))
        demoTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            let t = Date().timeIntervalSince(self.demoStart)
            let pose: BodyPose = switch demo {
            case .chairStand:
                // Sit, stand, sit… about one stand every 2.4 seconds.
                .sample(rise: (1 - cos(t / 2.4 * 2 * .pi)) / 2, armsCrossed: true)
            case .balance:
                .sample(lift: t > 1 ? min((t - 1) * 2, 1) : 0, armSpread: 0.05)
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

/// A mannequin-style body over the camera image, built from the tracked joints: a shaped torso,
/// limbs that taper like real ones, neck, head, hands and feet, filled as one smooth silhouette
/// with a light edge, soft shading and a glow in the test's colours. The joints the test measures
/// pulse. Mapped the same way the preview fits the frame.
private struct BodyOverlay: View {
    let pose: BodyPose?
    let frameSize: CGSize
    let feature: Feature
    let focus: Set<BodyJoint>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: focus.isEmpty || pose == nil || reduceMotion)) { timeline in
            let pulse = (sin(timeline.date.timeIntervalSinceReferenceDate * 4) + 1) / 2
            Canvas { context, size in
                guard let pose else { return }
                let placed = pose.joints.mapValues { place($0, in: size) }
                guard let figure = Mannequin(joints: placed) else { return }
                draw(figure, in: &context, size: size, pulse: pulse)
            }
        }
        .allowsHitTesting(false)
    }

    private func place(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let scale = min(size.width / frameSize.width, size.height / frameSize.height)
        let drawn = CGSize(width: frameSize.width * scale, height: frameSize.height * scale)
        return CGPoint(x: p.x * drawn.width - (drawn.width - size.width) / 2,
                       y: (1 - p.y) * drawn.height - (drawn.height - size.height) / 2)
    }

    private func draw(_ figure: Mannequin, in context: inout GraphicsContext, size: CGSize, pulse: Double) {
        let body = figure.silhouette(grow: 0)
        let edge = figure.silhouette(grow: 2.5)
        let fill = GraphicsContext.Shading.linearGradient(Gradient(colors: feature.colors),
                                                          startPoint: figure.bounds.origin,
                                                          endPoint: CGPoint(x: figure.bounds.maxX, y: figure.bounds.maxY))
        // Glow behind the body.
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: figure.unit * 0.12))
            glow.opacity = 0.7
            glow.fill(edge, with: fill)
        }
        // A light edge, then the body itself.
        context.fill(edge, with: .color(.white.opacity(0.85)))
        context.fill(body, with: fill)
        // Light from the top left and a shadow to the bottom right give it volume.
        context.drawLayer { shade in
            shade.clip(to: body)
            shade.fill(Path(figure.bounds.insetBy(dx: -20, dy: -20)),
                       with: .linearGradient(Gradient(colors: [.white.opacity(0.35), .clear, .black.opacity(0.28)]),
                                             startPoint: figure.bounds.origin,
                                             endPoint: CGPoint(x: figure.bounds.maxX, y: figure.bounds.maxY)))
            // A soft sheen down each limb makes them look round.
            shade.addFilter(.blur(radius: figure.unit * 0.03))
            for (a, b, width) in figure.sheens {
                var line = Path()
                line.move(to: a)
                line.addLine(to: b)
                shade.stroke(line, with: .color(.white.opacity(0.38)), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
        // The joints this test measures.
        for joint in focus {
            guard let p = figure.joints[joint] else { continue }
            let ring = figure.unit * (0.12 + 0.07 * pulse)
            context.stroke(Path(ellipseIn: CGRect(x: p.x - ring, y: p.y - ring, width: ring * 2, height: ring * 2)),
                           with: .color(.white.opacity(0.95 - 0.55 * pulse)), lineWidth: 2.5)
            let dot = figure.unit * 0.045
            context.fill(Path(ellipseIn: CGRect(x: p.x - dot, y: p.y - dot, width: dot * 2, height: dot * 2)), with: .color(.white))
        }
    }
}

/// Body shapes from joint positions (in view points). Sizes follow average human proportions,
/// measured in `unit`: the trunk length, steadied by the shin, which keeps its length in any pose.
private struct Mannequin {
    let joints: [BodyJoint: CGPoint]
    let unit: CGFloat
    private var parts: [(CGFloat) -> Path] = []
    private(set) var sheens: [(CGPoint, CGPoint, CGFloat)] = []
    private(set) var bounds = CGRect.null

    init?(joints: [BodyJoint: CGPoint]) {
        self.joints = joints
        func mid(_ a: BodyJoint, _ b: BodyJoint) -> CGPoint? {
            switch (joints[a], joints[b]) {
            case let (p?, q?): CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
            case let (p, q): p ?? q
            }
        }
        guard let hips = mid(.leftHip, .rightHip), let shoulders = mid(.leftShoulder, .rightShoulder) ?? joints[.neck] else { return nil }
        let shin = [(BodyJoint.leftKnee, BodyJoint.leftAnkle), (.rightKnee, .rightAnkle)]
            .compactMap { pair in joints[pair.0].flatMap { k in joints[pair.1].map { Self.length(k, $0) } } }.max() ?? 0
        unit = max(Self.length(shoulders, hips), shin * 1.3, 20)
        let u = unit

        // Torso: shaped (shoulders, waist, hips) when seen from the front; a rounded column side-on.
        if let ls = joints[.leftShoulder], let rs = joints[.rightShoulder], let lh = joints[.leftHip], let rh = joints[.rightHip],
           Self.length(ls, rs) > u * 0.35 {
            add { grow in Self.torso(ls: ls, rs: rs, lh: lh, rh: rh, unit: u, grow: grow) }
        } else {
            add { grow in Self.capsule(shoulders, hips, u * 0.2 + grow, u * 0.19 + grow) }
        }

        // Neck and head.
        let neckBase = joints[.neck] ?? shoulders
        let up = Self.unitVector(from: hips, to: shoulders)
        let face = joints[.nose] ?? CGPoint(x: neckBase.x + up.x * u * 0.32, y: neckBase.y + up.y * u * 0.32)
        let headAxis = Self.unitVector(from: neckBase, to: face)
        let headCenter = CGPoint(x: face.x + headAxis.x * u * 0.04, y: face.y + headAxis.y * u * 0.04)
        let chin = CGPoint(x: headCenter.x - headAxis.x * u * 0.2, y: headCenter.y - headAxis.y * u * 0.2)
        add { grow in Self.capsule(neckBase, chin, u * 0.1 + grow, u * 0.09 + grow) }
        add { grow in Self.head(center: headCenter, axis: headAxis, unit: u, grow: grow) }

        // Arms: upper arm, forearm, hand.
        for (s, e, w) in [(BodyJoint.leftShoulder, BodyJoint.leftElbow, BodyJoint.leftWrist), (.rightShoulder, .rightElbow, .rightWrist)] {
            guard let shoulder = joints[s] else { continue }
            let elbow = joints[e], wrist = joints[w]
            add { grow in Self.circle(shoulder, u * 0.11 + grow) }
            if let elbow {
                add { grow in Self.capsule(shoulder, elbow, u * 0.1 + grow, u * 0.075 + grow) }
                sheens.append((shoulder, elbow, u * 0.04))
            }
            if let wrist, let from = elbow ?? Optional(shoulder) {
                add { grow in Self.capsule(from, wrist, u * 0.075 + grow, u * 0.055 + grow) }
                let dir = Self.unitVector(from: from, to: wrist)
                let fingertips = CGPoint(x: wrist.x + dir.x * u * 0.17, y: wrist.y + dir.y * u * 0.17)
                add { grow in Self.capsule(wrist, fingertips, u * 0.06 + grow, u * 0.045 + grow) }
                sheens.append((from, wrist, u * 0.03))
            }
        }

        // Legs: thigh, calf, foot.
        for (h, k, a, side) in [(BodyJoint.leftHip, BodyJoint.leftKnee, BodyJoint.leftAnkle, CGFloat(1)), (.rightHip, .rightKnee, .rightAnkle, -1)] {
            guard let hip = joints[h] else { continue }
            let knee = joints[k], ankle = joints[a]
            if let knee {
                add { grow in Self.capsule(hip, knee, u * 0.18 + grow, u * 0.115 + grow) }
                sheens.append((hip, knee, u * 0.06))
            }
            if let ankle, let from = knee ?? Optional(hip) {
                // The calf is fullest just below the knee.
                let calf = CGPoint(x: from.x + (ankle.x - from.x) * 0.3, y: from.y + (ankle.y - from.y) * 0.3)
                add { grow in Self.capsule(from, calf, u * 0.11 + grow, u * 0.115 + grow) }
                add { grow in Self.capsule(calf, ankle, u * 0.115 + grow, u * 0.065 + grow) }
                let toe = CGPoint(x: ankle.x + side * u * 0.1, y: ankle.y + u * 0.07)
                add { grow in Self.capsule(ankle, toe, u * 0.065 + grow, u * 0.05 + grow) }
                sheens.append((from, ankle, u * 0.045))
            }
        }

        bounds = silhouette(grow: 0).boundingRect
    }

    private mutating func add(_ part: @escaping (CGFloat) -> Path) { parts.append(part) }

    /// All the parts merged into one outline; `grow` widens it for the edge and glow.
    func silhouette(grow: CGFloat) -> Path {
        parts.reduce(Path()) { $0.isEmpty ? $1(grow) : $0.union($1(grow)) }
    }

    // MARK: Shapes

    static func length(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y) }

    static func unitVector(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let l = max(length(a, b), 0.001)
        return CGPoint(x: (b.x - a.x) / l, y: (b.y - a.y) / l)
    }

    static func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    /// Two circles joined by their outer tangents: a limb that tapers from `ra` to `rb`.
    static func capsule(_ a: CGPoint, _ b: CGPoint, _ ra: CGFloat, _ rb: CGFloat) -> Path {
        let d = length(a, b)
        guard d > abs(ra - rb) + 0.5 else { return circle(ra >= rb ? a : b, max(ra, rb)) }
        let theta = atan2(b.y - a.y, b.x - a.x)
        let phi = acos((ra - rb) / d)
        var points: [CGPoint] = []
        let steps = 10
        for i in 0...steps {
            let t = theta + phi + (2 * .pi - 2 * phi) * CGFloat(i) / CGFloat(steps)
            points.append(CGPoint(x: a.x + ra * cos(t), y: a.y + ra * sin(t)))
        }
        for i in 0...steps {
            let t = theta - phi + 2 * phi * CGFloat(i) / CGFloat(steps)
            points.append(CGPoint(x: b.x + rb * cos(t), y: b.y + rb * sin(t)))
        }
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }

    /// Shoulders, a narrower waist and hips, with curved sides.
    static func torso(ls: CGPoint, rs: CGPoint, lh: CGPoint, rh: CGPoint, unit u: CGFloat, grow: CGFloat) -> Path {
        func push(_ p: CGPoint, awayFrom c: CGPoint, by amount: CGFloat) -> CGPoint {
            let v = unitVector(from: c, to: p)
            return CGPoint(x: p.x + v.x * amount, y: p.y + v.y * amount)
        }
        let top = CGPoint(x: (ls.x + rs.x) / 2, y: (ls.y + rs.y) / 2)
        let bottom = CGPoint(x: (lh.x + rh.x) / 2, y: (lh.y + rh.y) / 2)
        let lShoulder = push(ls, awayFrom: top, by: u * 0.08 + grow)
        let rShoulder = push(rs, awayFrom: top, by: u * 0.08 + grow)
        let lHip = push(lh, awayFrom: bottom, by: u * 0.12 + grow)
        let rHip = push(rh, awayFrom: bottom, by: u * 0.12 + grow)
        let waistMid = CGPoint(x: top.x + (bottom.x - top.x) * 0.62, y: top.y + (bottom.y - top.y) * 0.62)
        let across = unitVector(from: rShoulder, to: lShoulder)
        let halfWaist = min(length(lHip, rHip), length(lShoulder, rShoulder)) * 0.38 + grow
        let lWaist = CGPoint(x: waistMid.x + across.x * halfWaist, y: waistMid.y + across.y * halfWaist)
        let rWaist = CGPoint(x: waistMid.x - across.x * halfWaist, y: waistMid.y - across.y * halfWaist)
        let neckDip = CGPoint(x: top.x - (bottom.x - top.x) * 0.06, y: top.y - (bottom.y - top.y) * 0.06)
        let crotch = CGPoint(x: bottom.x + (bottom.x - top.x) * 0.12, y: bottom.y + (bottom.y - top.y) * 0.12 + grow)
        var path = Path()
        path.move(to: neckDip)
        path.addQuadCurve(to: lShoulder, control: CGPoint(x: lShoulder.x - (lShoulder.x - neckDip.x) * 0.3, y: neckDip.y))
        path.addQuadCurve(to: lWaist, control: CGPoint(x: lShoulder.x, y: (lShoulder.y + lWaist.y) / 2))
        path.addQuadCurve(to: lHip, control: CGPoint(x: lWaist.x, y: (lWaist.y + lHip.y) / 2))
        path.addQuadCurve(to: crotch, control: CGPoint(x: lHip.x, y: crotch.y))
        path.addQuadCurve(to: rHip, control: CGPoint(x: rHip.x, y: crotch.y))
        path.addQuadCurve(to: rWaist, control: CGPoint(x: rWaist.x, y: (rWaist.y + rHip.y) / 2))
        path.addQuadCurve(to: rShoulder, control: CGPoint(x: rShoulder.x, y: (rShoulder.y + rWaist.y) / 2))
        path.addQuadCurve(to: neckDip, control: CGPoint(x: rShoulder.x - (rShoulder.x - neckDip.x) * 0.3, y: neckDip.y))
        path.closeSubpath()
        return path
    }

    /// An egg-shaped head lined up with the neck.
    static func head(center: CGPoint, axis: CGPoint, unit u: CGFloat, grow: CGFloat) -> Path {
        let width = u * 0.33 + grow * 2, height = u * 0.43 + grow * 2
        let angle = atan2(axis.y, axis.x) + .pi / 2
        let transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle)
        return Path(ellipseIn: CGRect(x: -width / 2, y: -height / 2, width: width, height: height)).applying(transform)
    }
}
