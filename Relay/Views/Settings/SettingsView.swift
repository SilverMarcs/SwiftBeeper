import SwiftUI
import SwiftMediaViewer

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ServerConnection.self) private var serverConnection
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(NotificationService.self) private var notificationService
    @AppStorage("autoplay") private var autoplay = true
    @AppStorage("muteOnPlay") private var muteOnPlay = false

    var body: some View {
        NavigationStack {
            Form {
                #if REMOTE_ONLY
                ServerSettingsSection()
                #endif

                Section {
                    if sessionStore.accessToken.isEmpty {
                        Text("Not signed in.")
                            .foregroundStyle(.secondary)
                    } else {
                        profileRow
                    }
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
                    await notificationService.unregisterRemoteRegistration()
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
        .environment(ServerConnection())
        .environment(SessionStore())
        .environment(ChatStore())
        .environment(NotificationService())
}
