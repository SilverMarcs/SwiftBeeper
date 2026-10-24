import Foundation

/// Sign-in, verification and the signed-in account.
extension APIClient {
    static func manageState() async throws -> ManageState {
        try await execute("state", arguments: EmptyArguments())
    }

    static func getSession() async throws -> SessionOutput {
        try await execute("session", arguments: EmptyArguments())
    }

    static func beeperStartLogin(domain: String) async throws -> String {
        struct Arguments: Encodable { let domain: String }
        struct Response: Decodable { let request: String? }
        let response: Response = try await execute("beeper-start-login", arguments: Arguments(domain: domain))
        guard let request = response.request, !request.isEmpty else {
            throw MatrixError.decoding("Beeper did not return a request id")
        }
        return request
    }

    static func beeperRequestCode(domain: String, request: String, email: String) async throws {
        struct Arguments: Encodable { let domain: String; let request: String; let email: String }
        try await executeRaw("beeper-request-code", arguments: Arguments(domain: domain, request: request, email: email))
    }

    static func beeperSubmitCode(domain: String, request: String, code: String) async throws -> String {
        struct Arguments: Encodable { let domain: String; let request: String; let response: String }
        struct Response: Decodable { let token: String? }
        let response: Response = try await execute(
            "beeper-submit-code", arguments: Arguments(domain: domain, request: request, response: code)
        )
        guard let token = response.token, !token.isEmpty else {
            throw MatrixError.decoding("Beeper did not return a JWT")
        }
        return token
    }

    static func loginCustomJWT(homeserverURL: String, jwt: String) async throws -> ManageState {
        struct Login: Encodable { let type: String; let token: String }
        struct Arguments: Encodable { let homeserverURL: String; let request: Login }
        return try await execute("login-custom", arguments: Arguments(
            homeserverURL: homeserverURL,
            request: Login(type: "org.matrix.login.jwt", token: jwt)
        ))
    }

    static func verifyRecoveryKey(_ recoveryKey: String) async throws -> ManageState {
        struct Arguments: Encodable { let recoveryKey: String }
        return try await execute("verify", arguments: Arguments(recoveryKey: recoveryKey))
    }

    static func logout() async throws {
        try await executeRaw("logout", arguments: EmptyArguments())
    }
}
