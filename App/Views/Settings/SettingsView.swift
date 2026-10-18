import SwiftUI
import SwiftMediaViewer

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(NotificationService.self) private var notificationService
    @AppStorage("autoplay") private var autoplay = true
    @AppStorage("muteOnPlay") private var muteOnPlay = false
    @State private var signOutError: String?

    var body: some View {
        NavigationStack {
            Form {

                Section {
                    if sessionStore.accessToken.isEmpty {
                        Text("Not signed in.")
                            .foregroundStyle(.secondary)
                    } else {
                        profileRow
                    }
                    if let signOutError { Text(signOutError).foregroundStyle(.red) }
                }

                if !sessionStore.accessToken.isEmpty {
                    NotificationSettingsSection()
                }

                Section("Playback") {
                    Toggle(isOn: $autoplay) {
                        Label("Autoplay Videos", systemImage: "play.fill")
                    }
                    Toggle(isOn: $muteOnPlay) {
                        Label("Mute on Play", systemImage: "speaker.slash.fill")
                    }
                }

                Section("Cache") {
                   Button {
                       AuthenticatedImageLoader.clearTempFiles()
                   } label: {
                       Label("Delete File Cache", systemImage: "trash")
                   }
                   CacheManagerView()
               }
            }
            .navigationTitle("Settings")
            .toolbarTitleDisplayMode(.inline)
            .formStyle(.grouped)
            .contentMargins(.top, 10)
            #if os(macOS)
            .frame(width: 520)
            #else
            .toolbar {
               ToolbarItem(placement: .primaryAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            #endif
        }
    }

    private var profileRow: some View {
        HStack(spacing: 12) {
            let profile = chatStore.currentUserProfile
            ProfileAvatarView(
                name: profile?.displayName ?? "?",
                imageURLString: profile?.imgURL,
                dimension: 44
            )
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
                Task {
                    do {
                        try await notificationService.prepareForSignOut()
                        _ = try await MatrixRuntime.shared.command(Data("{\"action\":\"logout\"}".utf8))
                    } catch {
                        signOutError = error.localizedDescription
                        await notificationService.configure(signedIn: !sessionStore.accessToken.isEmpty)
                        return
                    }
                    sessionStore.clearToken()
                }
            }
            .buttonStyle(.plain)
            .labelStyle(.iconOnly)
            .foregroundStyle(.red)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SettingsView()
        .environment(SessionStore())
        .environment(ChatStore())
        .environment(NotificationService())
}
