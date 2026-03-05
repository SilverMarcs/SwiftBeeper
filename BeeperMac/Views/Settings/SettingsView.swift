import SwiftUI

struct SettingsView: View {
    @Environment(SessionStore.self) private var sessionStore

    var body: some View {
        @Bindable var sessionStore = sessionStore

        Form {
            Section("Beeper API") {
                SecureField("Bearer token", text: $sessionStore.accessToken)
                    .textFieldStyle(.roundedBorder)

                Text("Use the token for localhost:23373 API requests.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Clear Token", role: .destructive) {
                    sessionStore.clearToken()
                }
                .disabled(sessionStore.accessToken.isEmpty)
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
