import Foundation

/// Talks to the Floor Age coach server (see `server/`), which holds the Claude API key.
/// Only the conversation and a small context summary are sent — never the person's name.
struct CoachClient {
    struct Message: Codable, Identifiable, Equatable {
        enum Role: String, Codable { case user, assistant }
        var id = UUID()
        let role: Role
        let content: String

        private enum CodingKeys: String, CodingKey { case role, content }
    }

    struct Context: Encodable {
        let age: Int?
        let floorAge: Int?
        let weakestArea: String?
        let limitations: [String]
        let sessionsThisWeek: Int
    }

    enum CoachError: LocalizedError {
        case notConfigured
        case server(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: "The coach server isn't set up yet. Add its address in Settings."
            case .server(let message): message
            }
        }
    }

    static var serverURL: String {
        get {
            UserDefaults.standard.string(forKey: "coachServerURL")
                ?? (Bundle.main.object(forInfoDictionaryKey: "CoachServerURL") as? String)
                ?? ""
        }
        set { UserDefaults.standard.set(newValue, forKey: "coachServerURL") }
    }

    static var appToken: String {
        get { UserDefaults.standard.string(forKey: "coachAppToken") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "coachAppToken") }
    }

    static var isConfigured: Bool {
        URL(string: serverURL.trimmingCharacters(in: .whitespaces))?.host != nil
    }

    func reply(to messages: [Message], context: Context) async throws -> String {
        let base = Self.serverURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: base)?.appendingPathComponent("coach"), URL(string: base)?.host != nil else {
            throw CoachError.notConfigured
        }
        struct Body: Encodable {
            let messages: [Message]
            let context: Context
        }
        struct Reply: Decodable {
            let reply: String?
            let error: String?
        }

        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !Self.appToken.isEmpty {
            request.setValue(Self.appToken, forHTTPHeaderField: "X-App-Token")
        }
        request.httpBody = try JSONEncoder().encode(Body(messages: messages, context: context))

        let (data, response) = try await URLSession.shared.data(for: request)
        let decoded = try? JSONDecoder().decode(Reply.self, from: data)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, let text = decoded?.reply else {
            throw CoachError.server(decoded?.error ?? "The coach is unavailable right now. Please try again.")
        }
        return text
    }
}
