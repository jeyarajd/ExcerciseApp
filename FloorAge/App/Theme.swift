import SwiftUI

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
