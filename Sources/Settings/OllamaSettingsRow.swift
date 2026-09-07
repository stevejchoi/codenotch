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
                Text("Monitoring off. Ollama keeps running; no model readings are kept.")
                    .foregroundStyle(.secondary)
            } else if checking {
                Text("Checking Ollama…").foregroundStyle(.secondary)
            } else {
                Text(snapshot?.localRuntime?.summary ?? snapshot?.statusMessage ?? "Connecting to Ollama…")
                    .foregroundStyle(snapshot?.hasReading == true ? Color.secondary : .orange)
            }

            if let relay {
                OllamaThinkingSettings(preferences: preferences, relay: relay, enabled: enabled)
            }

            Text("Loaded models get a cell showing the last measured tok/s. Hover for RAM and context limit. Model residency is checked every 15 seconds.")
                .foregroundStyle(.tertiary)
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

private struct OllamaThinkingSettings: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var relay: OllamaActivityRelay
    let enabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Track speed and thinking through local relay", isOn: $preferences.ollamaThinkingRelayEnabled)
                .toggleStyle(.switch).controlSize(.small).disabled(!enabled)
            if preferences.ollamaThinkingRelayEnabled && enabled {
                HStack {
                    Text(relay.status).foregroundStyle(relay.ready ? Color.secondary : .orange)
                        .textSelection(.enabled)
                    Spacer()
                    Button("Copy address") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(OllamaActivityRelay.address, forType: .string)
                    }.controlSize(.small).disabled(!relay.ready)
                }
                Text("Speed colors: blue ≥40, green 20–40, yellow 10–20, red <10 tok/s. Generation speed is not a PC health rating.")
                    .foregroundStyle(.secondary)
                Text("Use this address in your chat app or OLLAMA_HOST. Keep Codenotch open. Native Ollama responses update generation speed; streamed thinking animates the ring. Prompts and replies are not saved.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
