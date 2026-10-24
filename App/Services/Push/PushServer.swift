import Foundation

/// The push gateway that relays Matrix pushes to APNs. It stores this
/// installation's APNs token and notification preferences. Its address and
/// secret come from the bundled `PushConfiguration.private.json`.
nonisolated struct PushServer {
    private let serverURL: URL
    private let registrationSecret: String
    /// Identifies this installation to the push server across launches.
    private let installationID: String

    init() throws {
        guard let url = Bundle.main.url(forResource: "PushConfiguration.private", withExtension: "json") else {
            throw PushError.notConfigured
        }
        let configuration = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url))
        guard configuration.serverURL.scheme == "https",
              configuration.serverURL.host != nil,
              configuration.serverURL.user == nil,
              configuration.serverURL.query == nil,
              configuration.serverURL.fragment == nil,
              configuration.registrationSecret.count >= 32 else { throw PushError.notConfigured }
        serverURL = configuration.serverURL
        registrationSecret = configuration.registrationSecret

        let key = "push.installationID"
        installationID = UserDefaults.standard.string(forKey: key) ?? UUID().uuidString
        UserDefaults.standard.set(installationID, forKey: key)
    }

    /// Where the homeserver sends this device's pushes.
    var gatewayURL: URL { serverURL.appending(path: "_matrix/push/v1/notify") }

    /// Stores the APNs token and returns the pusher to add on the homeserver.
    func register(token: String) async throws -> PushRegistration {
        let data = try await send("PUT", body: JSONEncoder().encode(["token": token]))
        let registration = try JSONDecoder().decode(PushRegistration.self, from: data)
        guard registration.pushkey.count == 64,
              registration.pushkey.allSatisfy(\.isHexDigit),
              registration.appID == Bundle.main.bundleIdentifier else { throw PushError.invalidRegistration }
        return registration
    }

    func uploadPreferences(_ preferences: Data) async throws {
        _ = try await send("PUT", body: preferences, path: "notification-preferences")
    }

    /// Deletes this installation by ID, which also covers an enrollment
    /// interrupted before its pushkey was saved.
    func unregister() async throws {
        _ = try await send("DELETE")
    }

    private func send(_ method: String, body: Data? = nil, path: String? = nil) async throws -> Data {
        var request = URLRequest(url: serverURL.appending(path: path ?? "devices/\(installationID)"), timeoutInterval: 20)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(registrationSecret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw PushError.registrationFailed
        }
        return data
    }

    private nonisolated struct Configuration: Decodable {
        let serverURL: URL
        let registrationSecret: String
    }
}

/// The push server's name for this installation's pusher.
nonisolated struct PushRegistration: Codable {
    let pushkey: String
    let appID: String

    enum CodingKeys: String, CodingKey {
        case pushkey
        case appID = "app_id"
    }
}

nonisolated enum PushError: LocalizedError {
    case notConfigured
    case registrationFailed
    case invalidRegistration

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Notifications aren’t configured for this build."
        case .registrationFailed: "Couldn’t connect notifications. Try again when you’re online."
        case .invalidRegistration: "The notification server returned an invalid registration."
        }
    }
}
