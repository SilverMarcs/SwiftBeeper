import Foundation

struct ManageState: Decodable {
    let clientState: ClientState?

    enum CodingKeys: String, CodingKey {
        case clientState = "client_state"
    }
}


extension APIClient {
    static func manageState() async throws -> ManageState {
        try await execute("state", arguments: EmptyArguments())
    }

    static func beeperStartLogin(domain: String) async throws -> String {
        struct Body: Encodable { let domain: String }
        struct Response: Decodable { let request: String? }
        let resp: Response = try await execute("beeper-start-login", arguments: Body(domain: domain))
        guard let request = resp.request, !request.isEmpty else {
            throw APIError.decoding("Beeper did not return a request id")
        }
        return request
    }

    static func beeperRequestCode(domain: String, request: String, email: String) async throws {
        struct Body: Encodable { let domain: String; let request: String; let email: String }
        try await executeRaw("beeper-request-code", arguments: Body(domain: domain, request: request, email: email))
    }

    static func beeperSubmitCode(domain: String, request: String, code: String) async throws -> String {
        struct Body: Encodable { let domain: String; let request: String; let response: String }
        struct Response: Decodable { let token: String? }
        let resp: Response = try await execute("beeper-submit-code", arguments: Body(domain: domain, request: request, response: code))
        guard let token = resp.token, !token.isEmpty else {
            throw APIError.decoding("Beeper did not return a JWT")
        }
        return token
    }

    static func loginCustomJWT(homeserverURL: String, jwt: String) async throws -> ManageState {
        struct Inner: Encodable { let type: String; let token: String }
        struct Body: Encodable { let homeserverURL: String; let request: Inner }
        return try await execute("login-custom", arguments: Body(
            homeserverURL: homeserverURL,
            request: Inner(type: "org.matrix.login.jwt", token: jwt)
        ))
    }

    static func verifyRecoveryKey(_ recoveryKey: String) async throws -> ManageState {
        struct Body: Encodable { let recoveryKey: String }
        return try await execute("verify", arguments: Body(recoveryKey: recoveryKey))
    }
}
