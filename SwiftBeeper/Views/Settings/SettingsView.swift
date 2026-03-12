import SwiftUI

struct SettingsView: View {
    @Environment(SessionStore.self) private var sessionStore

    var body: some View {
        @Bindable var sessionStore = sessionStore

        Form {
            Section {
                SecureField("Bearer token", text: $sessionStore.accessToken)
            } header: {
                Text("Beeper API")
            } footer: {
                Text("Use the token for localhost:23373 API requests.")
            }
            .sectionActions {
                Button("Clear Token", role: .destructive) {
                    sessionStore.clearToken()
                }
                .disabled(sessionStore.accessToken.isEmpty)
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
        .frame(width: 520)
    }
}

#Preview {
    SettingsView()
        .environment(SessionStore())
}
