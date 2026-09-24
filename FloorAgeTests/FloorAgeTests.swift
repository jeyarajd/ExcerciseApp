import XCTest
import simd
@testable import FloorAge

final class FloorAgeScoringTests: XCTestCase {
    func testEquivalentAgeClampsToTheNormRange() {
        XCTAssertEqual(FloorTest.sitRise.equivalentAge(for: 10), 20)
        XCTAssertEqual(FloorTest.sitRise.equivalentAge(for: 0), 90)
        XCTAssertEqual(FloorTest.balance.equivalentAge(for: 60), 25)
        XCTAssertEqual(FloorTest.reach.equivalentAge(for: 0), 85)
    }

    func testEquivalentAgeInterpolatesBetweenNorms() {
        // Sit to rise: 8 at 50, 7 at 60.
        XCTAssertEqual(FloorTest.sitRise.equivalentAge(for: 7.5), 55, accuracy: 0.001)
        XCTAssertEqual(FloorTest.chairStand.equivalentAge(for: 15), 62, accuracy: 0.001)
    }

    func testBetterScoresNeverMeanOlderAges() {
        for test in FloorTest.allCases {
            let best = test.norms.first!.score
            var previous = -Double.infinity
            for step in stride(from: 0.0, through: best, by: best / 50) {
                let age = test.equivalentAge(for: best - step)
                XCTAssertGreaterThanOrEqual(age, previous - 0.0001, "\(test) at \(best - step)")
                previous = age
            }
        }
    }

    func testSitRiseScore() {
        XCTAssertEqual(FloorAgeCalculator.sitRiseScore(downSupports: 0, upSupports: 0, unsteady: false), 10)
        XCTAssertEqual(FloorAgeCalculator.sitRiseScore(downSupports: 1, upSupports: 2, unsteady: true), 6.5)
        XCTAssertEqual(FloorAgeCalculator.sitRiseScore(downSupports: 5, upSupports: 5, unsteady: true), 0)
    }

    func testFloorAgeIsTheWeightedAverageOfTakenTests() {
        XCTAssertEqual(FloorAgeCalculator.floorAge(scores: [:]), 0)
        // One test: its own equivalent age, whatever the weight.
        XCTAssertEqual(FloorAgeCalculator.floorAge(scores: ["reach": 3]), 45, accuracy: 0.001)
        let scores = ["sitRise": 10.0, "balance": 45, "chairStand": 24, "reach": 5]
        let expected = (20 * 0.35 + 25 * 0.25 + 25 * 0.25 + 20 * 0.15) / 1.0
        XCTAssertEqual(FloorAgeCalculator.floorAge(scores: scores), expected, accuracy: 0.001)
    }

    func testWeakestAreaRanking() {
        let result = FloorAgeResult(age: 50, scores: ["sitRise": 10, "balance": 15, "reach": 3])
        XCTAssertEqual(result.weakest, .balance)
        XCTAssertEqual(result.rankedWeakest, [.balance, .reach, .sitRise])
        XCTAssertNil(result.equivalentAge(.chairStand))
    }
}

final class PlanBuilderTests: XCTestCase {
    private func allLimitationSets() -> [Set<Limitation>] {
        let all = Limitation.allCases
        return (0..<(1 << all.count)).map { mask in
            Set(all.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element))
        }
    }

    func testTodayNeverIncludesUnsafeMoves() {
        let results: [FloorAgeResult?] = [
            nil,
            FloorAgeResult(age: 40, scores: ["sitRise": 2, "balance": 40, "chairStand": 20, "reach": 1]),
            FloorAgeResult(age: 40, scores: ["reach": 0]),
        ]
        for limitations in allLimitationSets() {
            let unsafe = PlanBuilder.unsafe(for: limitations)
            for result in results {
                for day in 0..<7 {
                    let date = Date(timeIntervalSince1970: Double(day) * 86_400 + 1_700_000_000)
                    let plan = PlanBuilder.today(profile: Profile(name: "", age: 45, limitations: limitations), latest: result, date: date)
                    XCTAssertGreaterThanOrEqual(plan.count, 4)
                    XCTAssertEqual(plan.first?.exercise.id, "march")
                    for item in plan {
                        XCTAssertFalse(unsafe.contains(item.exercise.id), "\(item.exercise.id) with \(limitations)")
                    }
                    XCTAssertEqual(Set(plan.map(\.exercise.id)).count, plan.count, "no repeats")
                }
            }
        }
    }

    func testPelvicFloorFinishesThePlanUnlessSwitchedOff() {
        let profile = Profile(name: "", age: 45, limitations: [])
        XCTAssertEqual(PlanBuilder.today(profile: profile, latest: nil).last?.exercise.id, "kegel")
        XCTAssertFalse(PlanBuilder.today(profile: profile, latest: nil, pelvicFloor: false).contains { $0.exercise.id == "kegel" })
        XCTAssertEqual(PlanBuilder.pelvicFloor.first?.reps, 12)
    }

    func testOldSavedProfilesWithoutGenderStillLoad() throws {
        let json = #"{"name":"Ravi","age":61,"limitations":["knee"]}"#
        let profile = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
        XCTAssertNil(profile.gender)
        XCTAssertEqual(profile.limitations, [.knee])
    }

    func testGentleProfilesGetFewerReps() {
        let result = FloorAgeResult(age: 40, scores: ["chairStand": 5])
        let normal = PlanBuilder.today(profile: Profile(name: "", age: 40, limitations: []), latest: result)
        let gentle = PlanBuilder.today(profile: Profile(name: "", age: 75, limitations: []), latest: result)
        let normalReps = normal.compactMap(\.reps).reduce(0, +)
        let gentleReps = gentle.compactMap(\.reps).reduce(0, +)
        XCTAssertLessThan(gentleReps, normalReps)
        XCTAssertEqual(gentle.first?.seconds, 30)
    }
}

final class AppModelTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("floorage-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    func testEverythingPersistsAcrossLaunches() {
        let model = AppModel(fileURL: url)
        model.profile = Profile(name: "Asha", age: 52, limitations: [.back])
        model.add(FloorAgeResult(age: 52, scores: ["balance": 30]))
        model.completeSession()

        let reloaded = AppModel(fileURL: url)
        XCTAssertEqual(reloaded.profile, model.profile)
        XCTAssertEqual(reloaded.results.count, 1)
        XCTAssertEqual(reloaded.latestResult?.scores, ["balance": 30])
        XCTAssertTrue(reloaded.didSessionToday)
    }

    func testSessionsCountOncePerDayAndMissedDaysDontReset() {
        let model = AppModel(fileURL: url)
        let cal = Calendar.current
        let today = Date()
        model.completeSession(on: today)
        model.completeSession(on: today)
        model.completeSession(on: cal.date(byAdding: .day, value: -3, to: today)!)
        model.completeSession(on: cal.date(byAdding: .day, value: -10, to: today)!)
        XCTAssertEqual(model.sessionDays.count, 3)
        XCTAssertEqual(model.lastSevenDays, [false, false, false, true, false, false, true])
    }

    func testResetDeletesEverything() {
        let model = AppModel(fileURL: url)
        model.profile = Profile(name: "", age: 30, limitations: [])
        model.completeSession()
        model.resetAll()
        let reloaded = AppModel(fileURL: url)
        XCTAssertNil(reloaded.profile)
        XCTAssertTrue(reloaded.sessionDays.isEmpty)
    }
}

final class ExerciseLibraryTests: XCTestCase {
    let library = ExerciseLibrary.shared

    func testEveryKeyframeUsesKnownPosesAndJoints() {
        let joints = Set(library.rig.joints.map(\.name))
        for pose in library.poses.values {
            XCTAssertTrue(Set(pose.keys).isSubset(of: joints))
        }
        for exercise in library.exercises {
            XCTAssertFalse(exercise.keyframes.isEmpty, exercise.id)
            XCTAssertEqual(exercise.keyframes.map(\.t), exercise.keyframes.map(\.t).sorted(), "\(exercise.id) times ascend")
            for kf in exercise.keyframes {
                if let pose = kf.pose { XCTAssertNotNil(library.poses[pose], "\(exercise.id) pose \(pose)") }
                XCTAssertTrue(Set((kf.joints ?? [:]).keys).isSubset(of: joints), exercise.id)
            }
        }
    }

    func testExerciseAmountsMatchTheirKind() {
        for exercise in library.exercises {
            switch exercise.kind {
            case .reps:
                XCTAssertNotNil(exercise.defaultReps, exercise.id)
                let repTime = try? XCTUnwrap(exercise.repTime, "\(exercise.id) needs repTime to count reps")
                if let repTime { XCTAssertLessThanOrEqual(repTime, exercise.keyframes.last!.t, exercise.id) }
            case .timed, .hold:
                XCTAssertNotNil(exercise.defaultSeconds, exercise.id)
            }
            if exercise.id != "idle" {
                XCTAssertFalse(exercise.intro.isEmpty, exercise.id)
                XCTAssertFalse(exercise.cues.isEmpty, exercise.id)
            }
        }
    }

    func testEveryDemoVideoIsNamedAfterAnExercise() {
        // Clips must be named demo_<exercise id>.mp4 or the app never finds them.
        let ids = Set(library.exercises.map(\.id))
        let clips = Bundle.main.urls(forResourcesWithExtension: "mp4", subdirectory: nil) ?? []
        for clip in clips {
            let name = clip.deletingPathExtension().lastPathComponent
            XCTAssertTrue(name.hasPrefix("demo_"), "\(name).mp4 should be named demo_<exercise id>.mp4")
            XCTAssertTrue(ids.contains(String(name.dropFirst("demo_".count))), "\(name).mp4 matches no exercise id")
        }
    }

    func testPlanAndTestExercisesExist() {
        let ids = Set(library.exercises.map(\.id))
        for test in FloorTest.allCases { XCTAssertTrue(ids.contains(test.exerciseID)) }
        for options in PlanBuilder.trainers.values { XCTAssertTrue(Set(options).isSubset(of: ids)) }
        XCTAssertTrue(PlanBuilder.unsafe(for: Set(Limitation.allCases)).isSubset(of: ids))
    }
}

final class PoseSolverTests: XCTestCase {
    let library = ExerciseLibrary.shared

    private func lowestContact(_ clip: ExerciseClip, at t: Double) -> Float {
        let pose = clip.sample(at: t)
        return clip.solver.contactPoints(pose.angles, pelvis: pose.pelvis).values.map(\.y).min()!
    }

    func testCoachNeverSinksThroughTheFloor() {
        for exercise in library.exercises {
            for mirrored in [false, true] {
                let clip = ExerciseClip(exercise: exercise, mirrored: mirrored)
                for t in stride(from: 0, through: clip.duration, by: 0.05) {
                    XCTAssertGreaterThanOrEqual(lowestContact(clip, at: t), -0.001, "\(exercise.id) t=\(t)")
                }
            }
        }
    }

    func testKeyframesTouchTheFloor() {
        for exercise in library.exercises {
            let clip = ExerciseClip(exercise: exercise)
            for frame in clip.frames.dropLast() {
                XCTAssertEqual(lowestContact(clip, at: frame.t), 0, accuracy: 0.001, "\(exercise.id) t=\(frame.t)")
            }
        }
    }

    func testHeldPosesStayStillAndMotionNeverOvershoots() {
        // Kegel holds the squeeze from 1.0 s to 3.6 s: the spine must not drift during the hold.
        let clip = ExerciseClip(exercise: library["kegel"])
        for t in stride(from: 1.0, through: 3.6, by: 0.1) {
            XCTAssertEqual(clip.sample(at: t).angles["spine"]?.x ?? 0, 1, accuracy: 0.001, "t=\(t)")
        }
        // Between any two keyframes, every angle stays within the range of those two keyframes.
        for exercise in library.exercises {
            let clip = ExerciseClip(exercise: exercise)
            for (a, b) in zip(clip.frames, clip.frames.dropFirst()) where b.t > a.t {
                for t in stride(from: a.t, through: b.t, by: (b.t - a.t) / 10) {
                    for (name, angle) in clip.sample(at: t).angles {
                        let lo = simd_min(a.angles[name] ?? .zero, b.angles[name] ?? .zero)
                        let hi = simd_max(a.angles[name] ?? .zero, b.angles[name] ?? .zero)
                        XCTAssertTrue(all(angle .>= lo - 0.01) && all(angle .<= hi + 0.01), "\(exercise.id) \(name) t=\(t)")
                    }
                }
            }
        }
    }

    func testMirroringSwapsSides() {
        XCTAssertEqual(ExerciseClip.mirroredName("lKnee"), "rKnee")
        XCTAssertEqual(ExerciseClip.mirroredName("rShoulder"), "lShoulder")
        XCTAssertEqual(ExerciseClip.mirroredName("spine"), "spine")
        XCTAssertEqual(ExerciseClip.mirroredName("l"), "l")

        let balance = library["single_leg_balance"]
        let left = ExerciseClip(exercise: balance).sample(at: 2)
        let right = ExerciseClip(exercise: balance, mirrored: true).sample(at: 2)
        XCTAssertEqual(left.pelvis.x, -right.pelvis.x, accuracy: 0.001)
        XCTAssertEqual(left.angles["lKnee"]?.x ?? 0, right.angles["rKnee"]?.x ?? 0, accuracy: 0.001)
    }

    func testEulerOrderMatchesThePreviewScript() {
        // q = qx * qz * qy: a limb pointing down with negative X swings forward (+Z).
        let down = SIMD3<Float>(0, -1, 0)
        let forward = PoseSolver.localRotation([-90, 0, 0]).act(down)
        XCTAssertEqual(forward.z, 1, accuracy: 0.0001)
        let q = PoseSolver.localRotation([30, 40, 50])
        let expected = simd_quatf(angle: 30 * .pi / 180, axis: [1, 0, 0])
            * simd_quatf(angle: 50 * .pi / 180, axis: [0, 0, 1])
            * simd_quatf(angle: 40 * .pi / 180, axis: [0, 1, 0])
        XCTAssertEqual(simd_distance(q.vector, expected.vector), 0, accuracy: 0.0001)
    }
}

final class RemindersTests: XCTestCase {
    private let cal = Calendar.current

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
    }

    func testSchedulesAMonthAheadAtTheChosenTime() {
        let dates = Reminders.fireDates(minuteOfDay: 7 * 60 + 30, trainedToday: false, now: at(6))
        XCTAssertEqual(dates.count, 30)
        XCTAssertEqual(Set(dates.map { cal.startOfDay(for: $0) }).count, 30, "one per day")
        XCTAssertEqual(dates.first, at(7, 30), "today is still ahead")
        for date in dates {
            XCTAssertEqual(cal.component(.hour, from: date), 7)
            XCTAssertEqual(cal.component(.minute, from: date), 30)
        }
    }

    func testSkipsTodayWhenTrainedOrPast() {
        let tomorrow = cal.date(byAdding: .day, value: 1, to: at(7))!
        XCTAssertEqual(Reminders.fireDates(minuteOfDay: 7 * 60, trainedToday: true, now: at(6)).first, tomorrow)
        XCTAssertEqual(Reminders.fireDates(minuteOfDay: 7 * 60, trainedToday: false, now: at(9)).first, tomorrow)
        XCTAssertEqual(Reminders.fireDates(minuteOfDay: 7 * 60, trainedToday: false, now: at(9)).count, 30)
    }
}

final class HealthTests: XCTestCase {
    func testBMIUsesAsianIndianCutoffs() throws {
        XCTAssertEqual(try XCTUnwrap(BMI.value(weightKg: 70, heightCm: 170)), 24.22, accuracy: 0.01)
        XCTAssertEqual(BMI.category(17.3, scale: .asian), .underweight)
        XCTAssertEqual(BMI.category(20.8, scale: .asian), .healthy)
        XCTAssertEqual(BMI.category(23.0, scale: .asian), .overweight, "23 is already overweight on the Asian scale")
        XCTAssertEqual(BMI.category(24.9, scale: .asian), .overweight)
        XCTAssertEqual(BMI.category(25.0, scale: .asian), .obese)
        XCTAssertNil(BMI.value(weightKg: 70, heightCm: 0))
    }

    func testBMIUsesWHOCutoffsInternationally() {
        XCTAssertEqual(BMI.category(23.0, scale: .international), .healthy)
        XCTAssertEqual(BMI.category(25.0, scale: .international), .overweight)
        XCTAssertEqual(BMI.category(29.9, scale: .international), .overweight)
        XCTAssertEqual(BMI.category(30.0, scale: .international), .obese)
        XCTAssertEqual(BMI.healthyWeight(heightCm: 170, scale: .international).upperBound, 71.96, accuracy: 0.01, "24.9 x 1.7^2")
        XCTAssertEqual(BMI.Category.healthy.range(.international), "18.5 – 24.9")
        XCTAssertEqual(BMI.pounds(70), 154.3, accuracy: 0.1)
    }

    func testHealthyWeightRangeAndUnits() {
        let range = BMI.healthyWeight(heightCm: 170, scale: .asian)
        XCTAssertEqual(range.lowerBound, 53.5, accuracy: 0.1)
        XCTAssertEqual(range.upperBound, 66.2, accuracy: 0.1)
        XCTAssertEqual(BMI.centimetres(feet: 5, inches: 7), 170.18, accuracy: 0.01)
        XCTAssertTrue(BMI.feetAndInches(170.18) == (5, 7))
    }

    func testCalorieTargetFollowsMifflinStJeor() {
        // Woman, 30, 160 cm, 60 kg: BMR 1289 x 1.375 = 1772 -> 1770.
        XCTAssertEqual(Calories.dailyTarget(age: 30, gender: .female, heightCm: 160, weightKg: 60), 1770)
        XCTAssertEqual(Calories.dailyTarget(age: 30, gender: .male, heightCm: 160, weightKg: 60), 2000)
        XCTAssertEqual(Calories.dailyTarget(age: 30, gender: nil, heightCm: 160, weightKg: 60), 1890, "BMR 1372 x 1.375 = 1886.5")
        let profile = Profile(name: "", age: 30, limitations: [], gender: .female, heightCm: 160, weightKg: 60)
        XCTAssertEqual(profile.calorieTarget, 1770)
        XCTAssertNil(Profile(name: "", age: 30, limitations: []).calorieTarget)
    }

    func testStepsDistance() {
        XCTAssertEqual(Steps.kilometres(8000), 6.0, accuracy: 0.001)
    }

    func testFoodLibraryIsSensible() {
        XCTAssertGreaterThan(FoodLibrary.indian.count, 50)
        XCTAssertGreaterThan(FoodLibrary.international.count, 40)
        XCTAssertTrue(FoodLibrary.international.allSatisfy { $0.cuisine == .international })
        XCTAssertEqual(Set(FoodLibrary.items.map(\.name)).count, FoodLibrary.items.count, "no duplicate names")
        XCTAssertTrue(FoodLibrary.items.allSatisfy { (1...800).contains($0.kcal) }, "black coffee is 5 kcal")
        XCTAssertEqual(FoodLibrary.search("DOSA").map(\.name), ["Plain dosa", "Masala dosa"])
    }
}

final class FoodRecognizerTests: XCTestCase {
    func testEverySuggestionIsInTheFoodList() {
        let names = Set(FoodLibrary.items.map(\.name))
        for (label, foods) in FoodRecognizer.suggestions {
            for food in foods { XCTAssertTrue(names.contains(food), "\(label) -> \(food) is not in FoodLibrary") }
        }
    }

    func testGuessesRankConfidentSpecificFoodsFirst() {
        let guesses = FoodRecognizer.guesses(from: [
            ("food", 0.97), ("fruit", 0.5), ("curry", 0.62), ("biryani", 0.81), ("yogurt", 0.3), ("teapot", 0.9), ("rice", 0.05),
        ])
        // "food" and "teapot" aren't foods we map, rice is below the threshold, and the generic
        // "fruit" comes after the specific dishes.
        XCTAssertEqual(guesses.map(\.label), ["biryani", "curry", "yogurt", "fruit"])
        XCTAssertEqual(guesses.first?.items.first?.name, "Chicken biryani")
        XCTAssertEqual(guesses[1].title, "Curry")
    }

    func testLocalDishesComeFirst() {
        let india = FoodRecognizer.guesses(from: [("pancake", 0.6)], preferIndian: true)
        let elsewhere = FoodRecognizer.guesses(from: [("pancake", 0.6)], preferIndian: false)
        XCTAssertEqual(india.first?.items.first?.name, "Plain dosa")
        XCTAssertEqual(elsewhere.first?.items.first?.name, "Pancakes")
    }

    func testEachFoodIsSuggestedOnce() {
        let guesses = FoodRecognizer.guesses(from: [("soup", 0.7), ("curry", 0.6)])
        let names = guesses.flatMap { $0.items.map(\.name) }
        XCTAssertEqual(names.count, Set(names).count)
        XCTAssertEqual(names.filter { $0 == "Dal" }.count, 1)
    }

    func testGenericLabelsOnlyFillInWhenNothingSpecificWasSeen() {
        XCTAssertEqual(FoodRecognizer.guesses(from: [("fruit", 0.2)]).map(\.label), ["fruit"])
        XCTAssertEqual(FoodRecognizer.guesses(from: [("naan", 0.5), ("fruit", 0.2)]).map(\.label), ["naan"])
        XCTAssertTrue(FoodRecognizer.guesses(from: [("teapot", 0.9), ("food", 0.9)]).isEmpty)
    }
}

final class TrackingStorageTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("floorage-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    func testFoodLogTotalsPerDayAndPersists() {
        let cal = Calendar.current
        let model = AppModel(fileURL: url)
        model.addFood(FoodEntry(name: "Idli", kcal: 60, servings: 3))
        model.addFood(FoodEntry(name: "Sambar", kcal: 110))
        let yesterday = cal.date(byAdding: .day, value: -1, to: Date())!
        model.addFood(FoodEntry(date: yesterday, name: "Samosa", kcal: 260))
        XCTAssertEqual(model.caloriesEaten(), 290)
        XCTAssertEqual(model.caloriesEaten(on: yesterday), 260)

        let reloaded = AppModel(fileURL: url)
        XCTAssertEqual(reloaded.foods().map(\.name), ["Idli", "Sambar"])
        reloaded.removeFood(id: reloaded.foods()[0].id)
        XCTAssertEqual(AppModel(fileURL: url).caloriesEaten(), 110)
    }

    func testBodyUpdatesKeepOneWeightPerDay() {
        let model = AppModel(fileURL: url)
        model.profile = Profile(name: "", age: 40, limitations: [])
        model.updateBody(heightCm: 170, weightKg: 72)
        model.updateBody(heightCm: 170, weightKg: 71.5)
        XCTAssertEqual(model.weights.count, 1)
        XCTAssertEqual(model.profile?.weightKg, 71.5)
        XCTAssertEqual(try XCTUnwrap(model.profile?.bmi), 24.74, accuracy: 0.01)
    }

    func testFilesFromTheOlderVersionStillLoad() throws {
        // Saved before food, weight, height and gender existed.
        let old = #"{"profile":{"name":"Ravi","age":61,"limitations":["knee"]},"results":[],"sessionDays":[748000000]}"#
        try Data(old.utf8).write(to: url)
        let model = AppModel(fileURL: url)
        XCTAssertEqual(model.profile?.name, "Ravi")
        XCTAssertEqual(model.sessionDays.count, 1)
        XCTAssertTrue(model.foodLog.isEmpty)
        XCTAssertNil(model.profile?.bmi)
    }
}

final class TrainingPlanTests: XCTestCase {
    private func profile(age: Int = 35, heightCm: Double = 170, weightKg: Double = 65, limits: Set<Limitation> = []) -> Profile {
        Profile(name: "", age: age, limitations: limits, gender: .male, heightCm: heightCm, weightKg: weightKg)
    }

    func testProgramFollowsWeightAgeAndLimitations() {
        // 170 cm: 65 kg is BMI 22.5, 76 kg 26.3, 90 kg 31.1.
        XCTAssertEqual(TrainingPlan.recommendedProgram(for: profile(weightKg: 65), scale: .international), .runWalk)
        XCTAssertEqual(TrainingPlan.recommendedProgram(for: profile(weightKg: 76), scale: .international), .briskWalk)
        XCTAssertEqual(TrainingPlan.recommendedProgram(for: profile(weightKg: 90), scale: .international), .gentleWalk)
        XCTAssertEqual(TrainingPlan.recommendedProgram(for: profile(weightKg: 65), scale: .asian), .runWalk)
        XCTAssertEqual(TrainingPlan.recommendedProgram(for: profile(weightKg: 76), scale: .asian), .gentleWalk, "26.3 is obese on the Asian scale")
        XCTAssertEqual(TrainingPlan.recommendedProgram(for: profile(age: 62), scale: .international), .briskWalk)
        XCTAssertEqual(TrainingPlan.recommendedProgram(for: profile(limits: [.knee]), scale: .international), .briskWalk)
        XCTAssertEqual(TrainingPlan.recommendedProgram(for: profile(age: 72), scale: .international), .gentleWalk)
        XCTAssertEqual(TrainingPlan.recommendedProgram(for: profile(weightKg: 50), scale: .international), .briskWalk, "underweight: no running")
    }

    func testCouchTo5KMatchesTheNHSPlan() {
        let week1 = TrainingPlan.couchTo5K(week: 1, run: 0)
        XCTAssertEqual(week1.filter { $0.kind == .run }.count, 8)
        XCTAssertEqual(week1.filter { $0.kind == .walk }.map(\.seconds), Array(repeating: 90, count: 7))
        XCTAssertEqual(week1.first, TrainingPlan.Interval(kind: .warmUp, seconds: 300))
        XCTAssertEqual(week1.last, TrainingPlan.Interval(kind: .coolDown, seconds: 300))
        XCTAssertEqual(TrainingPlan.couchTo5K(week: 5, run: 2).filter { $0.kind == .run }.map(\.seconds), [1200])
        XCTAssertEqual(TrainingPlan.couchTo5K(week: 9, run: 0).filter { $0.kind == .run }.map(\.seconds), [1800])
        XCTAssertEqual(TrainingPlan.describe(week1), "5 min walk, (run 1 min, walk 1½ min) × 7, run 1 min, 5 min walk")
    }

    func testRunWalkWeekHasThreeRunsWithRestBetween() {
        let week = TrainingPlan.week(1, program: .runWalk, profile: profile(), averageSteps: nil, scale: .international)
        let runDays = week.days.filter { $0.activities.contains { if case .cardio(.runWalk, _) = $0 { true } else { false } } }.map(\.index)
        XCTAssertEqual(runDays, [0, 2, 4])
        let strengthDays = week.days.filter { $0.activities.contains { if case .strength = $0 { true } else { false } } }.count
        XCTAssertEqual(strengthDays, 2, "WHO: strength on 2+ days")
        XCTAssertEqual(week.days.last?.activities, [.rest])
    }

    func testWalkingBuildsToTheWeeklyTarget() {
        let overweight = profile(weightKg: 76)
        let first = TrainingPlan.week(1, program: .briskWalk, profile: overweight, averageSteps: nil, scale: .international)
        let last = TrainingPlan.week(12, program: .briskWalk, profile: overweight, averageSteps: nil, scale: .international)
        XCTAssertEqual(first.targetMinutes, 250, "ACSM: over 250 min a week for weight loss")
        XCTAssertLessThan(first.aerobicMinutes, last.aerobicMinutes)
        XCTAssertGreaterThanOrEqual(last.aerobicMinutes, 250)
        let healthy = TrainingPlan.week(12, program: .briskWalk, profile: profile(age: 62), averageSteps: nil, scale: .international)
        XCTAssertEqual(healthy.targetMinutes, 150)
        XCTAssertGreaterThanOrEqual(healthy.aerobicMinutes, 150, "WHO: at least 150 min")
    }

    func testSetsAndStepsProgressWithinGuidelines() {
        let p = profile()
        XCTAssertEqual(TrainingPlan.week(1, program: .runWalk, profile: p, averageSteps: 5000).sets, 1)
        XCTAssertEqual(TrainingPlan.week(3, program: .runWalk, profile: p, averageSteps: 5000).sets, 2)
        XCTAssertEqual(TrainingPlan.week(6, program: .runWalk, profile: p, averageSteps: 5000).sets, 3)
        XCTAssertEqual(TrainingPlan.week(6, program: .gentleWalk, profile: p, averageSteps: 5000).sets, 2)
        XCTAssertEqual(TrainingPlan.week(1, program: .runWalk, profile: p, averageSteps: 5000).stepGoal, 5000)
        XCTAssertEqual(TrainingPlan.week(3, program: .runWalk, profile: p, averageSteps: 5000).stepGoal, 7000)
        XCTAssertEqual(TrainingPlan.week(9, program: .runWalk, profile: p, averageSteps: 5000).stepGoal, 10000, "capped at 10,000 under 60")
        XCTAssertEqual(TrainingPlan.week(12, program: .briskWalk, profile: profile(age: 65), averageSteps: 5000).stepGoal, 8000, "capped at 8,000 from 60")
    }

    func testOlderAdultsGetBalanceThreeDaysAndUnsafeMovesAreLeftOut() {
        let week = TrainingPlan.week(4, program: .briskWalk, profile: profile(age: 67, limits: [.knee]), averageSteps: nil, scale: .international)
        let balanceDays = week.days.filter { $0.activities.contains { if case .balance = $0 { true } else { false } } }.count
        XCTAssertEqual(balanceDays, 3, "WHO: balance on 3+ days from 65")
        let unsafe = PlanBuilder.unsafe(for: [.knee])
        for case .strength(_, let moves) in week.days.flatMap(\.activities) {
            XCTAssertTrue(moves.allSatisfy { !unsafe.contains($0.exerciseID) })
        }
        XCTAssertEqual(TrainingPlan.sessionItems(sets: 2, moves: [.init(exerciseID: "calf_raise", reps: 10, seconds: nil)]).count, 2)
    }

    func testPlanDatesAndDoneDaysPersist() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("floorage-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let cal = Calendar.current
        let model = AppModel(fileURL: url)
        model.startPlan(.briskWalk, averageSteps: 4200, on: cal.date(byAdding: .day, value: -9, to: Date())!)
        XCTAssertTrue(try XCTUnwrap(model.planPosition()) == (2, 2))
        model.setPlanDay(Date(), done: true)
        let reloaded = AppModel(fileURL: url)
        XCTAssertEqual(reloaded.planProgram, .briskWalk)
        XCTAssertEqual(reloaded.planBaseSteps, 4200)
        XCTAssertTrue(reloaded.isPlanDayDone(Date()))
        reloaded.stopPlan()
        XCTAssertNil(AppModel(fileURL: url).planPosition())
    }
}

final class SleepTests: XCTestCase {
    private let cal = Calendar.current

    private func at(_ daysAgo: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(bySettingHour: hour, minute: minute, second: 0, of: cal.date(byAdding: .day, value: -daysAgo, to: Date())!)!
    }

    func testRecommendedHoursByAge() {
        XCTAssertEqual(SleepGuide.recommended(age: 40), 7...9)
        XCTAssertEqual(SleepGuide.recommended(age: 70), 7...8)
        XCTAssertTrue(SleepGuide.assessment(hours: 7.5, age: 40).contains("Right in"))
        XCTAssertTrue(SleepGuide.assessment(hours: 5.5, age: 40).contains("short"))
        XCTAssertEqual(SleepGuide.duration(6.75), "6 h 45 min")
    }

    func testHealthSamplesMergeIntoOneNightWithoutDoubleCounting() {
        // iPhone and Watch both recorded the same night; plus an in-bed record.
        let samples = [
            SleepGuide.Sample(start: at(1, 23), end: at(0, 3), asleep: true),
            SleepGuide.Sample(start: at(0, 2), end: at(0, 6, 30), asleep: true),
            SleepGuide.Sample(start: at(1, 22, 30), end: at(0, 7), asleep: false),
        ]
        let nights = SleepGuide.nights(from: samples)
        XCTAssertEqual(nights.count, 1)
        XCTAssertEqual(nights[0].minutesAsleep, 450, "23:00-06:30 asleep, overlap counted once, in-bed ignored")
        XCTAssertEqual(nights[0].day, cal.startOfDay(for: Date()))
        // Only in-bed data: use it.
        let inBed = SleepGuide.nights(from: [SleepGuide.Sample(start: at(2, 23), end: at(1, 7), asleep: false)])
        XCTAssertEqual(inBed.first?.hours ?? 0, 8, accuracy: 0.01)
    }

    func testManualNightsWinOverHealthAndPersist() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("floorage-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let model = AppModel(fileURL: url)
        model.logSleep(SleepEntry(bedtime: at(1, 23), wake: at(0, 6), quality: 3))
        model.importSleep([SleepEntry(bedtime: at(1, 22), wake: at(0, 7), minutesAsleep: 500, fromHealth: true),
                           SleepEntry(bedtime: at(2, 23), wake: at(1, 7), minutesAsleep: 420, fromHealth: true)])
        let reloaded = AppModel(fileURL: url)
        XCTAssertEqual(reloaded.sleepLog.count, 2)
        XCTAssertEqual(reloaded.sleepLog.last?.hours ?? 0, 7, accuracy: 0.01, "the night logged by hand is kept")
        XCTAssertEqual(reloaded.averageSleep ?? 0, 7, accuracy: 0.01)
    }
}

final class ReminderTextTests: XCTestCase {
    func testReminderNamesTheDaysPlanAndSkipsRestDays() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("floorage-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let model = AppModel(fileURL: url)
        model.profile = Profile(name: "", age: 35, limitations: [], gender: .female, heightCm: 165, weightKg: 58)
        XCTAssertEqual(model.reminderText(on: Date()), "Your 10-minute session with Coach is ready. Missing a day never resets your progress.")
        model.startPlan(.runWalk, averageSteps: 5000, on: Date())
        XCTAssertEqual(model.reminderText(on: Date()), "Today: Run/walk 28 min. A little now keeps your streak going.")
        let restDay = Calendar.current.date(byAdding: .day, value: 6, to: Date())!
        XCTAssertNil(model.reminderText(on: restDay), "no reminder on the plan's rest day")
    }
}

@MainActor
final class RealisticCoachTests: XCTestCase {
    let library = ExerciseLibrary.shared

    private func coach(_ look: CoachLook) throws -> RealisticCoach {
        try XCTUnwrap(RealisticCoach(look: look, rig: library.rig), "coach_\(look.rawValue).usdz should load")
    }

    private func lowestFoot(_ p: [String: SIMD3<Float>]) -> Float {
        ["foot_l", "foot_r", "ball_l", "ball_r"].compactMap { p[$0]?.y }.min() ?? .infinity
    }

    func testBothCoachesStandUpright() throws {
        for look in [CoachLook.female, .male] {
            let body = try coach(look)
            let solver = PoseSolver(rig: library.rig)
            body.apply(Pose(angles: [:], pelvis: solver.solvePelvis([:], ground: .feet, seatZ: 0, rootZ: 0)))
            let p = body.lastPositions
            let head = try XCTUnwrap(p["head"]), pelvis = try XCTUnwrap(p["pelvis"])
            XCTAssertGreaterThan(head.y, 1.3, "\(look) head height")
            XCTAssertGreaterThan(head.y, pelvis.y + 0.4, "\(look) head above pelvis")
            XCTAssertLessThan(lowestFoot(p), 0.1, "\(look) feet near the floor")
            XCTAssertGreaterThanOrEqual(lowestFoot(p), -0.02, "\(look) feet not below the floor")
            // Arms hang at the sides, below the chest.
            XCTAssertLessThan(try XCTUnwrap(p["hand_l"]).y, pelvis.y + 0.1)
            XCTAssertGreaterThan(try XCTUnwrap(p["hand_l"]).x, 0.05, "left hand on the left (+x)")
        }
    }

    func testExercisesMoveTheBody() throws {
        let body = try coach(.female)
        let squat = ExerciseClip(exercise: library["squat"])
        body.apply(squat.sample(at: squat.duration / 2))
        XCTAssertLessThan(try XCTUnwrap(body.lastPositions["pelvis"]).y, 0.6, "squat goes low")

        let raise = ExerciseClip(exercise: library["arm_raise"])
        body.apply(raise.sample(at: raise.duration / 2))
        XCTAssertGreaterThan(try XCTUnwrap(body.lastPositions["hand_l"]).y, 1.1, "arms raised")

        let kegel = ExerciseClip(exercise: library["kegel"])
        body.apply(kegel.sample(at: 2))
        let pelvis = try XCTUnwrap(body.lastPositions["pelvis"])
        XCTAssertEqual(pelvis.y, 0.5, accuracy: 0.15, "seated on the chair")
        XCTAssertLessThan(lowestFoot(body.lastPositions), 0.1, "feet on the floor while seated")
    }
}
