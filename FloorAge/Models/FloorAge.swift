import Foundation

/// The four at-home tests that make up a Floor Age check.
enum FloorTest: String, Codable, CaseIterable, Identifiable {
    case sitRise
    case balance
    case chairStand
    case reach

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sitRise: String(localized: "Sit to Rise")
        case .balance: String(localized: "One-Leg Balance")
        case .chairStand: String(localized: "30-Second Chair Stand")
        case .reach: String(localized: "Toe Reach")
        }
    }

    var area: String {
        switch self {
        case .sitRise: String(localized: "Getting up from the floor")
        case .balance: String(localized: "Balance")
        case .chairStand: String(localized: "Leg strength")
        case .reach: String(localized: "Flexibility")
        }
    }

    var symbol: String {
        switch self {
        case .sitRise: "figure.cross.training"
        case .balance: "figure.stand"
        case .chairStand: "chair.lounge"
        case .reach: "figure.flexibility"
        }
    }

    /// Exercise the coach avatar demonstrates for this test.
    var exerciseID: String {
        switch self {
        case .sitRise: "sit_rise"
        case .balance: "single_leg_balance"
        case .chairStand: "chair_stand"
        case .reach: "toe_reach"
        }
    }

    var instructions: String {
        switch self {
        case .sitRise:
            String(localized: "Stand on a mat. Cross your legs and sit down on the floor, then stand back up. Try not to use your hands, knees or forearms. Afterwards, tell me how many times you needed support.")
        case .balance:
            String(localized: "Stand near a wall. Lift one foot and balance for as long as you can, up to 45 seconds. Tap Stop the moment your foot touches down or you grab the wall.")
        case .chairStand:
            String(localized: "Sit in the middle of a sturdy chair, arms crossed on your chest. When I say go, stand up fully and sit down as many times as you can in 30 seconds. Count out loud.")
        case .reach:
            String(localized: "Stand with your feet together and knees straight but not locked. Slowly fold forward and reach down. Don't bounce. Pick how far you reached.")
        }
    }

    /// Relative weight in the combined Floor Age.
    var weight: Double {
        switch self {
        case .sitRise: 0.35
        case .balance: 0.25
        case .chairStand: 0.25
        case .reach: 0.15
        }
    }

    /// Typical score by age, best score first. Scores are mapped to an "equivalent age" by
    /// interpolating along this curve.
    ///
    /// Approximations drawn from published reference values:
    /// - Sit to rise (0–10): Araújo et al., sitting-rising test reference data.
    /// - One-leg balance, eyes open, seconds (max 45): Springer et al. 2007.
    /// - 30-second chair stand: Rikli & Jones senior fitness norms (60+), extended to younger
    ///   adults with young-adult study means.
    /// - Toe reach level (0–5): coarse flexibility bands.
    /// These give a fitness *estimate*, not a medical measurement, and should be refined with
    /// real user data over time.
    var norms: [(age: Double, score: Double)] {
        switch self {
        case .sitRise: [(20, 10), (30, 9.5), (40, 9), (50, 8), (60, 7), (70, 5.5), (80, 4), (90, 2.5)]
        case .balance: [(25, 45), (45, 40), (55, 37), (65, 27), (75, 15), (85, 6)]
        case .chairStand: [(25, 24), (35, 22), (45, 19), (55, 17), (62, 15), (67, 14), (72, 13), (77, 12.5), (82, 11.5), (87, 10)]
        case .reach: [(20, 5), (30, 4), (45, 3), (60, 2), (72, 1), (85, 0)]
        }
    }

    func equivalentAge(for score: Double) -> Double {
        let n = norms
        guard let first = n.first, let last = n.last else { return 50 }
        if score >= first.score { return first.age }
        if score <= last.score { return last.age }
        for (a, b) in zip(n, n.dropFirst()) where score <= a.score && score >= b.score {
            let u = (a.score - score) / max(a.score - b.score, 0.0001)
            return a.age + u * (b.age - a.age)
        }
        return last.age
    }
}

/// Toe reach answer levels, best first.
enum ReachLevel: Int, CaseIterable, Identifiable {
    case palmsFlat = 5, fingersToFloor = 4, toes = 3, ankles = 2, shins = 1, knees = 0

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .palmsFlat: String(localized: "Palms flat on the floor")
        case .fingersToFloor: String(localized: "Fingertips touch the floor")
        case .toes: String(localized: "Touch my toes")
        case .ankles: String(localized: "Reach my ankles")
        case .shins: String(localized: "Reach my shins")
        case .knees: String(localized: "Only to my knees")
        }
    }
}

struct FloorAgeResult: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var age: Int
    /// Raw score per test (`FloorTest.rawValue`). Skipped tests are absent.
    var scores: [String: Double]

    var floorAge: Int {
        Int(FloorAgeCalculator.floorAge(scores: scores).rounded())
    }

    func equivalentAge(_ test: FloorTest) -> Double? {
        scores[test.rawValue].map(test.equivalentAge(for:))
    }

    /// The test whose equivalent age is furthest above the person's real age.
    var weakest: FloorTest? {
        FloorTest.allCases
            .compactMap { test in equivalentAge(test).map { (test, $0) } }
            .max { $0.1 < $1.1 }?.0
    }

    var rankedWeakest: [FloorTest] {
        FloorTest.allCases
            .compactMap { test in equivalentAge(test).map { (test, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }
}

enum FloorAgeCalculator {
    static func floorAge(scores: [String: Double]) -> Double {
        var total = 0.0
        var weights = 0.0
        for test in FloorTest.allCases {
            guard let score = scores[test.rawValue] else { continue }
            total += test.equivalentAge(for: score) * test.weight
            weights += test.weight
        }
        return weights > 0 ? total / weights : 0
    }

    /// Sit-to-rise score: start at 10, minus one per support used, minus half for a wobble.
    static func sitRiseScore(downSupports: Int, upSupports: Int, unsteady: Bool) -> Double {
        max(0, 10 - Double(downSupports + upSupports) - (unsteady ? 0.5 : 0))
    }
}
