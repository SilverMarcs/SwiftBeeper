import SwiftUI

struct SettingsView: View {
    @Environment(SessionStore.self) private var sessionStore

    var body: some View {
        Form {
            Section("Account") {
                if sessionStore.accessToken.isEmpty {
                    Text("Not signed in.")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Sign out", role: .destructive) {
                        sessionStore.clearToken()
                    }
                }
            }

            Section {
                Button("Delete Cache", role: .destructive) {
                    AuthenticatedImageLoader.clearTempFiles()
                }
            } footer: {
                Text("Removes downloaded media files from the temporary directory.")
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
        .frame(width: 520)
        #endif
    }
}

#Preview {
    SettingsView()
        .environment(SessionStore())
}
