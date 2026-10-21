import SwiftUI
#if SWIFT_PACKAGE
import PoochiCore
#endif

struct SettingsView: View {
    @EnvironmentObject private var store: AnalyticsStore
    @Environment(\.dismiss) private var dismiss
    @State private var clientKey = ""
    @State private var secret = ""
    @State private var redirect = TikTokConfiguration.defaultRedirect
    @State private var deleteConfirmation = false
    @State private var hasSavedSecret = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("TikTok connection", systemImage: "lock.shield").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Use Poochi Analytics' sandbox credentials from TikTok for Developers while the application awaits approval.")
                .font(.callout).foregroundStyle(.secondary)
            Form {
                TextField("Client key", text: $clientKey)
                SecureField(hasSavedSecret ? "Client secret (leave blank to keep saved)" : "Client secret", text: $secret)
                TextField("Desktop redirect URI", text: $redirect)
            }.textFieldStyle(.roundedBorder).disabled(store.isConnected || store.isBusy)
            Text("Register this exact redirect in Login Kit → Desktop. The callback listener runs only on this Mac, on 127.0.0.1, while login is in progress.")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            HStack {
                Button("Save settings") {
                    store.saveConfiguration(clientKey: clientKey, secret: secret, redirectURI: redirect)
                    secret = ""; hasSavedSecret = !store.savedSecret().isEmpty
                }
                    .disabled(store.isConnected || store.isBusy)
                Spacer()
                Button(store.isConnected ? "Reconnect TikTok" : "Connect TikTok") { Task { await store.connect() } }
                    .buttonStyle(.borderedProminent).disabled(store.isBusy || store.isSample)
            }
            if let error = store.errorMessage { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            if let notice = store.notice { Text(notice).font(.caption).foregroundStyle(PoochiStyle.teal) }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("Your data").font(.headline)
                Text("Client secrets and tokens are stored in macOS Keychain. Analytics are saved locally in Application Support. History starts with actual observations; watch time, retention, audience demographics, and revenue are not supplied by this integration.")
                    .font(.caption).foregroundStyle(.secondary)
                if !store.scopeNames.isEmpty {
                    Text("Granted permissions: " + store.scopeNames.sorted().joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                HStack {
                    Button("Disconnect and delete account data") { Task { await store.disconnect() } }
                        .disabled(!store.isConnected || store.isBusy || store.isSample)
                    Spacer()
                    Button("Remove local account data…", role: .destructive) { deleteConfirmation = true }.disabled(store.isBusy)
                }
                Text("Removing local data keeps the app's client settings. Exported CSV files are managed separately by you.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Link("Developer Portal ↗", destination: URL(string: "https://developers.tiktok.com/portal/apps")!)
                Spacer()
                Link("Terms", destination: URL(string: "https://hoover2x.github.io/poochi-analytics-pages/terms.html")!)
                Link("Privacy", destination: URL(string: "https://hoover2x.github.io/poochi-analytics-pages/privacy.html")!)
            }.font(.caption)
        }.padding(28).frame(width: 620)
        .onAppear { clientKey = store.clientKey; redirect = store.redirectURI; hasSavedSecret = !store.savedSecret().isEmpty }
        .confirmationDialog("Remove all locally saved account analytics and login tokens?", isPresented: $deleteConfirmation, titleVisibility: .visible) {
            Button("Remove local account data", role: .destructive) { store.forgetLocalData() }
        } message: { Text("This deletes the saved observations on this Mac. It does not delete anything from TikTok. You can reconnect later.") }
    }
}
