import SwiftUI
import WidgetKit

/// The widgets' look. Also compiled into the app so its Debug demo screen can show them.
struct FloorAgeWidgetView: View {
    let snapshot: FloorAgeSnapshot
    /// Set only when drawing outside a widget (the app's Debug demo screen).
    var familyOverride: WidgetFamily?
    @Environment(\.widgetFamily) private var widgetFamily
    private var family: WidgetFamily { familyOverride ?? widgetFamily }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(snapshot.daysThisWeek), in: 0...7) {
                Image(systemName: "figure.cross.training")
            } currentValueLabel: {
                Text(snapshot.floorAge.map { "\($0)" } ?? "–")
            }
            .gaugeStyle(.accessoryCircular)
            .containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label(snapshot.floorAge.map { String(localized: "Floor Age \($0)") } ?? String(localized: "Find your Floor Age"),
                      systemImage: "figure.cross.training")
                    .font(.headline)
                    .widgetAccentable()
                Text("\(snapshot.daysThisWeek) of 7 days")
                Text("\(snapshot.stepsToday.formatted()) steps")
            }
            .containerBackground(.clear, for: .widget)
        case .accessoryInline:
            Label(snapshot.floorAge.map { String(localized: "Floor Age \($0) · \(snapshot.daysThisWeek)/7 days") } ?? String(localized: "Find your Floor Age"),
                  systemImage: "figure.cross.training")
                .containerBackground(.clear, for: .widget)
        case .systemMedium:
            HStack(spacing: Space.l) {
                summary
                Divider().overlay(.white.opacity(0.4))
                details
            }
            .foregroundStyle(.white)
            .containerBackground(for: .widget) { background }
        default:
            summary
                .foregroundStyle(.white)
                .containerBackground(for: .widget) { background }
        }
    }

    private var background: some View {
        ZStack(alignment: .topTrailing) {
            Feature.floorAge.gradient
            Image(systemName: "figure.cross.training")
                .font(.system(size: 90, weight: .bold))
                .foregroundStyle(.white.opacity(0.1))
                .rotationEffect(.degrees(-12))
                .offset(x: 18, y: 10)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Floor Age").font(.caption.weight(.heavy)).textCase(.uppercase).opacity(0.9)
            if let floorAge = snapshot.floorAge {
                Text("\(floorAge)")
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if let difference = snapshot.difference {
                    Text(difference < 0 ? String(localized: "\(-difference) yrs younger") : difference > 0 ? String(localized: "\(difference) yrs older") : String(localized: "Right on your age"))
                        .font(.caption.weight(.bold))
                        .opacity(0.95)
                }
            } else {
                Text("Take the check").font(.system(size: 20, weight: .bold, design: .serif)).padding(.vertical, Space.s)
            }
            Spacer(minLength: 4)
            WeekDots(week: snapshot.week)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            VStack(alignment: .leading, spacing: 3) {
                Label("\(snapshot.stepsToday.formatted()) steps", systemImage: "figure.walk").font(.caption.weight(.bold))
                ProgressBar(progress: snapshot.stepProgress)
            }
            if let day = snapshot.challengeDay {
                Label("Challenge day \(day) · \(snapshot.challengeDone ?? 0) trained", systemImage: "trophy.fill")
                    .font(.caption.weight(.semibold))
            }
            if snapshot.trainedToday {
                Label("Done today", systemImage: "checkmark.circle.fill").font(.caption.weight(.bold))
            } else {
                Label(snapshot.planToday ?? String(localized: "Today's session is waiting"), systemImage: "play.circle.fill")
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WeekDots: View {
    let week: [Bool]

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(Array(week.enumerated()), id: \.offset) { _, done in
                Circle()
                    .fill(done ? .white : .white.opacity(0.3))
                    .frame(width: 9, height: 9)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(week.filter { $0 }.count) of 7 days"))
    }
}

private struct ProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3))
                Capsule().fill(.white).frame(width: max(6, geo.size.width * progress))
            }
        }
        .frame(height: 6)
    }
}

struct StepsWidgetView: View {
    let snapshot: FloorAgeSnapshot
    var familyOverride: WidgetFamily?
    @Environment(\.widgetFamily) private var widgetFamily
    private var family: WidgetFamily { familyOverride ?? widgetFamily }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: snapshot.stepProgress) {
                Image(systemName: "figure.walk")
            } currentValueLabel: {
                Text(snapshot.stepsToday >= 1000 ? "\(snapshot.stepsToday / 1000)k" : "\(snapshot.stepsToday)")
            }
            .gaugeStyle(.accessoryCircular)
            .containerBackground(.clear, for: .widget)
        default:
            VStack(spacing: Space.s) {
                ZStack {
                    Circle().stroke(.white.opacity(0.3), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: snapshot.stepProgress)
                        .stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Image(systemName: "figure.walk").font(.caption.weight(.bold))
                        Text(snapshot.stepsToday.formatted())
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, Space.s)
                }
                Text("of \(snapshot.stepGoal.formatted())").font(.caption2.weight(.semibold)).opacity(0.9)
            }
            .foregroundStyle(.white)
            .containerBackground(Feature.steps.gradient, for: .widget)
        }
    }
}

