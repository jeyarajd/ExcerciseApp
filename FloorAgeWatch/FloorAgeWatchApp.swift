import SwiftUI

/// Floor Age on Apple Watch: your Floor Age and week at a glance, the chair stand and balance
/// tests on your wrist (results go to the iPhone's Floor Age check), and a remote for guided
/// sessions playing on the iPhone.
@main
struct FloorAgeWatchApp: App {
    @StateObject private var link = PhoneLink()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HomeView()
            }
            .environmentObject(link)
            .onAppear { link.activate() }
        }
    }
}

/// The Watch's colours, matching the iPhone app's.
enum WatchColors {
    static let floorAge = LinearGradient(colors: [Color(red: 0.98, green: 0.6, blue: 0.1), Color(red: 0.86, green: 0.28, blue: 0.2)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
    static let balance = LinearGradient(colors: [Color(red: 0.58, green: 0.4, blue: 0.98), Color(red: 0.35, green: 0.24, blue: 0.84)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let chair = LinearGradient(colors: [Color(red: 0.14, green: 0.74, blue: 0.9), Color(red: 0.24, green: 0.36, blue: 0.9)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
    static let steps = LinearGradient(colors: [Color(red: 1.0, green: 0.62, blue: 0.24), Color(red: 1.0, green: 0.36, blue: 0.38)],
                                      startPoint: .leading, endPoint: .trailing)
    static let accent = Color(red: 0.98, green: 0.52, blue: 0.16)
}
