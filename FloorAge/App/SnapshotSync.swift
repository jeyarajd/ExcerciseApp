import Combine
import WidgetKit

/// Keeps the widgets and the Apple Watch up to date: whenever the owner's data or steps change,
/// writes a fresh `FloorAgeSnapshot` (debounced) and asks the widgets to reload.
@MainActor
final class SnapshotPublisher: ObservableObject {
    private var subscription: AnyCancellable?
    private var last: FloorAgeSnapshot?

    func attach(model: AppModel, steps: StepCounter) {
        guard subscription == nil else { return }
        subscription = model.objectWillChange.map { _ in () }
            .merge(with: steps.objectWillChange.map { _ in () })
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self, weak model, weak steps] in
                guard let self, let model, let steps else { return }
                self.publish(model, steps)
            }
        publish(model, steps)
    }

    private func publish(_ model: AppModel, _ steps: StepCounter) {
        // The widgets and Watch show the phone's owner, not a family member being coached.
        guard model.isOwner, model.profile != nil else { return }
        var snapshot = model.snapshot(steps: steps)
        snapshot.updated = last?.updated ?? snapshot.updated
        guard snapshot != last else { return }
        snapshot.updated = Date()
        last = snapshot
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
        WatchLink.shared.send(snapshot)
    }
}

extension AppModel {
    func snapshot(steps: StepCounter) -> FloorAgeSnapshot {
        var snapshot = FloorAgeSnapshot()
        snapshot.name = profile?.name ?? ""
        snapshot.floorAge = latestResult?.floorAge
        snapshot.age = profile?.age
        snapshot.week = lastSevenDays
        snapshot.stepsToday = steps.today
        snapshot.stepGoal = steps.goal
        if let challenge, !challenge.isOver() {
            snapshot.challengeDay = challenge.dayNumber()
            snapshot.challengeDone = challenge.completed
        }
        if let position = planPosition(), let week = planWeek(position.week) {
            snapshot.planToday = TrainingPlan.headline(week.days[position.day])
        }
        snapshot.trainedToday = didSessionToday || isPlanDayDone(Date())
        return snapshot
    }
}
