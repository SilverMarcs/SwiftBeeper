import SwiftUI

struct SettingsView: View {
    @AppStorage("beeperAccessToken") private var accessToken = ""

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
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520)
    }
}

#Preview {
    SettingsView()
}
