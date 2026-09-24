import CoreMotion
import Foundation

/// Today's steps and the last 7 days, read from the iPhone's motion coprocessor (CoreMotion). The
/// phone keeps this history itself, so nothing is stored or sent anywhere; iOS asks for Motion &
/// Fitness permission the first time.
final class StepCounter: ObservableObject {
    struct Day: Identifiable, Equatable {
        let date: Date
        let steps: Int
        var id: Date { date }
    }

    enum Status: Equatable {
        case unknown, available, unavailable, denied
    }

    @Published private(set) var today = 0
    @Published private(set) var week: [Day] = []
    @Published private(set) var status: Status = .unknown
    @Published var goal: Int {
        didSet { UserDefaults.standard.set(goal, forKey: "stepGoal") }
    }

    private let pedometer = CMPedometer()
    private var liveSince: Date?
    private let isSample: Bool

    init() {
        goal = UserDefaults.standard.object(forKey: "stepGoal") as? Int ?? Steps.defaultGoal
        isSample = false
    }

    /// Made-up steps for screenshots and previews.
    private init(sampleToday: Int, week: [Int]) {
        goal = Steps.defaultGoal
        isSample = true
        today = sampleToday
        status = .available
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        self.week = week.enumerated().map { i, steps in
            Day(date: cal.date(byAdding: .day, value: i - (week.count - 1), to: start)!, steps: steps)
        }
    }

    static func sample() -> StepCounter {
        StepCounter(sampleToday: 6240, week: [7120, 4380, 9810, 8350, 3920, 10240, 6240])
    }

    var progress: Double { goal > 0 ? min(Double(today) / Double(goal), 1) : 0 }

    /// Starts live counting for today and loads the week. Safe to call again (e.g. on foreground).
    func start() {
        guard !isSample else { return }
        if AppleHealth.readsSteps {
            loadFromHealth()
            return
        }
        guard CMPedometer.isStepCountingAvailable() else {
            status = .unavailable
            return
        }
        switch CMPedometer.authorizationStatus() {
        case .denied, .restricted:
            status = .denied
            return
        default:
            break
        }
        loadWeek()
        let startOfDay = Calendar.current.startOfDay(for: Date())
        guard liveSince != startOfDay else { return }
        // Restart after midnight so "today" starts from zero.
        pedometer.stopUpdates()
        liveSince = startOfDay
        pedometer.startUpdates(from: startOfDay) { [weak self] data, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let steps = data?.numberOfSteps.intValue {
                    self.today = steps
                    self.status = .available
                    if let last = self.week.indices.last { self.week[last] = Day(date: startOfDay, steps: steps) }
                } else if error != nil {
                    self.status = CMPedometer.authorizationStatus() == .denied ? .denied : self.status
                }
            }
        }
    }

    /// Steps from Apple Health instead of the motion chip, which adds an Apple Watch's steps.
    private func loadFromHealth() {
        pedometer.stopUpdates()
        liveSince = nil
        Task { @MainActor in
            let steps = await AppleHealth.dailySteps()
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            self.week = (0..<7).map { offset in
                let day = cal.date(byAdding: .day, value: offset - 6, to: today)!
                return Day(date: day, steps: steps[day] ?? 0)
            }
            self.today = steps[today] ?? 0
            self.status = .available
        }
    }

    private func loadWeek() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days = (0..<7).map { cal.date(byAdding: .day, value: $0 - 6, to: today)! }
        var results = [Date: Int]()
        let group = DispatchGroup()
        let lock = NSLock()
        for day in days {
            group.enter()
            let end = min(cal.date(byAdding: .day, value: 1, to: day)!, Date())
            pedometer.queryPedometerData(from: day, to: end) { data, _ in
                lock.lock()
                results[day] = data?.numberOfSteps.intValue ?? 0
                lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.week = days.map { Day(date: $0, steps: results[$0] ?? 0) }
            if let todays = results[today] { self.today = max(self.today, todays) }
            if CMPedometer.authorizationStatus() == .denied { self.status = .denied } else if self.status == .unknown { self.status = .available }
        }
    }
}
