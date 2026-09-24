import XCTest
import simd
import SwiftUI
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

    func testChosenCoachWinsOverGenderAndOldProfilesFollowGender() throws {
        // Saved before the coach choice existed.
        let old = try JSONDecoder().decode(Profile.self, from: Data(#"{"name":"Raj","age":70,"limitations":[],"gender":"male"}"#.utf8))
        XCTAssertNil(old.coach)
        XCTAssertEqual(old.coachLook, .male)
        XCTAssertEqual(Profile(name: "", age: 40, limitations: []).coachLook, .female)

        let model = AppModel(fileURL: url)
        model.profile = Profile(name: "Raj", age: 70, limitations: [], gender: .male, coach: .female)
        XCTAssertEqual(AppModel(fileURL: url).profile?.coachLook, .female)
    }

    func testStreakCountsDaysInARowIncludingPlanDays() {
        let model = AppModel(fileURL: url)
        let cal = Calendar.current
        let today = Date()
        func daysAgo(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: today)! }
        XCTAssertEqual(model.streak(on: today), 0)
        model.completeSession(on: daysAgo(1))
        model.setPlanDay(daysAgo(2), done: true)
        model.completeSession(on: daysAgo(4))
        // Not trained yet today: yesterday's run still counts.
        XCTAssertEqual(model.streak(on: today), 2)
        model.completeSession(on: today)
        XCTAssertEqual(model.streak(on: today), 3)
        // A gap ends it.
        XCTAssertEqual(model.streak(on: daysAgo(3)), 1)
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

    func testEveryFocusTagIsAnAreaOrAWarmUp() {
        // A new tag in exercises.json needs a TrainingArea, or the session loses its colours.
        for exercise in library.exercises {
            for tag in exercise.focus where tag != "warmup" {
                XCTAssertNotNil(TrainingArea(focus: tag), "\(exercise.id): \(tag)")
            }
        }
        XCTAssertEqual(library["squat"].areas, [.legs, .floor])
        XCTAssertEqual(library["kegel"].feature, TrainingArea.pelvicFloor.feature)
    }

    func testPoseThumbnailShowsTheKeyPositionInsideThePicture() {
        let size = CGSize(width: 72, height: 72)
        for exercise in library.exercises where exercise.id != "idle" {
            let joints = PoseThumbnail.joints(for: exercise, size: size)
            XCTAssertEqual(Set(joints.keys), Set(BodyJoint.allCases), exercise.id)
            for (joint, p) in joints {
                XCTAssertTrue(CGRect(origin: .zero, size: size).contains(p), "\(exercise.id) \(joint) at \(p)")
            }
        }
        // The squat shows the bottom of the squat: hips nearly down at the knees (y grows downwards).
        let squat = PoseThumbnail.joints(for: library["squat"], size: size)
        let thigh = squat[.leftKnee]!.y - squat[.leftHip]!.y
        let shin = squat[.leftAnkle]!.y - squat[.leftKnee]!.y
        XCTAssertLessThan(thigh, shin * 0.6)
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
        let habit = DailyHabit.today(area: nil, on: restDay).text
        XCTAssertEqual(model.reminderText(on: restDay), "Rest day. Today's small habit: \(habit)", "rest days only carry the small habit")
    }
}

final class LocalizationTests: XCTestCase {
    /// Hindi and Spanish are bundled for screens, exercise instructions and food names.
    func testHindiAndSpanishShipInTheApp() throws {
        try XCTSkipUnless(Bundle.main.path(forResource: "hi", ofType: "lproj") != nil, "needs the app bundle")
        for language in ["hi", "es"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"), language)
            let bundle = try XCTUnwrap(Bundle(path: path))
            XCTAssertNotEqual(bundle.localizedString(forKey: "Today", value: nil, table: nil), "Today", language)
            XCTAssertNotEqual(ExerciseLibrary.shared["squat"].localized(bundle: bundle).intro,
                              ExerciseLibrary.shared["squat"].intro, "\(language) exercise instructions")
            XCTAssertNotEqual(bundle.localizedString(forKey: "Scrambled eggs", value: nil, table: "Foods"), "Scrambled eggs", language)
        }
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

@MainActor
final class StoreTests: XCTestCase {
    func testOnlyAnUnrefundedPlusPurchaseUnlocks() {
        XCTAssertTrue(Store.unlocks(Store.plusID, revoked: false))
        XCTAssertFalse(Store.unlocks(Store.plusID, revoked: true), "a refunded purchase locks Plus again")
        XCTAssertFalse(Store.unlocks("com.jeyaraj.floorage.other", revoked: false))
    }

    func testProductBelongsToTheApp() {
        // App Store Connect product IDs must sit under the app's bundle ID.
        XCTAssertTrue(Store.plusID.hasPrefix("com.jeyaraj.floorage."))
    }

    func testPreviewStoreNeverTouchesStoreKit() async {
        let locked = Store(preview: false)
        XCTAssertFalse(locked.hasPlus)
        XCTAssertEqual(locked.price, "$4.99")
        let restored = await locked.restore()
        XCTAssertNil(restored)
        XCTAssertFalse(locked.hasPlus)
        XCTAssertTrue(Store(preview: true).hasPlus)
    }
}

final class FamilyTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func newModel() -> AppModel { AppModel(fileURL: dir.appendingPathComponent("floorage.json")) }

    func testEachMemberKeepsTheirOwnData() {
        let model = newModel()
        model.profile = Profile(name: "Priya", age: 52, limitations: [])
        model.add(FloorAgeResult(age: 52, scores: ["sitRise": 7, "balance": 20, "chairStand": 14, "reach": 3]))
        model.addMember()
        XCTAssertNil(model.profile, "a new member starts with onboarding")
        XCTAssertFalse(model.isOwner)
        model.profile = Profile(name: "Raj", age: 78, limitations: [.knee], gender: .male)
        XCTAssertTrue(model.results.isEmpty)

        model.switchMember(model.owner.id)
        XCTAssertEqual(model.profile?.name, "Priya")
        XCTAssertEqual(model.results.count, 1)
        XCTAssertEqual(model.members.map(\.name), ["Priya", "Raj"])
        XCTAssertEqual(model.members[1].age, 78)
        XCTAssertEqual(model.members[0].floorAge, model.results.last?.floorAge)
    }

    func testFamilyAndActiveMemberSurviveARestart() {
        let model = newModel()
        model.profile = Profile(name: "Priya", age: 52, limitations: [])
        model.addMember()
        model.profile = Profile(name: "Meena", age: 74, limitations: [.hip])
        let reopened = newModel()
        XCTAssertEqual(reopened.members.count, 2)
        XCTAssertEqual(reopened.profile?.name, "Meena", "reopens as whoever was active")
        XCTAssertFalse(reopened.isOwner)
    }

    func testCancellingANewMemberGoesBack() {
        let model = newModel()
        model.profile = Profile(name: "Priya", age: 52, limitations: [])
        model.addMember()
        XCTAssertTrue(model.canCancelNewMember)
        model.cancelNewMember()
        XCTAssertEqual(model.members.count, 1)
        XCTAssertEqual(model.profile?.name, "Priya")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("floorage-family.json").path),
                       "one person needs no family index")
    }

    func testRemovingAMemberDeletesTheirFileButNeverTheOwner() throws {
        let model = newModel()
        model.profile = Profile(name: "Priya", age: 52, limitations: [])
        model.addMember()
        model.profile = Profile(name: "Raj", age: 78, limitations: [])
        let raj = model.activeMemberID
        let rajFile = dir.appendingPathComponent(try XCTUnwrap(model.members.last).file)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rajFile.path))
        model.removeMember(model.owner.id)
        XCTAssertEqual(model.members.count, 2, "the owner can't be removed")
        model.removeMember(raj)
        XCTAssertEqual(model.members.count, 1)
        XCTAssertTrue(model.isOwner)
        XCTAssertEqual(model.profile?.name, "Priya")
        XCTAssertFalse(FileManager.default.fileExists(atPath: rajFile.path))
    }

    func testDeletingAFamilyMembersDataRemovesOnlyThem() {
        let model = newModel()
        model.profile = Profile(name: "Priya", age: 52, limitations: [])
        model.addMember()
        model.profile = Profile(name: "Raj", age: 78, limitations: [])
        model.resetAll()
        XCTAssertEqual(model.members.count, 1)
        XCTAssertEqual(model.profile?.name, "Priya")
    }

    func testASinglePersonUsesTheOriginalFile() {
        let model = newModel()
        model.profile = Profile(name: "Priya", age: 52, limitations: [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("floorage.json").path))
        XCTAssertEqual(model.members.count, 1)
        XCTAssertTrue(model.isOwner)
    }
}

final class PoseScoringTests: XCTestCase {
    /// Holds each posture for several frames, like a camera at 15–30 fps.
    private func frames(_ pose: BodyPose, _ count: Int = 6) -> [BodyPose] { Array(repeating: pose, count: count) }

    func testChairStandsCountEachFullStandFromSitting() {
        var counter = ChairStandCounter()
        let seated = BodyPose.sample(rise: 0.05), standing = BodyPose.sample(rise: 1)
        var poses = frames(seated)
        for _ in 0..<3 { poses += frames(standing) + frames(seated) }
        for pose in poses { _ = counter.update(pose) }
        XCTAssertEqual(counter.count, 3)
    }

    func testStartingOnYourFeetAndHalfStandsDontCount() {
        var counter = ChairStandCounter()
        // Starts standing, sits, then only half rises twice, then one full stand.
        let poses = frames(.sample(rise: 1)) + frames(.sample(rise: 0.1))
            + frames(.sample(rise: 0.5)) + frames(.sample(rise: 0.1)) + frames(.sample(rise: 0.55)) + frames(.sample(rise: 0.1))
            + frames(.sample(rise: 0.95))
        for pose in poses { _ = counter.update(pose) }
        XCTAssertEqual(counter.count, 1)
    }

    func testOneStrayFrameIsIgnored() {
        var counter = ChairStandCounter()
        let poses = frames(.sample(rise: 0)) + [.sample(rise: 1)] + frames(.sample(rise: 0))
        for pose in poses { _ = counter.update(pose) }
        XCTAssertEqual(counter.count, 0)
    }

    func testChairStandIgnoresFramesWithoutLegs() {
        var counter = ChairStandCounter()
        var noLegs = BodyPose.sample(rise: 1)
        noLegs.joints[.leftKnee] = nil
        noLegs.joints[.rightKnee] = nil
        XCTAssertFalse(noLegs.legsVisible)
        XCTAssertFalse(counter.update(noLegs))
    }

    func testBalanceNoticesTheFootLiftingAndTouchingDown() {
        var detector = BalanceDetector()
        var events: [BalanceDetector.Event] = []
        for pose in frames(.sample()) + frames(.sample(lift: 1)) + frames(.sample(lift: 0.8)) + frames(.sample()) {
            if let event = detector.update(pose) { events.append(event) }
        }
        XCTAssertEqual(events, [.lifted, .down])
    }

    func testReachBands() {
        XCTAssertEqual(ReachEstimator.level(depth: -0.1), .palmsFlat)
        XCTAssertEqual(ReachEstimator.level(depth: 0.08), .fingersToFloor)
        XCTAssertEqual(ReachEstimator.level(depth: 0.25), .toes)
        XCTAssertEqual(ReachEstimator.level(depth: 0.45), .ankles)
        XCTAssertEqual(ReachEstimator.level(depth: 0.9), .shins)
        XCTAssertEqual(ReachEstimator.level(depth: 1.4), .knees)
    }

    func testReachKeepsTheDeepestPointAndIgnoresStanding() {
        var estimator = ReachEstimator()
        estimator.update(.sample())  // hands at the hips: not folded, no reading
        XCTAssertNil(estimator.level)
        for fold in stride(from: 0.2, through: 1.0, by: 0.2) { estimator.update(.sample(fold: fold, wristDepth: 0.45)) }
        estimator.update(.sample(fold: 0.5, wristDepth: 0.45))  // coming back up
        XCTAssertEqual(estimator.level, .ankles)
    }
}

final class PoseMirrorTests: XCTestCase {
    private let mirror = PoseMirror(rig: ExerciseLibrary.shared.rig)
    private let aspect = 720.0 / 1280.0

    private func angles(_ body: BodyPose) throws -> [String: SIMD3<Float>] {
        try XCTUnwrap(mirror.pose(from: body, aspect: aspect)).angles
    }

    func testEulerAnglesRoundTrip() {
        for degrees in [SIMD3<Float>(-80, 20, 10), SIMD3(30, -45, 60), SIMD3(0, 0, -20), SIMD3(95, 10, -5)] {
            let q = PoseSolver.localRotation(degrees)
            let back = PoseSolver.localRotation(PoseMirror.eulerDegrees(q))
            for v in [SIMD3<Float>(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)] {
                XCTAssertLessThan(simd_distance(q.act(v), back.act(v)), 0.001, "\(degrees)")
            }
        }
    }

    func testStandingMirrorsAsStanding() throws {
        let a = try angles(.sample())
        for joint in ["lHip", "rHip", "lKnee", "rKnee"] {
            XCTAssertLessThan(abs(a[joint]?.x ?? 0), 15, joint)
        }
        XCTAssertLessThan(simd_length(a["pelvis"] ?? .zero), 15, "upright and facing the camera")
    }

    func testSittingBendsHipsAndKnees() throws {
        let a = try angles(.sample(rise: 0.02, armsCrossed: true))
        // Thighs swing forward (negative x) and the knees bend (positive x), about 90° each.
        XCTAssertEqual(a["lHip"]?.x ?? 0, -90, accuracy: 25)
        XCTAssertEqual(a["lKnee"]?.x ?? 0, 90, accuracy: 30)
        let pose = try XCTUnwrap(mirror.pose(from: .sample(rise: 0.02), aspect: aspect))
        let standing = try XCTUnwrap(mirror.pose(from: .sample(), aspect: aspect))
        XCTAssertLessThan(pose.pelvis.y, standing.pelvis.y - 0.25, "seated is lower")
    }

    func testLiftingAFootRaisesThatKnee() throws {
        let a = try angles(.sample(lift: 1))
        XCTAssertLessThan(a["lHip"]?.x ?? 0, -20, "left thigh comes forward")
        XCTAssertLessThan(abs(a["rHip"]?.x ?? 0), 15, "standing leg stays straight")
    }

    func testSideOnFoldTipsTheBodyForward() throws {
        let a = try angles(.sample(fold: 1, wristDepth: 0.3))
        let pelvis = PoseSolver.localRotation(a["pelvis"] ?? .zero)
        // The trunk's up direction ends up mostly horizontal.
        XCTAssertLessThan(pelvis.act(SIMD3(0, 1, 0)).y, 0.4)
        // And the legs still point down to the floor.
        let thigh = pelvis * PoseSolver.localRotation(a["lHip"] ?? .zero)
        XCTAssertLessThan(thigh.act(SIMD3(0, -1, 0)).y, -0.9)
    }
}

final class ChallengeTests: XCTestCase {
    private let cal = Calendar.current
    private func day(_ offset: Int, from start: Date) -> Date { cal.date(byAdding: .day, value: offset, to: start)! }

    func testCountsOnlyDaysInsideTheThirty() {
        let start = cal.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000))
        let trained = Set([-1, 0, 1, 2, 5, 29, 30].map { day($0, from: start) })
        let challenge = Challenge(start: start, trainedDays: trained)
        XCTAssertEqual(challenge.completed, 5, "the day before and day 31 don't count")
        XCTAssertEqual(challenge.earned, [.three])
        XCTAssertEqual(challenge.nextBadge, .seven)
        XCTAssertEqual(challenge.dayNumber(on: day(9, from: start)), 10)
        XCTAssertEqual(challenge.dayNumber(on: day(45, from: start)), 30)
        XCTAssertFalse(challenge.isOver(on: day(29, from: start)))
        XCTAssertTrue(challenge.isOver(on: day(30, from: start)))
    }

    func testSessionsAndPlanDaysEarnBadgesOnce() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let model = AppModel(fileURL: url)
        let start = cal.date(byAdding: .day, value: -5, to: Date())!
        model.startChallenge(on: start)
        model.completeSession(on: day(0, from: start))
        model.setPlanDay(day(1, from: start), done: true)
        XCTAssertNil(model.newBadge)
        model.completeSession(on: day(2, from: start))
        XCTAssertEqual(model.newBadge, .three)
        model.newBadge = nil
        model.completeSession(on: day(2, from: start))  // same day again
        XCTAssertNil(model.newBadge)
        XCTAssertEqual(AppModel(fileURL: url).challenge?.completed, 3, "the challenge is saved")
    }

    func testRetestIsFourWeeksAfterTheLastCheck() {
        let check = cal.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 10))!
        XCTAssertFalse(Retest.isDue(lastCheck: check, on: cal.date(byAdding: .day, value: 27, to: check)!))
        XCTAssertTrue(Retest.isDue(lastCheck: check, on: cal.date(byAdding: .day, value: 28, to: check)!))
        let reminder = Reminders.retestDate(lastCheck: check, minuteOfDay: 18 * 60, now: check)
        XCTAssertEqual(cal.dateComponents([.month, .day, .hour], from: reminder), DateComponents(month: 3, day: 29, hour: 18))
        // Overdue: the next evening instead.
        let late = cal.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 19))!
        let next = Reminders.retestDate(lastCheck: check, minuteOfDay: 18 * 60, now: late)
        XCTAssertEqual(cal.dateComponents([.month, .day, .hour], from: next), DateComponents(month: 5, day: 11, hour: 18))
    }
}

final class WristRepCounterTests: XCTestCase {
    /// Vertical acceleration (g) for moving the wrist `height` metres up (or down) smoothly in `duration` s.
    private func move(_ height: Double, over duration: Double, rate: Double = 50) -> [Double] {
        let n = Int(duration * rate)
        return (0..<n).map { i in
            let t = Double(i) / rate
            return height / 2 * pow(.pi / duration, 2) * cos(.pi * t / duration) / 9.81
        }
    }

    private func hold(_ seconds: Double, rate: Double = 50) -> [Double] { Array(repeating: 0, count: Int(seconds * rate)) }

    private func count(_ samples: [Double], noise: Double = 0.015) -> Int {
        var counter = WristRepCounter()
        var generator = SystemRandomNumberGenerator()
        for (i, a) in samples.enumerated() {
            _ = counter.add(verticalAcceleration: a + Double.random(in: -noise...noise, using: &generator), at: Double(i) / 50)
        }
        return counter.count
    }

    func testCountsEachStand() {
        var samples = hold(0.5)
        for _ in 0..<8 { samples += move(0.4, over: 0.8) + hold(0.3) + move(-0.4, over: 0.9) + hold(0.4) }
        XCTAssertEqual(count(samples), 8)
    }

    func testFastStandsStillCount() {
        var samples = hold(0.3)
        for _ in 0..<12 { samples += move(0.4, over: 0.6) + move(-0.4, over: 0.6) + hold(0.1) }
        XCTAssertEqual(count(samples), 12)
    }

    func testSittingDownAndFidgetingDontCount() {
        let samples = hold(0.5) + move(-0.4, over: 0.9) + hold(1) + move(0.03, over: 0.4) + move(-0.03, over: 0.4) + hold(1)
        XCTAssertEqual(count(samples), 0)
    }
}

final class Tier2Tests: XCTestCase {
    func testSnapshotRollsForwardToALaterDay() {
        var snapshot = FloorAgeSnapshot.sample
        snapshot.updated = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        snapshot.week = [true, false, true, true, false, true, true]
        let today = snapshot.rolledForward(to: Date())
        XCTAssertEqual(today.week, [true, true, false, true, true, false, false])
        XCTAssertEqual(today.stepsToday, 0)
        XCTAssertFalse(today.trainedToday)
        XCTAssertEqual(today.challengeDay, 14)
        XCTAssertEqual(FloorAgeSnapshot.sample.rolledForward(to: Date()), FloorAgeSnapshot.sample.rolledForward(to: Date()))
    }

    func testSnapshotSavesAndLoads() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "floorage-tests-\(UUID().uuidString)"))
        FloorAgeSnapshot.sample.save(to: defaults)
        XCTAssertEqual(FloorAgeSnapshot.load(from: defaults)?.floorAge, 56)
    }

    func testWorkoutEnergyFromMETs() {
        // 3.5 MET × 70 kg × 10 minutes ≈ 41 kcal.
        XCTAssertEqual(Calories.burned(met: Calories.MET.session, weightKg: 70, minutes: 10), 41)
        let run = TrainingPlan.Interval(kind: .run, seconds: 60)
        XCTAssertGreaterThan(run.met, TrainingPlan.Interval(kind: .walk, seconds: 60).met)
    }

    func testWatchMessagesRoundTrip() {
        let status = SessionStatus(exercise: "Squat", detail: "6/10 reps", progress: 0.6, step: "2 of 5", isPaused: false, isResting: false, isDone: false)
        XCTAssertEqual(SessionStatus.fromWatch(status.watchData), status)
        let result = WatchTestResult(test: .chairStand, value: 14)
        XCTAssertEqual(WatchTestResult.fromWatch(result.watchData)?.value, 14)
    }
}

final class CoachPresentationTests: XCTestCase {
    func testWeightShiftRollsThePelvisAndKeepsTheHeadLevel() {
        let base = Pose(angles: [:], pelvis: .zero)
        let shifted = base.withWeightShift(time: 1, amount: 1)  // a quarter of the 4 s cycle: full roll
        XCTAssertEqual(shifted.angles["pelvis"]?.z ?? 0, 1.5, accuracy: 0.01)
        XCTAssertEqual(shifted.angles["chest"]?.z ?? 0, -1.2, accuracy: 0.01)
        XCTAssertEqual(base.withWeightShift(time: 1, amount: 0).angles["pelvis"], nil)
    }

    func testHeadTurnsTowardsTheViewerUpToTwentyDegrees() {
        let base = Pose(angles: [:], pelvis: .zero)
        XCTAssertEqual(base.lookingAtViewer(bodyYaw: 10, amount: 1).angles["neck"]?.y ?? 0, -10, accuracy: 0.01)
        XCTAssertEqual(base.lookingAtViewer(bodyYaw: 80, amount: 1).angles["neck"]?.y ?? 0, -20, accuracy: 0.01)
        XCTAssertEqual(base.lookingAtViewer(bodyYaw: 80, amount: 0.5).angles["neck"]?.y ?? 0, -10, accuracy: 0.01)
    }

    func testExercisesHaveABestCameraAngle() {
        let library = ExerciseLibrary.shared
        XCTAssertEqual(library.exercise("toe_reach")?.cameraYaw, 35, "turned more than the default, and the fold still fits a phone screen")
        XCTAssertTrue(library.exercises.allSatisfy { $0.cameraYaw != nil })
    }
}

final class ThemeTests: XCTestCase {
    func testFeatureInkReadsOnCardsInLightAndDarkMode() {
        let all: [Feature] = [.steps, .calories, .bmi, .sleep, .plan, .floorAge, .glance, .plus, .challenge]
        for (style, card) in [(UIUserInterfaceStyle.light, (1.0, 0.99, 0.98)), (.dark, (0.02, 0.02, 0.026))] {
            for feature in all {
                for ink in feature.inkColors {
                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                    UIColor(ink).resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(&r, green: &g, blue: &b, alpha: &a)
                    let ratio = Color.contrast((r, g, b), (CGFloat(card.0), CGFloat(card.1), CGFloat(card.2)))
                    XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(feature) in \(style == .dark ? "dark" : "light") mode: \(ratio)")
                }
            }
        }
    }
}

final class ProgressionTests: XCTestCase {
    private let cal = Calendar.current
    private let library = ExerciseLibrary.shared

    private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: Date()))! }

    private func log(_ target: Int, _ done: Int, _ effort: Effort? = nil, on offset: Int = 0) -> SessionLog {
        SessionLog(date: day(offset), targetReps: target, doneReps: done, rpe: effort?.rawValue)
    }

    func testEveryFamilyHasFourLevelsOfKnownExercises() {
        XCTAssertEqual(Set(library.families.map(\.id)), ["sit_to_stand", "squat", "balance", "calf_raise", "floor"])
        for family in library.families {
            XCTAssertEqual(family.levels.count, 4, family.id)
            XCTAssertNotNil(library.exercise(family.anchor), family.id)
            XCTAssertTrue(family.levels.indices.contains(family.start), family.id)
            for level in family.levels { XCTAssertNotNil(library.exercise(level.exercise), "\(family.id) \(level.exercise)") }
        }
        XCTAssertEqual(library.family("sit_to_stand")?.exercise(at: 2).name, "Low Chair Stand")
        // Each level shows its own movement: a low seat, a chair to touch, eyes shut, hands free.
        XCTAssertEqual(library.family("sit_to_stand")?.exercise(at: 2).id, "low_chair_stand")
        XCTAssertEqual(library.family("squat")?.exercise(at: 1).id, "chair_squat")
        XCTAssertEqual(library.family("balance")?.exercise(at: 3).eyesClosed, true)
        XCTAssertEqual(library.family("calf_raise")?.exercise(at: 3).id, "single_leg_calf_raise_free")
        XCTAssertEqual(library.family("floor")?.exercise(at: 2).id, "kneel_to_stand_free")
    }

    func testHarderVersionsAreFilteredLikeTheirBase() {
        let versions = ["chair_squat": "squat", "kneel_to_stand_free": "kneel_to_stand",
                        "single_leg_calf_raise_free": "single_leg_calf_raise", "single_leg_balance_eyes_closed": "single_leg_balance"]
        for limitation in Limitation.allCases {
            let unsafe = PlanBuilder.unsafe(for: [limitation])
            for (version, base) in versions where unsafe.contains(base) {
                XCTAssertTrue(unsafe.contains(version), "\(version) with \(limitation)")
            }
        }
        XCTAssertTrue(PlanBuilder.unsafe(for: [.dizziness]).contains("single_leg_balance_eyes_closed"))
        XCTAssertTrue(PlanBuilder.unsafe(for: [.knee]).contains("low_chair_stand"), "a low seat bends the knee further")
    }

    func testTwoForTwoMovesUpOneLevel() {
        var p = ExerciseProgress(id: "sit_to_stand", level: 1)
        p = Progression.record(log(10, 12, on: -2), to: p, levels: 4).0
        XCTAssertEqual(p.level, 1, "one good session isn't enough")
        let (next, change) = Progression.record(log(10, 12), to: p, levels: 4)
        XCTAssertEqual(next.level, 2)
        XCTAssertEqual(change, .up)
        XCTAssertTrue(next.lastSessions.isEmpty, "the new level starts fresh")
    }

    func testEasyTwiceCountsAsTwoInReserve() {
        var p = ExerciseProgress(id: "squat", level: 0)
        p = Progression.record(log(10, 10, on: -2), to: p, levels: 4).0
        p = Progression.rate(p, effort: .easy, levels: 4).0
        p = Progression.record(log(10, 10), to: p, levels: 4).0
        XCTAssertEqual(p.level, 0, "just finishing the target isn't a level up")
        let (next, change) = Progression.rate(p, effort: .easy, levels: 4)
        XCTAssertEqual(next.level, 1)
        XCTAssertEqual(change, .up)
        // Never beyond level D.
        let top = ExerciseProgress(id: "squat", level: 3, lastSessions: [log(10, 12, on: -1)])
        XCTAssertEqual(Progression.record(log(10, 12), to: top, levels: 4).0.level, 3)
    }

    func testMissingByThreeTwiceMovesDown() {
        var p = ExerciseProgress(id: "calf_raise", level: 2)
        p = Progression.record(log(10, 7, on: -2), to: p, levels: 4).0
        let (next, change) = Progression.record(log(10, 6), to: p, levels: 4)
        XCTAssertEqual(next.level, 1)
        XCTAssertEqual(change, .down)
        // Missing by 2 holds the level.
        var q = ExerciseProgress(id: "calf_raise", level: 2)
        q = Progression.record(log(10, 8, on: -2), to: q, levels: 4).0
        XCTAssertEqual(Progression.record(log(10, 8), to: q, levels: 4).0.level, 2)
    }

    func testHardTwiceHoldsTheLevelAndDropsASet() {
        var p = ExerciseProgress(id: "sit_to_stand", level: 1)
        p = Progression.rate(Progression.record(log(10, 10, on: -2), to: p, levels: 4).0, effort: .hard, levels: 4).0
        XCTAssertFalse(Progression.dropsASet(p))
        p = Progression.rate(Progression.record(log(10, 10), to: p, levels: 4).0, effort: .hard, levels: 4).0
        XCTAssertEqual(p.level, 1)
        XCTAssertTrue(Progression.dropsASet(p))

        let book = LevelBook(progress: ["sit_to_stand": p])
        let moves = [TrainingPlan.StrengthMove(exerciseID: "chair_stand", reps: 10, seconds: nil),
                     TrainingPlan.StrengthMove(exerciseID: "arm_raise", reps: nil, seconds: 30)]
        let items = TrainingPlan.sessionItems(sets: 3, moves: moves, levels: book)
        XCTAssertEqual(items.filter { $0.family == "sit_to_stand" }.count, 2, "one set fewer")
        XCTAssertEqual(items.filter { $0.exercise.id == "arm_raise" }.count, 3)
        XCTAssertEqual(items.compactMap(\.restBefore), [Progression.setRest, Progression.setRest], "a longer rest before sets 2 and 3")
    }

    func testSomethingHurtPlaysTheEasierLevelForAWeek() {
        var p = Progression.record(log(10, 10), to: ExerciseProgress(id: "floor", level: 2), levels: 4).0
        let (hurt, change) = Progression.rate(p, effort: nil, hurt: true, levels: 4)
        XCTAssertEqual(change, .easier)
        p = hurt
        XCTAssertEqual(p.level, 2, "the level itself is kept")
        XCTAssertEqual(Progression.level(p, on: day(3)), 1)
        XCTAssertEqual(Progression.level(p, on: day(7)), 2, "back after a week")
        let item = LevelBook(progress: ["floor": p], date: day(1)).item("kneel_to_stand")
        XCTAssertEqual(item?.exercise.id, "kneel_to_stand")
        XCTAssertEqual(item?.level, 1)
        XCTAssertEqual(item?.note, "We're keeping this one easier for a few days.")
    }

    func testAWeekAwayEasesBackOneLevel() {
        let p = Progression.record(log(10, 10, on: -20), to: ExerciseProgress(id: "balance", level: 2), levels: 4).0
        XCTAssertEqual(Progression.level(p, on: day(-13)), 2, "6 days off: nothing changes")
        XCTAssertEqual(Progression.level(p, on: day(0)), 1)
        XCTAssertEqual(LevelBook(progress: ["balance": p]).item("single_leg_balance")?.note, "Let's ease back in.")
        let (next, change) = Progression.record(log(10, 10), to: p, levels: 4)
        XCTAssertEqual(change, .easeBack)
        XCTAssertEqual(next.level, 1)
        XCTAssertEqual(Progression.level(next, on: day(0)), 1, "dropped once, not twice")
    }

    func testCoachSaysLastTimeNotTheWeek() {
        var p = ExerciseProgress(id: "sit_to_stand", level: 1)
        p = Progression.record(log(10, 9), to: p, levels: 4).0
        let item = LevelBook(progress: ["sit_to_stand": p]).item("chair_stand", reps: 10)
        XCTAssertEqual(item?.note, "You did 9 last time. Try 10 again.")
        p = Progression.rate(Progression.record(log(10, 10), to: ExerciseProgress(id: "sit_to_stand", level: 1), levels: 4).0,
                             effort: .easy, levels: 4).0
        XCTAssertEqual(LevelBook(progress: ["sit_to_stand": p]).item("chair_stand", reps: 10)?.note,
                       "You did 10 last time. Try 10 again. If it feels easy again, we go up.")
    }

    func testLevelsStartByPlanAndSkipWhatsUnsafe() {
        let fresh = LevelBook()
        XCTAssertEqual(fresh.item("chair_stand", reps: 10)?.exercise.id, "chair_stand", "most people start at level B")
        XCTAssertEqual(LevelBook(gentle: true).item("chair_stand", reps: 10)?.exercise.id, "chair_stand_hands", "gentle starts at A")
        // Level D of sit to stand is the floor rise. Knees cap it at an ordinary chair: the low seat
        // bends the knee further.
        let top = ["sit_to_stand": ExerciseProgress(id: "sit_to_stand", level: 3)]
        XCTAssertEqual(LevelBook(progress: top).item("chair_stand")?.exercise.id, "sit_rise")
        XCTAssertEqual(LevelBook(progress: top, limitations: [.knee]).item("chair_stand")?.exercise.name, "Chair Stand")
        // Eyes closed is out with dizziness.
        let balance = ["balance": ExerciseProgress(id: "balance", level: 3)]
        XCTAssertEqual(LevelBook(progress: balance, limitations: [.dizziness]).item("single_leg_balance")?.level, 2)
        // A level's own amount wins; otherwise the plan's amount when the kind matches.
        let squat = LevelBook(gentle: true).item("squat", reps: 10)
        XCTAssertEqual(squat?.exercise.id, "wall_sit")
        XCTAssertEqual(squat?.seconds, 20)
        XCTAssertNil(squat?.reps)
        // Every family ruled out entirely: no item.
        XCTAssertNil(LevelBook(limitations: [.knee]).item("kneel_to_stand"))
        XCTAssertEqual(LevelBook().item("march", seconds: 45)?.seconds, 45, "exercises outside a family pass through")
    }

    func testDailySessionPlaysLevelsAndStaysSafe() {
        let profile = Profile(name: "", age: 72, limitations: [.knee])
        let levels = LevelBook(limitations: profile.limitations, gentle: true)
        for offset in 0..<14 {
            let plan = PlanBuilder.today(profile: profile, latest: nil, date: day(offset), levels: levels)
            let unsafe = PlanBuilder.unsafe(for: profile.limitations)
            XCTAssertTrue(plan.allSatisfy { !unsafe.contains($0.exercise.id) })
            XCTAssertEqual(Set(plan.map(\.exercise.id)).count, plan.count, "no exercise twice")
            XCTAssertFalse(plan.contains { $0.exercise.id == "chair_stand" }, "gentle plans play level A (with hands)")
        }
    }

    func testProgressAndRatingsPersistPerFamilyMember() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("floorage.json")
        let model = AppModel(fileURL: url)
        model.profile = Profile(name: "Priya", age: 52, limitations: [])
        let result = FamilyResult(family: "sit_to_stand", level: 1, target: 10, done: 10)
        model.logSession([result], on: day(-2))
        model.rateSession(.easy, families: ["sit_to_stand"], on: day(-2))
        model.logSession([result], on: day(0))
        let changes = model.rateSession(.easy, families: ["sit_to_stand"], on: day(0))
        XCTAssertEqual(changes["sit_to_stand"], .up)
        XCTAssertEqual(AppModel(fileURL: url).progress(for: "sit_to_stand")?.level, 2)

        model.addMember()
        model.profile = Profile(name: "Raj", age: 78, limitations: [])
        XCTAssertNil(model.progress(for: "sit_to_stand"), "each member has their own levels")
        model.switchMember(model.owner.id)
        XCTAssertEqual(model.progress(for: "sit_to_stand")?.level, 2)
    }
}

final class PlanEmphasisTests: XCTestCase {
    private func profile(age: Int = 35, limits: Set<Limitation> = []) -> Profile {
        Profile(name: "", age: age, limitations: limits, gender: .female, heightCm: 165, weightKg: 58)
    }

    /// Reach weakest (moves like 72), then chair stand (62).
    private func result(reach: Double = 1, chair: Double = 15) -> FloorAgeResult {
        FloorAgeResult(age: 45, scores: ["sitRise": 9, "balance": 40, "chairStand": chair, "reach": reach])
    }

    private func days(_ week: TrainingPlan.Week, containing match: (TrainingPlan.Activity) -> Bool) -> [Int] {
        week.days.filter { $0.activities.contains(where: match) }.map(\.index)
    }

    func testEmphasisIsTheWeakestAreaAndMovesOnWhenItDidntImprove() {
        XCTAssertNil(TrainingPlan.emphasis(from: []))
        XCTAssertEqual(TrainingPlan.emphasis(from: [result()]), TrainingPlan.Emphasis(area: .reach))
        XCTAssertEqual(TrainingPlan.emphasis(from: [result(), result()]), TrainingPlan.Emphasis(area: .chairStand, unchanged: .reach))
        XCTAssertEqual(TrainingPlan.emphasis(from: [result(reach: 1), result(reach: 1.5)]), TrainingPlan.Emphasis(area: .reach),
                       "improved, still the weakest: keep going")
        XCTAssertEqual(TrainingPlan.emphasis(from: [result(reach: 1), result(reach: 3)]), TrainingPlan.Emphasis(area: .chairStand))
    }

    func testFocusShapesTheWeek() {
        let p = profile()
        func week(_ focus: FloorTest?, _ number: Int = 3, _ program: TrainingPlan.Program = .runWalk) -> TrainingPlan.Week {
            TrainingPlan.week(number, program: program, profile: p, averageSteps: 5000, focus: focus, scale: .international)
        }
        let isStrength = { (a: TrainingPlan.Activity) in if case .strength = a { true } else { false } }
        let isBalance = { (a: TrainingPlan.Activity) in if case .balance = a { true } else { false } }
        XCTAssertEqual(days(week(nil), containing: isStrength), [1, 5])
        XCTAssertEqual(days(week(.chairStand), containing: isStrength), [1, 3, 5], "Otago: strength 3 times a week")
        XCTAssertEqual(days(week(.chairStand, 3, .briskWalk), containing: isStrength), [0, 3, 5])
        XCTAssertEqual(days(week(.balance), containing: isBalance), [1, 3, 5], "balance block 3 times a week at any age")
        XCTAssertTrue(days(week(nil), containing: isBalance).isEmpty)
        XCTAssertEqual(days(week(.sitRise), containing: { if case .mobility(.floor, _, _) = $0 { true } else { false } }), [1, 3, 5])
        XCTAssertEqual(days(week(.reach), containing: { if case .mobility(.flexibility, _, _) = $0 { true } else { false } }), [0, 1, 3, 5])
        // The other areas keep one session a week, without the focus area's own move.
        let own: [FloorTest: String] = [.sitRise: "kneel_to_stand", .balance: "single_leg_balance", .reach: "toe_reach"]
        for focus in FloorTest.allCases {
            let allRound = week(focus).days.flatMap(\.activities).compactMap { a -> [String]? in
                if case .mobility(.allRound, _, let moves) = a { moves.map(\.exerciseID) } else { nil }
            }
            XCTAssertEqual(allRound.count, 1, "\(focus)")
            if let mine = own[focus] { XCTAssertFalse(allRound.first?.contains(mine) ?? true, "\(focus)") }
        }
        XCTAssertEqual(week(nil).days[6].activities, [.rest], "rest day kept")
    }

    func testCheckWeekIsLighterWithAFloorAgeCheck() {
        let p = profile()
        let w3 = TrainingPlan.week(3, program: .runWalk, profile: p, averageSteps: 5000, focus: .chairStand, scale: .international)
        let w4 = TrainingPlan.week(4, program: .runWalk, profile: p, averageSteps: 5000, focus: .chairStand, scale: .international)
        let w8 = TrainingPlan.week(8, program: .runWalk, profile: p, averageSteps: 5000, scale: .international)
        XCTAssertFalse(w3.isCheckWeek)
        XCTAssertTrue(w4.isCheckWeek)
        XCTAssertEqual(w3.sets, 2)
        XCTAssertEqual(w4.sets, 1, "deload: one set fewer")
        XCTAssertEqual(w8.sets, 2)
        XCTAssertEqual(w4.days[6].activities, [.check])
        XCTAssertEqual(days(w4, containing: { if case .strength = $0 { true } else { false } }).count, 2, "two lighter sessions")
        XCTAssertEqual(TrainingPlan.headline(w4.days[6]), "Floor Age check")
        XCTAssertTrue(TrainingPlan.week(13, program: .runWalk, profile: p, averageSteps: nil).days[6].activities.contains(.rest),
                      "past the end the final week repeats, and week 13 isn't a check week")
    }

    func testGentlePlansCapSetsAtTwo() {
        let p = profile(age: 45)
        XCTAssertFalse(TrainingPlan.isGentle(p, latest: nil))
        let older = FloorAgeResult(age: 45, scores: ["sitRise": 4, "balance": 6, "chairStand": 10, "reach": 0])
        XCTAssertGreaterThanOrEqual(older.floorAge - older.age, 15)
        XCTAssertTrue(TrainingPlan.isGentle(p, latest: older))
        XCTAssertTrue(TrainingPlan.isGentle(profile(age: 71), latest: nil))
        XCTAssertEqual(TrainingPlan.week(6, program: .runWalk, profile: p, averageSteps: nil, gentle: true).sets, 2)
        XCTAssertEqual(TrainingPlan.week(6, program: .runWalk, profile: p, averageSteps: nil).sets, 3)
    }

    func testDailyHabitComesFromTheFocusArea() {
        let cal = Calendar.current
        for offset in 0..<8 {
            let date = cal.date(byAdding: .day, value: offset, to: Date())!
            XCTAssertTrue(DailyHabit.all(for: .balance).contains(DailyHabit.today(area: .balance, on: date)))
            XCTAssertEqual(DailyHabit.today(area: nil, on: date), DailyHabit.today(area: .balance, on: date), "balance before any check")
        }
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date())!
        XCTAssertNotEqual(DailyHabit.today(area: .chairStand), DailyHabit.today(area: .chairStand, on: tomorrow), "a new one each day")
    }

    func testWeeklyDoseCountsEachDayOnce() {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let week = DateInterval(start: start, duration: 7 * 86400)
        func at(_ day: Int) -> Date { cal.date(byAdding: .hour, value: 10, to: cal.date(byAdding: .day, value: day, to: start)!)! }
        let strength = TrainingPlan.Activity.strength(sets: 2, moves: [.init(exerciseID: "squat", reps: 10, seconds: nil)])
        let walk = TrainingPlan.Activity.cardio(.briskWalk, TrainingPlan.walk(briskMinutes: 30))
        let dose = WeeklyDose.compute(
            week: week,
            records: [ActivityRecord(date: at(0), minutes: 12, kinds: [.strength, .balance]),
                      ActivityRecord(date: at(1), minutes: 30, kinds: [.move]),
                      ActivityRecord(date: at(9), minutes: 99, kinds: [.move])],
            planDays: [(at(1), [walk, strength]), (at(2), [walk])],
            habitDays: [(at(0), .balance), (at(3), .balance), (at(4), nil)],
            moveTarget: 150, balanceTarget: 3)
        XCTAssertEqual(dose.moveMinutes, 60, "day 1's walk was logged; day 2's ticked-off walk adds its 30 min; next week's doesn't count")
        XCTAssertEqual(dose.strengthDays, 2)
        XCTAssertEqual(dose.strengthMinutes, 12 + strength.minutes)
        XCTAssertEqual(dose.balanceDays, 2, "a session and a habit on the same day count once")
    }
}
