import Foundation

nonisolated struct PushConfiguration: Decodable {
    let serverURL: URL
    let registrationSecret: String

    static func load() throws -> Self {
        guard let url = Bundle.main.url(forResource: "PushConfiguration.private", withExtension: "json") else {
            throw PushError.notConfigured
        }
        let configuration = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard configuration.serverURL.scheme == "https",
              configuration.serverURL.host != nil,
              configuration.serverURL.user == nil,
              configuration.serverURL.query == nil,
              configuration.serverURL.fragment == nil,
              configuration.registrationSecret.count >= 32 else { throw PushError.notConfigured }
        return configuration
    }
}
