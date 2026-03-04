import SwiftUI

struct SettingsView: View {
    @AppStorage("beeperAccessToken") private var accessToken = ""
    @AppStorage("beeperUserID") private var currentUserID = ""

    var body: some View {
        Form {
            Section("Beeper API") {
                SecureField("Bearer token", text: $accessToken)
                    .textFieldStyle(.roundedBorder)

                Text("Use the token for localhost:23373 API requests.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Clear Token", role: .destructive) {
                    accessToken = ""
                }
                .disabled(accessToken.isEmpty)
            }

            Section("Chat Rendering") {
                TextField("Your sender ID (optional)", text: $currentUserID)
                    .textFieldStyle(.roundedBorder)

                Text("Set this to your sender ID so your messages are shown on the right side.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520)
    }
}

#Preview {
    SettingsView()
}
