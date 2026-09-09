import SwiftUI

struct OllamaSettingsRow: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var store: UsageStore
    var relay: OllamaActivityRelay? = nil
    @State private var address = ""
    @State private var addressError: String?

    private var enabled: Bool { preferences.isConnected("ollama") }
    private var snapshot: ProviderSnapshot? { store.snapshots.first { $0.id == "ollama" } }
    private var checking: Bool { store.refreshing.contains("ollama") }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ProviderGlyphView(glyph: .ollama, size: 16)
                Text("Ollama")
                Spacer()
                Toggle("Monitor Ollama", isOn: Binding(
                    get: { enabled },
                    set: { on in
                        preferences.setConnected(on, for: "ollama")
                        store.disconnected = preferences.disconnectedProviders
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .font(.body)

            HStack {
                TextField("Server address", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { applyAddress() }
                    .accessibilityLabel("Ollama server address")
                Button(address == preferences.ollamaEndpoint ? "Check connection" : "Apply") {
                    applyAddress()
                }
                .disabled(address == preferences.ollamaEndpoint && (!enabled || checking))
                .controlSize(.small)
            }

            if let addressError {
                Text(addressError).foregroundStyle(.orange)
            } else if !enabled {
                Text("Monitoring off.")
                    .foregroundStyle(.secondary)
            } else if checking {
                Text("Checking Ollama…").foregroundStyle(.secondary)
            } else {
                Text(snapshot?.localRuntime?.summary ?? snapshot?.statusMessage ?? "Connecting to Ollama…")
                    .foregroundStyle(snapshot?.hasReading == true ? Color.secondary : .orange)
            }

            if enabled, let relay {
                OllamaRelayStatus(relay: relay)
            }
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { address = preferences.ollamaEndpoint }
        .onChange(of: address) { _, _ in addressError = nil }
    }

    private func applyAddress() {
        do {
            let endpoint = try OllamaEndpoint.parse(address)
            address = endpoint.absoluteString
            preferences.ollamaEndpoint = address
            store.updateOllamaEndpoint(endpoint)
            if enabled { store.refresh(providerID: "ollama") }
            addressError = nil
        } catch {
            addressError = error.localizedDescription
        }
    }
}

private struct OllamaRelayStatus: View {
    @ObservedObject var relay: OllamaActivityRelay

    var body: some View {
        if !relay.ready {
            Text(relay.status).foregroundStyle(.orange)
                .textSelection(.enabled)
        }
    }
}
