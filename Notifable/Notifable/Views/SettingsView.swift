import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var expenses: [Expense]
    
    @State private var showDeleteConfirmation = false
    @State private var showFinalWarning = false
    
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("syncBBVA") private var syncBBVA = true
    @AppStorage("syncBCP") private var syncBCP = true
    @AppStorage("syncYape") private var syncYape = true
    @AppStorage("syncInterbank") private var syncInterbank = true
    @AppStorage("syncScotiabank") private var syncScotiabank = true
    
    @AppStorage("cloudAIAnalysis") private var cloudAIAnalysis = true
    @AppStorage("cloudSocialFeed") private var cloudSocialFeed = false
    
    @StateObject private var gmailAuth = GmailAuthService.shared
    @StateObject private var gmailSync = GmailSyncService.shared
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Preferencias")) {
                    Toggle("Notificaciones de Presupuesto", isOn: $notificationsEnabled)
                        .tint(.purple)
                    
                    Button(action: {
                        // TODO: Implement CSV Export
                    }) {
                        Label("Exportar a CSV", systemImage: "square.and.arrow.up")
                    }
                    .foregroundStyle(.primary)
                }
                
                Section(header: Text("Conexiones")) {
                    NavigationLink(destination: initialSyncView) {
                        Label("Sincronización Inicial", systemImage: "building.columns.fill")
                    }
                    
                    NavigationLink(destination: onlineConfigView) {
                        Label("Configuración Online", systemImage: "cloud.fill")
                    }
                }
                
                Section(header: Text("Gestión de Datos"), footer: Text("Esta acción es irreversible y borrará todos los gastos registrados localmente.")) {
                    Button(role: .destructive, action: {
                        showDeleteConfirmation = true
                    }) {
                        Label("Borrar todos los datos", systemImage: "trash.fill")
                    }
                }
                
                Section(header: Text("Acerca de")) {
                    HStack {
                        Text("Versión")
                        Spacer()
                        Text("1.0 (PoC)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Configuración")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                }
            }
            .preferredColorScheme(.dark)
            .confirmationDialog(
                "¿Estás seguro?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sí, quiero borrarlos", role: .destructive) {
                    // Muestra el disclaimer adicional
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showFinalWarning = true
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Esta acción eliminará todos tus gastos de prueba de SwiftData.")
            }
            .alert("⚠️ ADVERTENCIA FINAL", isPresented: $showFinalWarning) {
                Button("Eliminar Todo", role: .destructive) {
                    deleteAllData()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Estás a punto de borrar absolutamente toda la base de datos local y el historial de correos de la caché. No hay vuelta atrás. ¿Continuar?")
            }
        }
    }
    
    // MARK: - Submenús
    
    private var initialSyncView: some View {
        Form {
            Section(header: Text("Conexión con el Banco")) {
                if gmailAuth.isAuthenticated {
                    Button(action: {
                        gmailSync.modelContext = modelContext
                        gmailSync.syncEmails()
                    }) {
                        Label(gmailSync.isSyncing ? "Buscando nuevos gastos..." : "Sincronizar Correos", systemImage: "envelope.arrow.triangle.branch")
                    }
                    .disabled(gmailSync.isSyncing)
                    
                    Button(role: .destructive, action: {
                        gmailAuth.signOut()
                    }) {
                        Label("Desvincular Gmail", systemImage: "xmark.circle")
                    }
                } else {
                    Button(action: {
                        gmailAuth.signIn()
                    }) {
                        Label("Vincular Gmail (Lectura Automática)", systemImage: "envelope.badge")
                    }
                }
            }
            
            Section(header: Text("Bancos a Sincronizar"), footer: Text("Selecciona de qué bancos quieres que la app lea notificaciones automáticamente.")) {
                Toggle("BBVA (Activo)", isOn: $syncBBVA).tint(.blue)
                Toggle("BCP", isOn: $syncBCP).tint(.orange)
                Toggle("Yape", isOn: $syncYape).tint(.purple)
                Toggle("Interbank", isOn: $syncInterbank).tint(.green)
                Toggle("Scotiabank", isOn: $syncScotiabank).tint(.red)
            }
        }
        .navigationTitle("Sincronización Inicial")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var onlineConfigView: some View {
        Form {
            Section(header: Text("Respaldo en la Nube (Supabase)"), footer: Text("Tus datos se guardarán de forma segura en nuestros servidores.")) {
                Button(action: {
                    Task { await SyncManager.shared.syncLocalExpensesToCloud(localExpenses: expenses) }
                }) {
                    Label(SyncManager.shared.isSyncing ? "Subiendo a la nube..." : "Forzar Backup Manual", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(SyncManager.shared.isSyncing)
            }
            
            Section(header: Text("Funciones IA y Sociales")) {
                Toggle("Análisis Financiero con IA", isOn: $cloudAIAnalysis)
                    .tint(.purple)
                Toggle("Feed en vivo de amigos", isOn: $cloudSocialFeed)
                    .tint(.blue)
            }
        }
        .navigationTitle("Configuración Online")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Lógica
    
    private func deleteAllData() {
        do {
            try modelContext.delete(model: Expense.self)
            try modelContext.save()
            // Reset the sync state so the user can re-sync emails
            gmailSync.resetSyncState()
        } catch {
            print("Error al borrar los datos: \(error)")
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: Expense.self, inMemory: true)
}
