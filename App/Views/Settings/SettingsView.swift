import SwiftUI
import SwiftMediaViewer

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var sessionStore
    @AppStorage("autoplay") private var autoplay = true
    @AppStorage("muteOnPlay") private var muteOnPlay = false
    @AppStorage(ChatNetworkIcons.storageKey) private var showsNetworkIcons = true

    var body: some View {
        NavigationStack {
            Form {
                AccountSection()

                if sessionStore.isSignedIn {
                    NotificationSettingsSection()
                }

                Section {
                    Toggle(isOn: $showsNetworkIcons) {
                        Label("Show Network Icons", systemImage: "app.badge")
                    }
                } header: {
                    Text("Chat List")
                } footer: {
                    Text("Marks each chat's avatar with the logo of its network, such as WhatsApp or Slack.")
                }

                Section("Playback") {
                    Toggle(isOn: $autoplay) {
                        Label("Autoplay Videos", systemImage: "play.fill")
                    }
                    Toggle(isOn: $muteOnPlay) {
                        Label("Mute on Play", systemImage: "speaker.slash.fill")
                    }
                }

                DictationSettingsSection()

                Section("Cache") {
                    Button {
                        Task { await MatrixMedia.clearCaches() }
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
}

#Preview {
    SettingsView()
        .environment(DictationSettings())
        .environment(SessionStore())
        .environment(ChatStore())
        .environment(NotificationService())
}
