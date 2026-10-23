import Observation
import SwiftUI
import UserNotifications

@MainActor
@Observable
final class NotificationService {
    /// Whether Relay is frontmost.
    private(set) var isAppActive = false
    private(set) var authorizationStatus: UNAuthorizationStatus?
    private(set) var errorMessage: String?
    private(set) var isRegistering = false
    private(set) var isPreparing = false

    @ObservationIgnored private var isSignedIn = false
    @ObservationIgnored private var requestedAppleToken = false
    @ObservationIgnored private var notificationsAllowed = false
    @ObservationIgnored private var identity: PushIdentity?
    @ObservationIgnored private var deviceToken: String?
    /// The APNs token this process already registered, so returning to the
    /// foreground does not register it again.
    private var registeredToken: String?
    @ObservationIgnored private var registrationTask: Task<Void, Never>?
    @ObservationIgnored private var preferenceSyncTask: Task<Void, Error>?
    @ObservationIgnored private var preferenceSyncRequested = false
    @ObservationIgnored private var uploadedPreferences: Data?
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let installationID: String
    @ObservationIgnored private let configuration = try? PushConfiguration.load()
    private let registrationKey = "push.registration"

    init() {
        let key = "push.installationID"
        let identifier = UserDefaults.standard.string(forKey: key) ?? UUID().uuidString
        installationID = identifier
        UserDefaults.standard.set(identifier, forKey: key)
    }

    /// Whether this launch registered with the push server, so pushes arrive.
    var isRegistered: Bool { registeredToken != nil }

    /// Opening Relay clears its badge and its entries in Notification Center.
    func setAppActive(_ active: Bool) {
        isAppActive = active
        guard active else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        Task { try? await center.setBadgeCount(0) }
    }

    func configure(signedIn: Bool, force: Bool = false) async {
        isSignedIn = signedIn
        guard signedIn else {
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            try? NotificationCredentials.remove()
            identity = nil
            notificationsAllowed = false
            uploadedPreferences = nil
            registeredToken = nil
            errorMessage = nil
            return
        }
        guard !isPreparing else { return }
        isPreparing = true
        errorMessage = nil
        defer { isPreparing = false }
        do {
            let credentials = try await MatrixRuntime.shared.command(Data("{\"action\":\"notification-credentials\"}".utf8))
            guard isSignedIn, !Task.isCancelled else { return }
            identity = try JSONDecoder().decode(PushIdentity.self, from: credentials)
            if identity?.backupKey.isEmpty == false {
                try NotificationCredentials.save(credentials)
            } else {
                try NotificationCredentials.remove()
            }
            _ = try pushConfiguration()
            let center = UNUserNotificationCenter.current()
            var settings = await center.notificationSettings()
            authorizationStatus = settings.authorizationStatus
            if settings.authorizationStatus == .notDetermined {
                _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                settings = await center.notificationSettings()
                authorizationStatus = settings.authorizationStatus
            }
            guard isSignedIn, !Task.isCancelled else { return }
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                notificationsAllowed = false
                registeredToken = nil
                if defaults.data(forKey: registrationKey) != nil {
                    let pending = registrationTask
                    pending?.cancel()
                    await pending?.value
                    try await removeRegistration()
                }
                return
            }
            notificationsAllowed = true
            if force {
                registeredToken = nil
                requestedAppleToken = false
                uploadedPreferences = nil
            }
            try await syncNotificationPreferences()
            if deviceToken != nil { enrollIfNeeded() }
            guard !requestedAppleToken else { return }
            requestedAppleToken = true
            #if os(macOS)
            NSApplication.shared.registerForRemoteNotifications(matching: [.alert, .sound, .badge])
            #else
            UIApplication.shared.registerForRemoteNotifications()
            #endif
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }

    /// Registration must precede delivery, including launches for a reply action.
    static func registerCategories() {
        let reply = UNTextInputNotificationAction(
            identifier: NotificationCategory.reply,
            title: "Reply",
            options: [.authenticationRequired],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Message…"
        )
        let category = UNNotificationCategory(
            identifier: NotificationCategory.message,
            actions: [reply],
            intentIdentifiers: ["INSendMessageIntent"],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Await server acknowledgement; the normal composer queues sends instead.
    func reply(_ text: String, to chatID: String, messageID: String?) async {
        guard !text.trimmed.isEmpty else { return }
        do {
            let command = NotificationReplyCommand(roomID: chatID, eventID: messageID, text: text)
            _ = try await MatrixRuntime.shared.command(JSONEncoder().encode(command))
            clearDeliveredNotifications(for: chatID)
        } catch {
            errorMessage = "Could not send your notification reply: \(error.localizedDescription)"
            let content = UNMutableNotificationContent()
            content.title = "Reply wasn’t sent"
            content.body = text
            content.categoryIdentifier = NotificationCategory.message
            content.threadIdentifier = chatID
            content.userInfo = ["chatID": chatID, "replyDraft": text]
            if let messageID { content.userInfo["messageID"] = messageID }
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    func receivedDeviceToken(_ data: Data) {
        // APNs tokens are requested at launch and kept only in memory.
        deviceToken = data.map { let value = String($0, radix: 16); return value.count == 1 ? "0" + value : value }.joined()
        enrollIfNeeded()
    }

    private func enrollIfNeeded() {
        guard isSignedIn, notificationsAllowed, !isRegistering else { return }
        isRegistering = true
        registrationTask = Task {
            defer { isRegistering = false; registrationTask = nil }
            // If Apple rotates the token during registration, finish this attempt
            // before enrolling the latest token. Sign-out waits for this task.
            while isSignedIn, notificationsAllowed, let token = deviceToken, token != registeredToken {
                do {
                    try Task.checkCancellation()
                    guard identity != nil else { return }
                    try await register(token: token)
                    try Task.checkCancellation()
                    registeredToken = token
                    if !Task.isCancelled { errorMessage = nil }
                } catch {
                    if !Task.isCancelled { errorMessage = error.localizedDescription }
                }
                if Task.isCancelled || token == deviceToken { break }
            }
        }
    }

    func registrationFailed(_ error: Error) {
        guard isSignedIn else { return }
        requestedAppleToken = false
        errorMessage = "Apple push registration failed: \(error.localizedDescription)"
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Coalesce changes from sync and archive and mute actions. Unchanged preferences
    /// require only a local database read; there is no timer or per-chat fetch.
    func syncNotificationPreferences() async throws {
        guard isSignedIn else { return }
        preferenceSyncRequested = true
        if let preferenceSyncTask { try await preferenceSyncTask.value; return }
        let task = Task {
            while preferenceSyncRequested, isSignedIn {
                preferenceSyncRequested = false
                let body = try await MatrixRuntime.shared.command(Data("{\"action\":\"push-preferences\"}".utf8))
                try Task.checkCancellation()
                guard isSignedIn else { return }
                if body != uploadedPreferences {
                    _ = try await send(method: "PUT", body: body, path: "notification-preferences")
                    try Task.checkCancellation()
                    uploadedPreferences = body
                }
            }
        }
        preferenceSyncTask = task
        defer { preferenceSyncTask = nil }
        try await task.value
    }

    func notificationPreferencesChanged() {
        Task {
            do { try await syncNotificationPreferences() }
            catch { if isSignedIn { errorMessage = "Could not update notification preferences. Reopen Relay to retry." } }
        }
    }

    func prepareForSignOut() async throws {
        isSignedIn = false
        let pending = registrationTask
        pending?.cancel()
        await pending?.value
        preferenceSyncTask?.cancel()
        _ = try? await preferenceSyncTask?.value
        uploadedPreferences = nil
        do {
            try await removeRegistration()
            try NotificationCredentials.remove()
            identity = nil
            requestedAppleToken = false
            deviceToken = nil
            registeredToken = nil
            errorMessage = nil
        } catch {
            isSignedIn = true
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func clearDeliveredNotifications(for chatID: String) {
        guard !chatID.isEmpty else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let notifications = await center.deliveredNotifications()
            let identifiers = notifications.compactMap { notification in
                let content = notification.request.content
                let room = content.userInfo["chatID"] as? String ?? content.threadIdentifier
                return room == chatID ? notification.request.identifier : nil
            }
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    private func register(token: String) async throws {
        let configuration = try pushConfiguration()
        let body = try JSONEncoder().encode(["token": token])
        let data = try await send(method: "PUT", body: body)
        let registration = try JSONDecoder().decode(PushRegistration.self, from: data)
        guard registration.pushkey.count == 64,
              registration.pushkey.allSatisfy({ $0.isHexDigit }),
              registration.appID == Bundle.main.bundleIdentifier else { throw PushError.invalidRegistration }
        // Save before Matrix registration so sign-out can clean up a partial setup.
        defaults.set(try JSONEncoder().encode(registration), forKey: registrationKey)
        try Task.checkCancellation()
        guard isSignedIn else { throw CancellationError() }
        #if os(macOS)
        let name = "Relay on Mac"
        #else
        let name = UIDevice.current.userInterfaceIdiom == .pad ? "Relay on iPad" : "Relay on iPhone"
        #endif
        let command = MatrixPusherCommand(action: "set-pusher", pushkey: registration.pushkey,
                                          appID: registration.appID,
                                          gatewayURL: configuration.serverURL.appending(path: "_matrix/push/v1/notify").absoluteString,
                                          deviceDisplayName: name)
        _ = try await MatrixRuntime.shared.command(JSONEncoder().encode(command))
    }

    private func removeRegistration() async throws {
        if let data = defaults.data(forKey: registrationKey) {
            let registration = try JSONDecoder().decode(PushRegistration.self, from: data)
            let command = MatrixPusherCommand(action: "remove-pusher", pushkey: registration.pushkey,
                                              appID: registration.appID, gatewayURL: nil, deviceDisplayName: nil)
            _ = try await MatrixRuntime.shared.command(JSONEncoder().encode(command))
        }
        // Delete by installation ID even if an interrupted enrollment never
        // returned its pushkey to this process.
        if configuration != nil {
            _ = try await send(method: "DELETE")
        }
        defaults.removeObject(forKey: registrationKey)
    }

    private func pushConfiguration() throws -> PushConfiguration {
        guard let configuration else { throw PushError.notConfigured }
        return configuration
    }

    private func send(method: String, body: Data? = nil, path: String? = nil) async throws -> Data {
        let configuration = try pushConfiguration()
        let url = configuration.serverURL.appending(path: path ?? "devices/\(installationID)")
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(configuration.registrationSecret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw PushError.registrationFailed
        }
        return data
    }
}
