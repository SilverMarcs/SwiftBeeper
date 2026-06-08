import SwiftUI
import SwiftMediaViewer

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var sessionStore
    @AppStorage("dismissKeyboardAfterSend") private var dismissKeyboardAfterSend = false

    var body: some View {
        NavigationStack {
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
    
                #if !os(macOS)
                Section("Keyboard") {
                    Toggle("Dismiss Keyboard After Send", isOn: $dismissKeyboardAfterSend)
                }
                #endif
                
               Section("Cache") {
                   CacheManagerView()
               }
            }
            .navigationTitle("Settings")
            .toolbarTitleDisplayMode(.inline)
            .formStyle(.grouped)
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
        .environment(SessionStore())
}
