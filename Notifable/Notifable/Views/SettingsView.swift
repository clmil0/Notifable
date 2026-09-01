import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var expenses: [Expense]
    
    @State private var showDeleteClassificationsConfirmation = false
    @State private var showDeleteExpensesConfirmation = false
    @State private var showRecoveryAlert = false
    
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("syncFilters") private var syncFilters = true
    @AppStorage("isDarkMode") private var isDarkMode = true
    @AppStorage("syncBBVA") private var syncBBVA = true
    @AppStorage("syncBCP") private var syncBCP = true
    @AppStorage("syncYape") private var syncYape = true
    @AppStorage("syncInterbank") private var syncInterbank = true
    @AppStorage("syncScotiabank") private var syncScotiabank = true
    
    @AppStorage("cloudAIAnalysis") private var cloudAIAnalysis = true
    @AppStorage("cloudSocialFeed") private var cloudSocialFeed = false
    
    @StateObject private var gmailAuth = GmailAuthService.shared
    @StateObject private var gmailSync = GmailSyncService.shared
    
    @State private var syncStartDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var syncEndDate: Date = Date()
    @State private var showBankInfo: Bool = false
    @State private var bankInfoMessage: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Preferencias")) {
                    Toggle("Notificaciones de Presupuesto", isOn: $notificationsEnabled)
                        .tint(.purple)
                    
                    Toggle("Sincronizar filtros entre pestañas", isOn: $syncFilters)
                        .tint(.purple)
                    
                    Toggle("Modo Oscuro", isOn: $isDarkMode)
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
                    
                    Button(action: {
                        gmailSync.resetSyncState()
                    }) {
                        Label("Restaurar caché de sincronización", systemImage: "arrow.triangle.2.circlepath.doc.on.clipboard")
                    }
                    .foregroundStyle(.orange)
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
            .preferredColorScheme(isDarkMode ? .dark : .light)
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
            .alert("Recuperación de Gastos", isPresented: $showRecoveryAlert) {
                Button("Sí, recuperar") {
                    let recoveryIDs = UserDefaults.standard.stringArray(forKey: "pendingRecoveryIDs") ?? []
                    gmailSync.recoverExpenses(ids: recoveryIDs)
                }
                Button("No (Descartar)") {
                    UserDefaults.standard.removeObject(forKey: "pendingRecoveryIDs")
                    gmailSync.syncEmails(force: true)
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Has borrado elementos anteriores. ¿Quieres recuperarlos antes de continuar con la sincronización normal?")
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
                        if gmailSync.isSyncing {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Sincronizando... (\(gmailSync.emailsProcessed)/\(gmailSync.totalEmailsToProcess))")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            DatePicker("Desde", selection: $syncStartDate, displayedComponents: .date)
                            DatePicker("Hasta", selection: $syncEndDate, displayedComponents: .date)
                            
                            Button(action: {
                                gmailSync.modelContext = modelContext
                                let recoveryIDs = UserDefaults.standard.stringArray(forKey: "pendingRecoveryIDs") ?? []
                                if !recoveryIDs.isEmpty {
                                    showRecoveryAlert = true
                                } else {
                                    gmailSync.syncEmails(force: true, startDate: syncStartDate, endDate: syncEndDate)
                                }
                            }) {
                                Label("Sincronizar Correos", systemImage: "envelope.arrow.triangle.branch")
                            }
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
                Toggle(isOn: $syncBBVA) {
                    HStack {
                        Text("BBVA (Activo)")
                        Button(action: {
                            bankInfoMessage = "Detecta: Plin, Pagos Automáticos, Pagos con tarjeta en físico (contactless) y Pagos con tarjeta de crédito en línea."
                            showBankInfo = true
                        }) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }.tint(.blue)
                
                Toggle(isOn: $syncBCP) {
                    HStack {
                        Text("BCP")
                        Button(action: {
                            bankInfoMessage = "Detecta: Pagos con tarjeta y transferencias convencionales."
                            showBankInfo = true
                        }) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.orange)
                        }
                        .buttonStyle(.plain)
                    }
                }.tint(.orange)
                
                Toggle(isOn: $syncYape) {
                    HStack {
                        Text("Yape")
                        Button(action: {
                            bankInfoMessage = "Detecta: Yapeos convencionales recibidos y enviados."
                            showBankInfo = true
                        }) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.purple)
                        }
                        .buttonStyle(.plain)
                    }
                }.tint(.purple)
                
                Toggle(isOn: $syncInterbank) {
                    HStack {
                        Text("Interbank")
                        Button(action: {
                            bankInfoMessage = "Detecta: Pagos con tarjeta y transferencias."
                            showBankInfo = true
                        }) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.green)
                        }
                        .buttonStyle(.plain)
                    }
                }.tint(.green)
                
                Toggle(isOn: $syncScotiabank) {
                    HStack {
                        Text("Scotiabank")
                        Button(action: {
                            bankInfoMessage = "Detecta: Pagos con tarjeta y transferencias."
                            showBankInfo = true
                        }) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }.tint(.red)
            }
        }
        .navigationTitle("Sincronización Inicial")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Información del Banco", isPresented: $showBankInfo) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(bankInfoMessage)
        }
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
                    gmailSync.diagnosticBBVA()
                }) {
                    Label("Diagnóstico BBVA Pago", systemImage: "stethoscope")
                }
            }.foregroundColor(.orange)
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
