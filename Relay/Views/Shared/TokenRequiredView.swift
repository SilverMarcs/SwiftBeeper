import SwiftUI

struct TokenRequiredView: View {
    let title: String
    let systemImage: String
    let description: String

    #if !os(macOS)
    @State private var showingSettings = false
    #endif

    var body: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: Text(description)
            )

            #if os(macOS)
            SettingsLink {
                Text("Open Settings")
            }
            #else
            // iOS has no Settings scene; present settings in a sheet instead.
            Button("Open Settings") {
                showingSettings = true
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsView()
                }
            }
            #endif
        }
    }
}

#Preview {
    TokenRequiredView(
        title: "Missing Token",
        systemImage: "key.fill",
        description: "Open Settings and add your Beeper bearer token."
    )
}
