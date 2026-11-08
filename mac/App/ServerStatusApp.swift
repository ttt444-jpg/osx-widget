import SwiftUI
import WidgetKit

@main
struct ServerStatusApp: App {
    var body: some Scene {
        WindowGroup("Server-Status") {
            ContentView()
                .frame(width: 460)
        }
        .windowResizability(.contentSize)
    }
}

/// Die App ist nur Hülle fürs Widget: Verbindung testen und Widgets neu laden.
struct ContentView: View {
    @State private var url = "https://status.example.de/status"
    @State private var token = ""
    @State private var result = ""
    @State private var testing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Server-Status")
                .font(.title2.weight(.semibold))
            Text("Widget hinzufügen: Rechtsklick auf den Schreibtisch → „Widgets bearbeiten“ → Server-Status. URL und Token trägst du per Rechtsklick auf das Widget → „Widget bearbeiten“ ein.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Text("Verbindung testen").font(.headline)
            TextField("Status-URL", text: $url)
            SecureField("Token", text: $token)

            HStack {
                Button(testing ? "Teste…" : "Testen") { Task { await test() } }
                    .disabled(testing)
                Button("Widgets neu laden") { WidgetCenter.shared.reloadAllTimelines() }
                Spacer()
            }

            if !result.isEmpty {
                Text(result)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(24)
    }

    private func test() async {
        testing = true
        defer { testing = false }
        do {
            let s = try await StatusFetcher.fetch(url: url, token: token)
            let p = s.problems.isEmpty ? "keine Probleme" : s.problems.joined(separator: ", ")
            result = "✓ \(s.health.title) – \(p)"
        } catch {
            result = "✗ \(error.localizedDescription)"
        }
    }
}
