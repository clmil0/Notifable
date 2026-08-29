import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var expenses: [Expense]
    
    @State private var showDeleteClassificationsConfirmation = false
    @State private var showDeleteExpensesConfirmation = false
    
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
                
                Section(header: Text("Gestión de Datos"), footer: Text("Estas acciones son irreversibles y afectarán tu base de datos local.")) {
                    Button(role: .destructive, action: {
                        showDeleteClassificationsConfirmation = true
                    }) {
                        Label("Borrar configuraciones", systemImage: "tag.slash.fill")
                    }
                    
                    Button(role: .destructive, action: {
                        showDeleteExpensesConfirmation = true
                    }) {
                        Label("Borrar datos de gastos", systemImage: "trash.fill")
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
            .alert("Borrar Reglas", isPresented: $showDeleteClassificationsConfirmation) {
                Button("Borrar Categorías", role: .destructive) { deleteClassifications() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Se eliminarán tus configuraciones de comercios, pero los gastos se mantendrán como 'Sin Clasificar'.")
            }
            .alert("Borrar Gastos", isPresented: $showDeleteExpensesConfirmation) {
                Button("Borrar Gastos", role: .destructive) { deleteExpenses() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Se eliminarán los gastos importados y la caché, pudiendo volver a descargarlos. Tus reglas de categorías se mantendrán.")
            }
        }
    }
    
    // MARK: - Submenús
    
    private var initialSyncView: some View {
        Form {
            Section(header: Text("Conexión con el Banco")) {
                if gmailAuth.isAuthenticated {
                    if gmailSync.isSyncing {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Buscando nuevos gastos...")
                                .font(.headline)
                            
                            ProgressView(value: Double(gmailSync.emailsProcessed), total: Double(max(1, gmailSync.totalEmailsToProcess)))
                                .progressViewStyle(LinearProgressViewStyle())
                                .animation(.easeInOut, value: gmailSync.emailsProcessed)
                            
                            Text("\(gmailSync.emailsProcessed) de \(gmailSync.totalEmailsToProcess) correos procesados")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if !gmailSync.expensesFoundByBank.isEmpty {
                                Divider()
                                Text("Gastos identificados:")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                ForEach(Array(gmailSync.expensesFoundByBank.keys.sorted()), id: \.self) { bank in
                                    HStack {
                                        Text(bank)
                                        Spacer()
                                        Text("\(gmailSync.expensesFoundByBank[bank] ?? 0)")
                                            .fontWeight(.bold)
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    } else {
                        Button(action: {
                            gmailSync.modelContext = modelContext
                            gmailSync.syncEmails(force: true)
                        }) {
                            Label("Sincronizar Correos", systemImage: "envelope.arrow.triangle.branch")
                        }
                    }
                    
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
            Section(header: Text("Debug")) {
                Button(action: {
                    gmailSync.diagnosticYape()
                }) {
                    Label("Diagnóstico Yape", systemImage: "ladybug.fill")
                        .foregroundColor(.orange)
                }
            }
        }
        .navigationTitle("Configuración Online")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $gmailSync.showDiagnostic) {
            NavigationStack {
                ScrollView {
                    Text(gmailSync.diagnosticResult)
                        .padding()
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                .navigationTitle("Diagnóstico")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cerrar") {
                            gmailSync.showDiagnostic = false
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Lógica
    
    private func deleteClassifications() {
        UserDefaults.standard.removeObject(forKey: "merchantCategories")
        do {
            let descriptor = FetchDescriptor<Expense>()
            let expenses = try modelContext.fetch(descriptor)
            for expense in expenses {
                expense.category = "Sin Clasificar"
            }
            try modelContext.save()
        } catch {
            print("Error resetting classifications: \(error)")
        }
    }
    
    private func deleteExpenses() {
        gmailSync.resetSyncState()
        do {
            try modelContext.delete(model: Expense.self)
            try modelContext.save()
        } catch {
            print("Error al borrar los datos: \(error)")
        }
    }
    

}

#Preview {
    SettingsView()
        .modelContainer(for: Expense.self, inMemory: true)
}
