import Observation
import SwiftUI
import UserNotifications

/// Enrolls this device for APNs pushes through the push server, keeps the
/// notification extension's credentials and the server's copy of the
/// notification preferences current, and tidies delivered notifications.
@MainActor
@Observable
final class NotificationService {
    /// Whether Relay is frontmost.
    private(set) var isAppActive = false
    private(set) var authorizationStatus: UNAuthorizationStatus?
    private(set) var errorMessage: String?
    private(set) var isRegistering = false
    private(set) var isPreparing = false
    /// The APNs token this process already registered, so returning to the
    /// foreground does not register it again.
    private var registeredToken: String?

    @ObservationIgnored private var isSignedIn = false
    @ObservationIgnored private var requestedAppleToken = false
    @ObservationIgnored private var notificationsAllowed = false
    @ObservationIgnored private var identity: PushIdentity?
    @ObservationIgnored private var deviceToken: String?
    @ObservationIgnored private var registrationTask: Task<Void, Never>?
    @ObservationIgnored private var preferenceSyncTask: Task<Void, Error>?
    @ObservationIgnored private var preferenceSyncRequested = false
    @ObservationIgnored private var uploadedPreferences: Data?
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let pushServer = try? PushServer()
    /// Holds the saved `PushRegistration`, so sign-out can remove its pusher.
    private let registrationKey = "push.registration"

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
            let credentials = try await APIClient.notificationCredentials()
            guard isSignedIn, !Task.isCancelled else { return }
            identity = try JSONDecoder().decode(PushIdentity.self, from: credentials)
            if identity?.backupKey.isEmpty == false {
                try NotificationCredentials.save(credentials)
            } else {
                try NotificationCredentials.remove()
            }
            _ = try server()
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
                    await cancelRegistration()
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

    /// Awaits the homeserver's acknowledgement; the normal composer queues sends instead.
    func reply(_ text: String, to chatID: String, messageID: String?) async {
        guard !text.isBlank else { return }
        do {
            try await APIClient.sendNotificationReply(chatID: chatID, messageID: messageID, text: text)
            clearDeliveredNotifications(for: chatID)
        } catch {
            errorMessage = "Could not send your notification reply: \(error.localizedDescription)"
            await UNUserNotificationCenter.current().addFailedReply(text, chatID: chatID, messageID: messageID)
        }
    }

    func receivedDeviceToken(_ data: Data) {
        // APNs tokens are requested at launch and kept only in memory.
        deviceToken = data.map { let value = String($0, radix: 16); return value.count == 1 ? "0" + value : value }.joined()
        enrollIfNeeded()
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
                let preferences = try await APIClient.pushPreferences()
                try Task.checkCancellation()
                guard isSignedIn else { return }
                if preferences != uploadedPreferences {
                    try await APIClient.configureMentionNotifications()
                    try await server().uploadPreferences(preferences)
                    try Task.checkCancellation()
                    uploadedPreferences = preferences
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
        await cancelRegistration()
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
        Task { await UNUserNotificationCenter.current().removeDeliveredNotifications(forChat: chatID) }
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

    /// Cancels an enrollment in progress and waits for it to stop.
    private func cancelRegistration() async {
        let pending = registrationTask
        pending?.cancel()
        await pending?.value
    }

    private func register(token: String) async throws {
        let server = try server()
        let registration = try await server.register(token: token)
        // Save before adding the pusher so sign-out can clean up a partial setup.
        defaults.set(try JSONEncoder().encode(registration), forKey: registrationKey)
        try Task.checkCancellation()
        guard isSignedIn else { throw CancellationError() }
        let deviceName = Device.isMac ? "Relay on Mac" : Device.isIPad ? "Relay on iPad" : "Relay on iPhone"
        try await APIClient.setPusher(pushkey: registration.pushkey, appID: registration.appID,
                                      gatewayURL: server.gatewayURL, deviceDisplayName: deviceName)
    }

    private func removeRegistration() async throws {
        if let data = defaults.data(forKey: registrationKey) {
            let registration = try JSONDecoder().decode(PushRegistration.self, from: data)
            try await APIClient.removePusher(pushkey: registration.pushkey, appID: registration.appID)
        }
        try await pushServer?.unregister()
        defaults.removeObject(forKey: registrationKey)
    }

    private func server() throws -> PushServer {
        guard let pushServer else { throw PushError.notConfigured }
        return pushServer
    }
}

/// The notification extension's decryption credentials, as the core reports them.
private struct PushIdentity: Decodable {
    let userID: String
    let deviceID: String
    let backupKey: String
}
