import SwiftUI
import UIKit

/// The warm background behind every screen: a soft mesh of peach, cream and a hint of the mat's
/// teal that drifts very slowly. Still when Reduce Motion is on; a deep evening palette in dark mode.
struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                mesh(at: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                    mesh(at: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func mesh(at time: TimeInterval) -> some View {
        let t = Float(time)
        func drift(_ speed: Float, _ phase: Float) -> Float { 0.06 * sin(t * speed + phase) }
        let points: [SIMD2<Float>] = [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5], [0.5 + drift(0.23, 0), 0.45 + drift(0.19, 1.3)], [1, 0.5],
            [0, 1], [0.5, 1], [1, 1],
        ]
        return MeshGradient(width: 3, height: 3, points: points, colors: scheme == .dark ? Self.night : Self.day)
    }

    private static let day: [Color] = [
        Color(red: 1.0, green: 0.9, blue: 0.82), Color(red: 1.0, green: 0.86, blue: 0.74), Color(red: 1.0, green: 0.94, blue: 0.88),
        Color(red: 1.0, green: 0.95, blue: 0.91), Color(red: 1.0, green: 0.98, blue: 0.95), Color(red: 0.9, green: 0.97, blue: 0.95),
        Color(red: 1.0, green: 0.97, blue: 0.93), Color(red: 0.88, green: 0.95, blue: 0.93), Color(red: 1.0, green: 0.93, blue: 0.88),
    ]

    private static let night: [Color] = [
        Color(red: 0.17, green: 0.12, blue: 0.18), Color(red: 0.23, green: 0.13, blue: 0.16), Color(red: 0.12, green: 0.13, blue: 0.2),
        Color(red: 0.13, green: 0.11, blue: 0.16), Color(red: 0.1, green: 0.1, blue: 0.13), Color(red: 0.07, green: 0.15, blue: 0.16),
        Color(red: 0.1, green: 0.1, blue: 0.14), Color(red: 0.06, green: 0.15, blue: 0.16), Color(red: 0.14, green: 0.11, blue: 0.13),
    ]
}

// MARK: - Spacing and radii

/// The spacing scale for padding and stack spacing. Anything tighter (1–3 pt between lines of
/// text) or larger (fixed layouts like the share card) stays a plain number.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// Corner radii: small controls and tiles, cards, and hero cards.
enum Radius {
    static let small: CGFloat = 12
    static let medium: CGFloat = 20
    static let large: CGFloat = 28
}

extension View {
    /// Glassy card on top of `AppBackground`: translucent white (dark in dark mode), a hairline
    /// edge and a soft shadow.
    func card(padding: CGFloat = Space.l, cornerRadius: CGFloat = Radius.medium) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .padding(padding)
            .background(Color(.systemBackground).opacity(0.72), in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.6), lineWidth: 0.5))
            .shadow(color: Color(red: 0.55, green: 0.3, blue: 0.15).opacity(0.1), radius: 14, y: 6)
    }

    /// Puts `AppBackground` behind a List or Form (which otherwise paint their own grey).
    func appBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AppBackground())
    }
}

// MARK: - Feature identity

/// Each area of the app has its own colours and symbol, so screens feel distinct rather than
/// uniform white cards.
enum Feature {
    case steps, calories, bmi, sleep, plan, floorAge, glance, plus, challenge

    var colors: [Color] {
        switch self {
        case .steps: [Color(red: 1.0, green: 0.62, blue: 0.24), Color(red: 1.0, green: 0.36, blue: 0.38)]
        case .calories: [Color(red: 0.2, green: 0.82, blue: 0.6), Color(red: 0.04, green: 0.6, blue: 0.62)]
        case .bmi: [Color(red: 0.58, green: 0.4, blue: 0.98), Color(red: 0.35, green: 0.24, blue: 0.84)]
        case .sleep: [Color(red: 0.27, green: 0.3, blue: 0.7), Color(red: 0.08, green: 0.1, blue: 0.3)]
        case .plan: [Color(red: 0.14, green: 0.74, blue: 0.9), Color(red: 0.24, green: 0.36, blue: 0.9)]
        case .floorAge: [Color(red: 0.98, green: 0.6, blue: 0.1), Color(red: 0.86, green: 0.28, blue: 0.2)]
        case .glance: [Color(red: 1.0, green: 0.55, blue: 0.25), Color(red: 0.93, green: 0.3, blue: 0.5), Color(red: 0.45, green: 0.3, blue: 0.85)]
        case .plus: [Color(red: 0.42, green: 0.26, blue: 0.66), Color(red: 0.13, green: 0.08, blue: 0.28)]
        case .challenge: [Color(red: 1.0, green: 0.76, blue: 0.2), Color(red: 0.93, green: 0.42, blue: 0.12)]
        }
    }

    var symbol: String {
        switch self {
        case .steps: "figure.walk"
        case .calories: "fork.knife"
        case .bmi: "scalemass.fill"
        case .sleep: "moon.stars.fill"
        case .plan: "calendar.badge.checkmark"
        case .floorAge: "figure.cross.training"
        case .glance: "sun.max.fill"
        case .plus: "crown.fill"
        case .challenge: "trophy.fill"
        }
    }

    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }
    var tint: Color { colors[0] }

    /// The feature's colours for text and small icons on cards and screens (not on its own
    /// gradient): darkened in light mode and lightened in dark mode just enough to read at 4.5:1.
    /// Without this the oranges and greens wash out on cream, and the sleep and Plus purples
    /// vanish on the night background.
    var inkColors: [Color] { colors.map(\.readableInk) }
    var ink: LinearGradient { LinearGradient(colors: inkColors, startPoint: .topLeading, endPoint: .bottomTrailing) }

    /// The warm gold used with Plus (crown, price) against its deep purple.
    static let gold = Color(red: 1.0, green: 0.8, blue: 0.38)
}

extension View {
    /// Rich gradient card with white text, a soft light bloom, a large faded symbol, a fine grain
    /// and light catching the top edge.
    func heroCard(_ feature: Feature, symbol: String? = nil, padding: CGFloat = Space.l, cornerRadius: CGFloat = Radius.large) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .padding(padding)
            .foregroundStyle(.white)
            .tint(.white)
            .background {
                // The decorations are overlays so they can never make the card bigger than its content.
                feature.gradient
                    .overlay(alignment: .topTrailing) {
                        Circle().fill(.white.opacity(0.22)).frame(width: 180, height: 180).blur(radius: 40).offset(x: 50, y: -80)
                    }
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: symbol ?? feature.symbol)
                            .font(.system(size: 120, weight: .bold))
                            .foregroundStyle(.white.opacity(0.1))
                            .rotationEffect(.degrees(-12))
                            .offset(x: 28, y: 18)
                    }
                    // Film grain, so the gradient looks printed rather than flat.
                    .overlay {
                        Image(uiImage: Grain.tile).resizable(resizingMode: .tile).opacity(0.025).blendMode(.overlay)
                    }
                    // Light from above along the top of the card.
                    .overlay(alignment: .top) {
                        LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 28)
                    }
                    .clipShape(shape)
            }
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.18), .white.opacity(0.1)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: feature.colors.last!.opacity(0.35), radius: 18, y: 10)
    }

    /// Light card with a gradient edge in the feature's colours, for supporting content.
    func tintedCard(_ feature: Feature, padding: CGFloat = Space.l, cornerRadius: CGFloat = Radius.medium) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .padding(padding)
            .background(Color(.systemBackground).opacity(0.8), in: shape)
            .background(feature.tint.opacity(0.06), in: shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: feature.colors.map { $0.opacity(0.55) }, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2))
            .shadow(color: feature.tint.opacity(0.14), radius: 14, y: 6)
    }
}

/// A rounded-square badge filled with the feature's gradient.
struct FeatureBadge: View {
    let feature: Feature
    var symbol: String? = nil
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: symbol ?? feature.symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(feature.gradient, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .shadow(color: feature.colors.last!.opacity(0.35), radius: 6, y: 3)
    }
}

/// The main action on a screen: a full-width gradient capsule in the feature's colours.
struct GradientButtonStyle: ButtonStyle {
    var feature: Feature = .floorAge
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.vertical, 16)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity)
            .background(feature.gradient, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1))
            .shadow(color: feature.colors.last!.opacity(isEnabled ? 0.4 : 0), radius: 12, y: 6)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// A white capsule for actions that sit on a hero card.
struct OnHeroButtonStyle: ButtonStyle {
    var feature: Feature

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(feature.colors.last!)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(.white, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// Small spaced capitals above a heading.
struct Eyebrow: View {
    let text: Text
    var feature: Feature = .floorAge

    init(_ key: LocalizedStringKey, feature: Feature = .floorAge) {
        text = Text(key)
        self.feature = feature
    }

    var body: some View {
        text
            .font(.caption.weight(.heavy))
            .tracking(1.8)
            .textCase(.uppercase)
            .foregroundStyle(feature.ink)
    }
}

/// A semicircle meter with a gradient stroke and a soft glow: the app's own look instead of rings.
struct ArcGauge<Label: View>: View {
    var progress: Double
    var colors: [Color] = [.white, .white.opacity(0.85)]
    var track: Color = .white.opacity(0.25)
    var lineWidth: CGFloat = 14
    @ViewBuilder var label: Label

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height * 2)
            ZStack(alignment: .bottom) {
                Group {
                    Circle().trim(from: 0.5, to: 1).stroke(track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    Circle().trim(from: 0.5, to: 0.5 + 0.5 * min(max(progress, 0), 1))
                        .stroke(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing),
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .shadow(color: (colors.last ?? .white).opacity(0.6), radius: 8)
                        .animation(.easeOut(duration: 0.8), value: progress)
                }
                .frame(width: d - lineWidth, height: d - lineWidth)
                .offset(y: (d - lineWidth) / 2)
                // The label shrinks to fit inside the arc at large text sizes rather than
                // being cut off at the top.
                label
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .padding(.bottom, 4)
                    .frame(maxWidth: max(d - lineWidth * 3, 0), maxHeight: max(geo.size.height - lineWidth, 0), alignment: .bottom)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
            .clipped()
        }
        .aspectRatio(2, contentMode: .fit)
    }
}

extension Font {
    /// Serif display type for headings: warmer and more editorial than the system default.
    static func display(_ style: Font.TextStyle = .title2) -> Font { .system(style, design: .serif, weight: .bold) }
    /// Big rounded numbers. They grow with Dynamic Type like the text around them, but only to
    /// 1.5×, so a figure still fits its card at the largest accessibility sizes.
    static func metric(_ size: CGFloat) -> Font {
        let scaled = min(UIFontMetrics(forTextStyle: .body).scaledValue(for: size), size * 1.5)
        return .system(size: scaled, weight: .bold, design: .rounded)
    }
}

enum Appearance {
    /// Serif navigation titles throughout the app.
    static func apply() {
        func serif(_ style: UIFont.TextStyle, bold: Bool) -> UIFont {
            let base = UIFont.preferredFont(forTextStyle: style).fontDescriptor
            let serif = base.withDesign(.serif) ?? base
            return UIFont(descriptor: bold ? (serif.withSymbolicTraits(.traitBold) ?? serif) : serif, size: 0)
        }
        let appearance = UINavigationBar.appearance()
        appearance.largeTitleTextAttributes = [.font: serif(.largeTitle, bold: true)]
        appearance.titleTextAttributes = [.font: serif(.headline, bold: true)]
    }
}

// MARK: - Readable colours and grain

extension Color {
    /// This colour as text on the app's cards: mixed towards black (light mode) or white (dark
    /// mode) in small steps until it reaches 4.5:1 against the card, and left alone if it already does.
    var readableInk: Color {
        let base = UIColor(self)
        return Color(UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            // The cards: nearly white over the peach mesh, nearly black over the night mesh.
            let card: (CGFloat, CGFloat, CGFloat) = dark ? (0.02, 0.02, 0.026) : (1.0, 0.99, 0.98)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            base.getRed(&r, green: &g, blue: &b, alpha: &a)
            let target: CGFloat = dark ? 1 : 0
            var t: CGFloat = 0
            func mixed(_ c: CGFloat) -> CGFloat { c + (target - c) * t }
            while t < 1, Self.contrast((mixed(r), mixed(g), mixed(b)), card) < 4.5 { t += 0.02 }
            return UIColor(red: mixed(r), green: mixed(g), blue: mixed(b), alpha: a)
        })
    }

    /// WCAG contrast ratio of two sRGB colours.
    static func contrast(_ a: (CGFloat, CGFloat, CGFloat), _ b: (CGFloat, CGFloat, CGFloat)) -> CGFloat {
        func channel(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        func luminance(_ c: (CGFloat, CGFloat, CGFloat)) -> CGFloat { 0.2126 * channel(c.0) + 0.7152 * channel(c.1) + 0.0722 * channel(c.2) }
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}

/// A small tile of random grey noise for the hero cards' grain, made once.
enum Grain {
    static let tile: UIImage = {
        let size = 96
        var generator = SystemRandomNumberGenerator()
        let pixels = (0..<size * size).map { _ in UInt8.random(in: 0...255, using: &generator) }
        let image = pixels.withUnsafeBytes { bytes -> CGImage? in
            guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
            return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: size,
                           space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                           provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
        return image.map { UIImage(cgImage: $0) } ?? UIImage()
    }()
}
