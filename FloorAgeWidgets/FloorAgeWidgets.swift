import CoreMotion
import SwiftUI
import WidgetKit

/// Home Screen and Lock Screen widgets. They show the summary the app shares through the App
/// Group, rolled forward to today, with today's steps read fresh from the motion chip when allowed.
@main
struct FloorAgeWidgetBundle: WidgetBundle {
    var body: some Widget {
        FloorAgeWidget()
        StepsWidget()
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: FloorAgeSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            current { completion($0) }
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        current { entry in
            // Fresh steps every half hour; the app also reloads the widgets when anything changes.
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
        }
    }

    private func current(_ completion: @escaping (SnapshotEntry) -> Void) {
        let now = Date()
        var snapshot = (FloorAgeSnapshot.load() ?? FloorAgeSnapshot()).rolledForward(to: now)
        guard CMPedometer.isStepCountingAvailable(), CMPedometer.authorizationStatus() == .authorized else {
            completion(SnapshotEntry(date: now, snapshot: snapshot))
            return
        }
        CMPedometer().queryPedometerData(from: Calendar.current.startOfDay(for: now), to: now) { data, _ in
            if let steps = data?.numberOfSteps.intValue {
                // The app may count an Apple Watch's steps through Health, so keep the larger number.
                snapshot.stepsToday = max(snapshot.stepsToday, steps)
            }
            completion(SnapshotEntry(date: now, snapshot: snapshot))
        }
    }
}

// MARK: - Floor Age widget

struct FloorAgeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FloorAge", provider: SnapshotProvider()) { entry in
            FloorAgeWidgetView(snapshot: entry.snapshot)
                .widgetURL(URL(string: "floorage://today"))
        }
        .configurationDisplayName("Floor Age")
        .description("Your Floor Age, this week's training and today's steps.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Steps widget

struct StepsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Steps", provider: SnapshotProvider()) { entry in
            StepsWidgetView(snapshot: entry.snapshot)
                .widgetURL(URL(string: "floorage://steps"))
        }
        .configurationDisplayName("Steps")
        .description("Today's steps against your goal.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

#Preview(as: .systemMedium) {
    FloorAgeWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .sample)
}
