import Foundation

struct ManageState: Decodable {
    let clientState: ClientState?
    let homeserverHost: String?

    enum CodingKeys: String, CodingKey {
        case clientState = "client_state"
        case homeserverHost = "homeserver_host"
    }
}

struct ClientState: Decodable {
    let isInitialized: Bool
    let isLoggedIn: Bool
    let isVerified: Bool
    let userID: String?
    let deviceID: String?
    let homeserverURL: String?

    enum CodingKeys: String, CodingKey {
        case isInitialized = "is_initialized"
        case isLoggedIn = "is_logged_in"
        case isVerified = "is_verified"
        case userID = "user_id"
        case deviceID = "device_id"
        case homeserverURL = "homeserver_url"
    }
}

struct AccessTokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int64
    let scope: String?
    let resource: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
        case resource
    }
}

struct PushPrivacyTestState: Decodable {
    let registered: Bool
    let gatewayURL: String?
    let registeredAt: Date?
    let lastNotification: PushPrivacyTestNotification?
}

struct PushPrivacyTestNotification: Decodable {
    let receivedAt: Date
    let eventID: String?
    let roomID: String?
    let unreadCount: Int
    let deviceCount: Int
    let fields: [String]
    let hadContent: Bool
    let hadSender: Bool
}

extension APIClient {
    static func manageState() async throws -> ManageState {
        try await get(url: manageURL("state"))
    }

    static func beeperStartLogin(domain: String) async throws -> String {
        struct Body: Encodable { let domain: String }
        struct Response: Decodable { let request: String? }
        let resp: Response = try await post(url: manageURL("beeper/start-login"), body: Body(domain: domain))
        guard let request = resp.request, !request.isEmpty else {
            throw APIError.decoding("Beeper did not return a request id")
        }
        return request
    }

    static func beeperRequestCode(domain: String, request: String, email: String) async throws {
        struct Body: Encodable { let domain: String; let request: String; let email: String }
        let url = manageURL("beeper/request-code")
        let req = try Self.request(url: url, method: .post, body: Body(domain: domain, request: request, email: email), accessToken: accessToken)
        _ = try await sendRaw(req)
    }

    static func beeperSubmitCode(domain: String, request: String, code: String) async throws -> String {
        struct Body: Encodable { let domain: String; let request: String; let response: String }
        struct Response: Decodable { let token: String? }
        let resp: Response = try await post(url: manageURL("beeper/submit-code"), body: Body(domain: domain, request: request, response: code))
        guard let token = resp.token, !token.isEmpty else {
            throw APIError.decoding("Beeper did not return a JWT")
        }
        return token
    }

    static func loginCustomJWT(homeserverURL: String, jwt: String) async throws -> ManageState {
        struct Inner: Encodable { let type: String; let token: String }
        struct Body: Encodable { let homeserverURL: String; let request: Inner }
        return try await post(url: manageURL("login-custom"), body: Body(
            homeserverURL: homeserverURL,
            request: Inner(type: "org.matrix.login.jwt", token: jwt)
        ))
    }

    static func verifyRecoveryKey(_ recoveryKey: String) async throws -> ManageState {
        struct Body: Encodable { let recoveryKey: String }
        return try await post(url: manageURL("verify"), body: Body(recoveryKey: recoveryKey))
    }

    static func mintAccessToken() async throws -> AccessTokenResponse {
        struct Empty: Encodable {}
        return try await post(url: manageURL("access-token"), body: Empty())
    }

    static func pushPrivacyTestState(manageSecret: String) async throws -> PushPrivacyTestState {
        let request = pushPrivacyTestRequest(method: .get, manageSecret: manageSecret)
        return try await send(request)
    }

    static func registerPushPrivacyTest(
        gatewayURL: String,
        manageSecret: String
    ) async throws -> PushPrivacyTestState {
        struct Body: Encodable { let gatewayURL: String }
        var request = try request(
            url: manageURL("push-privacy-test"),
            method: .post,
            body: Body(gatewayURL: gatewayURL),
            accessToken: accessToken
        )
        request.setValue(manageSecret, forHTTPHeaderField: "X-EasyMatrix-Manage-Secret")
        return try await send(request)
    }

    static func removePushPrivacyTest(manageSecret: String) async throws -> PushPrivacyTestState {
        let request = pushPrivacyTestRequest(method: .delete, manageSecret: manageSecret)
        return try await send(request)
    }

    private static func pushPrivacyTestRequest(
        method: HTTPMethod,
        manageSecret: String
    ) -> URLRequest {
        var request = request(
            url: manageURL("push-privacy-test"),
            method: method,
            accessToken: accessToken
        )
        request.setValue(manageSecret, forHTTPHeaderField: "X-EasyMatrix-Manage-Secret")
        return request
    }

    private static func manageURL(_ path: String) -> URL {
        APIConfiguration.baseURL.appending(path: "/manage/\(path)")
    }
}

extension APIClient {
    static func registerPushDevice(token: String, platform: String) async throws {
        struct Body: Encodable {
            let token: String
            let platform: String
            let serverURL: String
        }
        struct Response: Decodable {
            let success: Bool
        }

        let url = APIConfiguration.baseURL.appending(path: "/v1/push/devices")
        let _: Response = try await post(
            url: url,
            body: Body(
                token: token,
                platform: platform,
                serverURL: APIConfiguration.baseURL.absoluteString
            )
        )
    }

    static func unregisterPushDevice(token: String) async throws {
        struct Response: Decodable {
            let success: Bool
        }

        let url = APIConfiguration.baseURL.appending(path: "/v1/push/devices/\(token)")
        let _: Response = try await delete(url: url)
    }
}
