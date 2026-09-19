import SwiftUI

/// Lo que dejó `Diagnostics`: bitácoras de las últimas aperturas e informes
/// de MetricKit, cada uno para leer o compartir.
struct DiagnosticsView: View {
    @State private var reports: [URL] = []
    @State private var sessions: [URL] = []
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                Text("Si la app se congela o se cierra, aquí queda la última marca de lo que estaba haciendo. Los informes de iOS con la pila de llamadas llegan en la apertura siguiente, a veces horas después.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Informes de iOS (\(reports.count))") {
                if reports.isEmpty {
                    Text("Ninguno todavía").foregroundStyle(.secondary)
                }
                ForEach(reports, id: \.self) { url in
                    fileRow(url)
                }
            }

            Section("Bitácoras por apertura (\(sessions.count))") {
                ForEach(sessions, id: \.self) { url in
                    fileRow(url, badge: hangCount(in: url))
                }
            }

            Section {
                #if DEBUG
                Button("Simular cuelgue de 4 s") {
                    Thread.sleep(forTimeInterval: 4)
                    reload()
                }
                #endif
                Button("Borrar registros anteriores", role: .destructive) {
                    confirmDelete = true
                }
            }
        }
        .navigationTitle("Diagnóstico")
        .onAppear(perform: reload)
        .refreshable { reload() }
        .confirmationDialog("¿Borrar los registros?", isPresented: $confirmDelete) {
            Button("Borrar", role: .destructive) {
                Diagnostics.shared.deleteAll()
                reload()
            }
        } message: {
            Text("Se conserva la bitácora de esta apertura.")
        }
    }

    private func fileRow(_ url: URL, badge: Int = 0) -> some View {
        NavigationLink {
            DiagnosticFileView(url: url)
        } label: {
            HStack {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.footnote.monospaced())
                    .fontDesign(.monospaced)
                    .lineLimit(1)
                Spacer()
                if badge > 0 {
                    Text("\(badge) cuelgue\(badge == 1 ? "" : "s")")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func hangCount(in url: URL) -> Int {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        return text.components(separatedBy: "CUELGUE").count - 1
    }

    private func reload() {
        reports = Diagnostics.shared.files(prefix: "metrickit-")
        sessions = Diagnostics.shared.files(prefix: "session-")
    }
}

private struct DiagnosticFileView: View {
    let url: URL
    @State private var text = ""

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(text)
                .font(.caption2.monospaced())
                .fontDesign(.monospaced)
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(url.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ShareLink(item: url)
        }
        .onAppear {
            text = (try? String(contentsOf: url, encoding: .utf8)) ?? "No se pudo leer"
        }
    }
}
