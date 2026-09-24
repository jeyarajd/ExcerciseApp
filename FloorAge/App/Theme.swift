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

extension View {
    /// Glassy card on top of `AppBackground`: translucent white (dark in dark mode), a hairline
    /// edge and a soft shadow.
    func card(padding: CGFloat = 16, cornerRadius: CGFloat = 20) -> some View {
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
    case steps, calories, bmi, sleep, plan, floorAge, glance

    var colors: [Color] {
        switch self {
        case .steps: [Color(red: 1.0, green: 0.62, blue: 0.24), Color(red: 1.0, green: 0.36, blue: 0.38)]
        case .calories: [Color(red: 0.2, green: 0.82, blue: 0.6), Color(red: 0.04, green: 0.6, blue: 0.62)]
        case .bmi: [Color(red: 0.58, green: 0.4, blue: 0.98), Color(red: 0.35, green: 0.24, blue: 0.84)]
        case .sleep: [Color(red: 0.27, green: 0.3, blue: 0.7), Color(red: 0.08, green: 0.1, blue: 0.3)]
        case .plan: [Color(red: 0.14, green: 0.74, blue: 0.9), Color(red: 0.24, green: 0.36, blue: 0.9)]
        case .floorAge: [Color(red: 0.98, green: 0.6, blue: 0.1), Color(red: 0.86, green: 0.28, blue: 0.2)]
        case .glance: [Color(red: 1.0, green: 0.55, blue: 0.25), Color(red: 0.93, green: 0.3, blue: 0.5), Color(red: 0.45, green: 0.3, blue: 0.85)]
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
        }
    }

    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }
    var tint: Color { colors[0] }
}

extension View {
    /// Rich gradient card with white text, a soft light bloom and a large faded symbol.
    func heroCard(_ feature: Feature, padding: CGFloat = 18, cornerRadius: CGFloat = 26) -> some View {
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
                        Image(systemName: feature.symbol)
                            .font(.system(size: 120, weight: .bold))
                            .foregroundStyle(.white.opacity(0.1))
                            .rotationEffect(.degrees(-12))
                            .offset(x: 28, y: 18)
                    }
                    .clipShape(shape)
            }
            .overlay(shape.strokeBorder(.white.opacity(0.28), lineWidth: 1))
            .shadow(color: feature.colors.last!.opacity(0.35), radius: 18, y: 10)
    }

    /// Light card with a gradient edge in the feature's colours, for supporting content.
    func tintedCard(_ feature: Feature, padding: CGFloat = 16, cornerRadius: CGFloat = 22) -> some View {
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
                label.padding(.bottom, 4)
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
    /// Big rounded numbers.
    static func metric(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
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
