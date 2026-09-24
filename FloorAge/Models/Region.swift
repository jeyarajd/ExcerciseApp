import Foundation

/// Defaults that depend on where the person lives, from the phone's region and measurement
/// settings. Each one can be changed in the app; these only pick the starting point.
enum Region {
    static var code: String { Locale.current.region?.identifier ?? "US" }

    static let southAsia: Set<String> = ["IN", "PK", "BD", "LK", "NP", "BT", "MV", "AF"]
    /// Where the lower Asian BMI cut-offs are recommended (WHO expert consultation, Lancet 2004).
    static let asia: Set<String> = southAsia.union([
        "CN", "HK", "MO", "TW", "JP", "KR", "SG", "MY", "TH", "VN", "PH", "ID", "MM", "KH", "LA", "MN", "BN",
    ])

    static var isSouthAsia: Bool { southAsia.contains(code) }

    static var defaultBMIScale: BMIScale { asia.contains(code) ? .asian : .international }

    /// Pounds for body weight where people usually weigh themselves in pounds (or stones).
    static var usesPounds: Bool { ["US", "GB", "LR", "MM"].contains(code) }

    /// The on-device English voice closest to the local accent.
    static var defaultAccent: String {
        switch code {
        case _ where southAsia.contains(code): "en-IN"
        case "GB", "IE": "en-GB"
        case "AU", "NZ": "en-AU"
        default: "en-US"
        }
    }

    static var greeting: String { isSouthAsia ? "Namaste!" : "Hello!" }

    /// Indian foods first in South Asia, international foods first elsewhere.
    static var prefersIndianFood: Bool { isSouthAsia }
}
