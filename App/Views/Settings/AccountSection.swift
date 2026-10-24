import SwiftUI

/// The signed-in profile with its Sign Out button.
struct AccountSection: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(NotificationService.self) private var notificationService
    @State private var signOutError: String?

    var body: some View {
        Section {
            if sessionStore.isSignedIn {
                let profile = chatStore.currentUserProfile
                HStack(spacing: 12) {
                    ProfileAvatarView(participant: profile, dimension: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile?.displayName ?? "Account")
                            .bold()
                        if let username = profile?.username, !username.isEmpty,
                           username != profile?.displayName {
                            Text(username)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        Task { await signOut() }
                    }
                    .buttonStyle(.plain)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.red)
                }
                .padding(.vertical, 4)
            } else {
                Text("Not signed in.")
                    .foregroundStyle(.secondary)
            }
            if let signOutError { Text(signOutError).foregroundStyle(.red) }
        }
    }

    /// Removes the push registration first, so a signed-out device stops
    /// receiving pushes; on failure Relay stays signed in.
    private func signOut() async {
        do {
            try await notificationService.prepareForSignOut()
            try await APIClient.logout()
        } catch {
            signOutError = error.localizedDescription
            await notificationService.configure(signedIn: sessionStore.isSignedIn)
            return
        }
        sessionStore.isSignedIn = false
    }
}
