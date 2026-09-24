import HealthKit

/// Optional Apple Health links, both off until switched on in Settings and only for the phone's
/// owner: sessions are saved as workouts (so they count towards the Activity rings), and steps can
/// come from Health, which includes an Apple Watch's steps. Nothing is sent anywhere else.
enum AppleHealth {
    private static let store = HKHealthStore()
    private static let defaults = UserDefaults.standard

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Workouts

    static var savesWorkouts: Bool {
        get { defaults.bool(forKey: "healthWorkouts") }
        set { defaults.set(newValue, forKey: "healthWorkouts") }
    }

    static func requestWorkoutAccess() async -> Bool {
        guard isAvailable else { return false }
        let types: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)]
        return (try? await store.requestAuthorization(toShare: types, read: [])) != nil
    }

    /// Saves a finished session as a workout with its estimated energy.
    static func saveWorkout(_ activity: HKWorkoutActivityType, start: Date, end: Date, kcal: Int) async {
        guard savesWorkouts, isAvailable, end > start,
              store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity
        configuration.locationType = activity == .running || activity == .walking ? .outdoor : .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: start)
            if kcal > 0, store.authorizationStatus(for: HKQuantityType(.activeEnergyBurned)) == .sharingAuthorized {
                let energy = HKQuantitySample(type: HKQuantityType(.activeEnergyBurned),
                                              quantity: HKQuantity(unit: .kilocalorie(), doubleValue: Double(kcal)),
                                              start: start, end: end)
                try await builder.addSamples([energy])
            }
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            // Health may be locked or full; the session still counts in Floor Age.
        }
    }

    // MARK: - Steps

    static var readsSteps: Bool {
        get { defaults.bool(forKey: "healthSteps") }
        set { defaults.set(newValue, forKey: "healthSteps") }
    }

    static func requestStepAccess() async -> Bool {
        guard isAvailable else { return false }
        return (try? await store.requestAuthorization(toShare: [], read: [HKQuantityType(.stepCount)])) != nil
    }

    /// Steps for each of the last `days` days (Health merges iPhone and Watch without counting twice).
    static func dailySteps(days: Int = 7) async -> [Date: Int] {
        guard isAvailable else { return [:] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: 1 - days, to: today) else { return [:] }
        let type = HKQuantityType(.stepCount)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: nil)),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )
        guard let collection = try? await descriptor.result(for: store) else { return [:] }
        var steps: [Date: Int] = [:]
        collection.enumerateStatistics(from: start, to: Date()) { statistics, _ in
            steps[calendar.startOfDay(for: statistics.startDate)] = Int(statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0)
        }
        return steps
    }
}
