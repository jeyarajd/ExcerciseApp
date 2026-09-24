import Foundation

/// What the iPhone and the Apple Watch send each other (WatchConnectivity dictionaries carry
/// these as JSON data under `WatchKey`).
enum WatchKey {
    static let snapshot = "snapshot"
    static let session = "session"
    static let command = "command"
    static let result = "result"
}

/// The guided session now playing on the iPhone, for the Watch remote.
struct SessionStatus: Codable, Equatable {
    var exercise: String
    /// "6 of 10" or "0:25 left".
    var detail: String
    var progress: Double
    /// "Exercise 2 of 5".
    var step: String
    var isPaused: Bool
    var isResting: Bool
    var isDone: Bool
}

/// Buttons on the Watch remote.
enum WatchCommand: String, Codable {
    case pause, skip
}

/// A Floor Age test done on the Watch: chair stands counted, or seconds balanced.
struct WatchTestResult: Codable, Equatable {
    enum Test: String, Codable { case chairStand, balance }
    var test: Test
    var value: Double
    var date = Date()
}

extension Encodable {
    var watchData: Data? { try? JSONEncoder().encode(self) }
}

extension Decodable {
    static func fromWatch(_ value: Any?) -> Self? {
        (value as? Data).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }
}
