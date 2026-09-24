import Foundation

/// Decoded form of `Resources/exercises.json`: the avatar skeleton, named poses and every exercise.
/// Poses are authored and previewed with `tools/pose_preview.py`, which shares this format.
struct ExerciseLibrary: Decodable {
    let version: Int
    let rig: Rig
    let poses: [String: [String: [Double]]]
    let exercises: [Exercise]

    static let shared: ExerciseLibrary = {
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json") else {
            fatalError("exercises.json missing from the app bundle")
        }
        do {
            return try JSONDecoder().decode(ExerciseLibrary.self, from: Data(contentsOf: url))
        } catch {
            fatalError("exercises.json is invalid: \(error)")
        }
    }()

    func exercise(_ id: String) -> Exercise? {
        exercises.first { $0.id == id }
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

    static func == (lhs: Exercise, rhs: Exercise) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
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
}

struct Prop: Decodable, Hashable {
    let type: String
    let position: [Float]
}
