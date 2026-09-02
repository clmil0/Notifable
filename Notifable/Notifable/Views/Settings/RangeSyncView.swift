import SwiftUI
import SwiftData

/// Leer un rango pasado. Sale de la pantalla de Gmail porque es una acción
/// puntual, no un ajuste.
struct RangeSyncView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.purple.rawValue

    @StateObject private var gmailSync = GmailSyncService.shared

    @State private var startDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate: Date = Date()
    @State private var showRecoveryAlert = false

    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .purple }
    private var palette: Palette { Palette(scheme) }

    /// Dice exactamente qué va a pasar antes de tocar el botón.
    private var explanation: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_PE")
        f.dateFormat = "d MMM"
        let range = f.string(from: startDate) + " – " + f.string(from: endDate)
        var text = "Se revisa " + range + " completo. Los gastos que ya tienes no se duplican; sólo se añade lo que falte."
        if !GmailSyncService.reachesNow(endDate) {
            text += " La sincronización automática seguirá cubriendo desde ahí hasta hoy."
        }
        return text
    }

    var body: some View {
        Form {
            if gmailSync.isSyncing {
                Section {
                    HStack {
                        ProgressView().padding(.trailing, 8)
                        Text("Leyendo… (\(gmailSync.emailsProcessed)/\(gmailSync.totalEmailsToProcess))")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Section {
                    DatePicker("Desde", selection: $startDate,
                               in: ...endDate, displayedComponents: .date)
                    DatePicker("Hasta", selection: $endDate,
                               in: startDate...Date(), displayedComponents: .date)
                } footer: {
                    Text(explanation)
                }

                Section {
                    Button {
                        gmailSync.modelContext = modelContext
                        let recoveryIDs = UserDefaults.standard.stringArray(forKey: "pendingRecoveryIDs") ?? []
                        if !recoveryIDs.isEmpty {
                            showRecoveryAlert = true
                        } else {
                            gmailSync.syncEmails(force: true, startDate: startDate, endDate: endDate)
                        }
                    } label: {
                        Label("Leer este rango", systemImage: "envelope.arrow.triangle.branch")
                            .foregroundStyle(accent.onSurface(scheme))
                    }
                }
            }
        }
        .navigationTitle("Leer un rango pasado")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Recuperación de Gastos", isPresented: $showRecoveryAlert) {
            Button("Sí, recuperar") {
                let recoveryIDs = UserDefaults.standard.stringArray(forKey: "pendingRecoveryIDs") ?? []
                gmailSync.recoverExpenses(ids: recoveryIDs)
            }
            Button("No (Descartar)") {
                UserDefaults.standard.removeObject(forKey: "pendingRecoveryIDs")
                gmailSync.syncEmails(force: true, startDate: startDate, endDate: endDate)
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Has borrado elementos anteriores. ¿Quieres recuperarlos antes de continuar con la lectura?")
        }
    }
}
