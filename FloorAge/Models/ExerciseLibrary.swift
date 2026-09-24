import Foundation

/// Decoded form of `Resources/exercises.json`: the avatar skeleton, named poses and every exercise.
/// Poses are authored and previewed with `tools/pose_preview.py`, which shares this format.
struct ExerciseLibrary: Decodable {
    let version: Int
    let rig: Rig
    let poses: [String: [String: [Double]]]
    private(set) var exercises: [Exercise]
    /// Exercises that progress through levels A–D (see `Progression`).
    private(set) var families: [ExerciseFamily]

    static let shared: ExerciseLibrary = {
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json") else {
            fatalError("exercises.json missing from the app bundle")
        }
        do {
            var library = try JSONDecoder().decode(ExerciseLibrary.self, from: Data(contentsOf: url))
            library.exercises = library.exercises.map { $0.localized() }
            library.families = library.families.map { $0.localized() }
            return library
        } catch {
            fatalError("exercises.json is invalid: \(error)")
        }
    }()

    func exercise(_ id: String) -> Exercise? {
        exercises.first { $0.id == id }
    }

    /// The family whose plans name this exercise ("chair_stand" stands for the sit-to-stand levels).
    func family(anchoredAt exerciseID: String) -> ExerciseFamily? {
        families.first { $0.anchor == exerciseID }
    }

    func family(_ id: String) -> ExerciseFamily? {
        families.first { $0.id == id }
    }

    subscript(id: String) -> Exercise {
        guard let exercise = exercise(id) else { fatalError("Unknown exercise \(id)") }
        return exercise
    }
}

struct Rig: Decodable {
    let joints: [RigJoint]
    let contacts: [String: RigContact]
}

struct RigJoint: Decodable {
    let name: String
    let parent: String?
    let offset: [Float]
}

struct RigContact: Decodable {
    let joint: String
    let offset: [Float]
}

struct Exercise: Decodable, Identifiable, Hashable {
    enum Kind: String, Decodable {
        /// Counted repetitions; one rep each time the animation passes `repTime`.
        case reps
        /// Keep moving for a number of seconds.
        case timed
        /// Get into position and hold for a number of seconds.
        case hold
    }

    let id: String
    let name: String
    let kind: Kind
    let defaultReps: Int?
    let defaultSeconds: Int?
    let repTime: Double?
    let mirrorHalfway: Bool?
    let focus: [String]
    let intro: String
    let cues: [String]
    let safety: String?
    let props: [Prop]?
    let keyframes: [Keyframe]
    /// The camera angle (degrees the coach is turned) that shows this move best, e.g. side-on for
    /// the toe reach. The view eases there when the exercise starts.
    let cameraYaw: Double?

    static func == (lhs: Exercise, rhs: Exercise) -> Bool { lhs.id == rhs.id }

    /// Name, instructions, cues and safety note in the person's language, from the "Exercises"
    /// string table (keys like "squat.intro", "squat.cue.0"); English from exercises.json otherwise.
    func localized(bundle: Bundle = .main) -> Exercise {
        func text(_ key: String, _ english: String) -> String {
            bundle.localizedString(forKey: "\(id).\(key)", value: english, table: "Exercises")
        }
        return Exercise(id: id, name: text("name", name), kind: kind, defaultReps: defaultReps, defaultSeconds: defaultSeconds,
                        repTime: repTime, mirrorHalfway: mirrorHalfway, focus: focus, intro: text("intro", intro),
                        cues: cues.enumerated().map { text("cue.\($0.offset)", $0.element) },
                        safety: safety.map { text("safety", $0) }, props: props,
                        keyframes: keyframes.map { $0.localized(exercise: id, bundle: bundle) }, cameraYaw: cameraYaw)
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// The same movement under a level's own name and instructions ("Low Chair Stand").
    func variant(name: String?, intro: String?) -> Exercise {
        guard name != nil || intro != nil else { return self }
        return Exercise(id: id, name: name ?? self.name, kind: kind, defaultReps: defaultReps, defaultSeconds: defaultSeconds,
                        repTime: repTime, mirrorHalfway: mirrorHalfway, focus: focus, intro: intro ?? self.intro,
                        cues: cues, safety: safety, props: props, keyframes: keyframes, cameraYaw: cameraYaw)
    }
}

/// One exercise at four levels, easiest first, following the Otago programme's progressions
/// (Campbell & Robertson, Otago Exercise Programme manual): e.g. a chair stand with hands, then
/// arms crossed, then a low chair, then rising from the floor. Plans name the family by its
/// `anchor` exercise and the coach plays the person's current level.
struct ExerciseFamily: Decodable, Identifiable {
    struct Level: Decodable {
        /// The animation the coach plays.
        let exercise: String
        /// Name and instructions when they differ from the exercise's own.
        let name: String?
        let intro: String?
        /// Fixed amount for this level; otherwise the plan's amount.
        let reps: Int?
        let seconds: Int?
        /// Limitations that rule this level out.
        let avoid: [Limitation]?
    }

    let id: String
    let anchor: String
    /// The level most people start at (0 = A). Gentle plans start at A.
    let start: Int
    let levels: [Level]

    /// Level names and instructions from the "Exercises" table (keys like "squat.level.1.name").
    func localized(bundle: Bundle = .main) -> ExerciseFamily {
        func text(_ key: String, _ english: String?) -> String? {
            english.map { bundle.localizedString(forKey: "\(id).\(key)", value: $0, table: "Exercises") }
        }
        return ExerciseFamily(id: id, anchor: anchor, start: start, levels: levels.enumerated().map { index, level in
            Level(exercise: level.exercise, name: text("level.\(index).name", level.name),
                  intro: text("level.\(index).intro", level.intro), reps: level.reps, seconds: level.seconds, avoid: level.avoid)
        })
    }

    /// The level's exercise under its own name.
    func exercise(at level: Int) -> Exercise {
        let entry = levels[min(max(level, 0), levels.count - 1)]
        return ExerciseLibrary.shared[entry.exercise].variant(name: entry.name, intro: entry.intro)
    }
}

struct Keyframe: Decodable {
    enum Ground: String, Decodable {
        case feet, left, right, seat, lowest
    }

    let t: Double
    let pose: String?
    let joints: [String: [Double]]?
    let ground: Ground?
    let seatZ: Float?
    let rootZ: Float?
    /// Said and shown when the animation reaches this keyframe, e.g. "Squeeze and lift".
    let cue: String?

    /// The cue in the person's language (key "kegel.Squeeze and lift" in the "Exercises" table).
    func localized(exercise: String, bundle: Bundle) -> Keyframe {
        guard let cue else { return self }
        return Keyframe(t: t, pose: pose, joints: joints, ground: ground, seatZ: seatZ, rootZ: rootZ,
                        cue: bundle.localizedString(forKey: "\(exercise).\(cue)", value: cue, table: "Exercises"))
    }
}

struct Prop: Decodable, Hashable {
    let type: String
    let position: [Float]
}
