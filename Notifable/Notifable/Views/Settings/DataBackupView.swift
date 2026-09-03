import SwiftUI
import SwiftData

/// Datos y respaldo. El CSV vivía en una sección llamada "Funciones Online"
/// junto a dos toggles de IA que no hacían nada; las acciones destructivas
/// compartían sección con el diagnóstico BBVA, las dos en naranja.
struct DataBackupView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue

    @Query private var expenses: [Expense]
    @StateObject private var gmailSync = GmailSyncService.shared

    @State private var pendingAction: DestructiveAction?
    @State private var showDateRangeSheet = false
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()

    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .purple }
    private var palette: Palette { Palette(scheme) }

    enum DestructiveAction: String, Identifiable {
        case rules, expenses, cache
        var id: String { rawValue }
    }

    private var ruleCount: Int { MerchantRules.all().count }
    private var cachedEmailCount: Int {
        (UserDefaults.standard.stringArray(forKey: "processedEmailIDs") ?? []).count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                backupCard
                inventory
                dangerZone
                debugSection
            }
            .padding(.vertical, 16)
        }
        .background(palette.background)
        .navigationTitle("Datos y respaldo")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(dialogTitle,
                            isPresented: dialogBinding,
                            titleVisibility: .visible) {
            if let pendingAction {
                Button(confirmLabel(pendingAction), role: pendingAction == .cache ? .none : .destructive) {
                    perform(pendingAction)
                }
            }
            Button("Cancelar", role: .cancel) { pendingAction = nil }
        } message: {
            Text(pendingAction.map(consequence) ?? "")
        }
        .sheet(isPresented: $showDateRangeSheet) {
            dateRangeSheet
        }
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
                        Button("Cerrar") { gmailSync.showDiagnostic = false }
                    }
                }
            }
        }
    }

    // MARK: - Respaldo

    private var backupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.color.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: "icloud.and.arrow.up")
                        .foregroundStyle(accent.onSurface(scheme))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Respaldo en la nube")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.label)
                    Text("\(expenses.count) gastos en este dispositivo")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                secondaryButton("Respaldar ahora", icon: "arrow.triangle.2.circlepath") {
                    Task { await SyncManager.shared.syncLocalExpensesToCloud(localExpenses: expenses) }
                }
                secondaryButton("Exportar CSV", icon: "square.and.arrow.up") {
                    // TODO: Implement CSV Export
                }
            }
        }
        .padding(16)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(palette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }

    private func secondaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.label)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(palette.track)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Inventario

    /// El contexto que hace comprensible el bloque de abajo: sin saber cuántos
    /// gastos hay, "borrar todo" no significa nada.
    private var inventory: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EN ESTE DISPOSITIVO")
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                inventoryRow("Gastos", value: "\(expenses.count)")
                Rectangle().fill(palette.separator).frame(height: 0.5).padding(.leading, 16)
                inventoryRow("Reglas de categoría", value: "\(ruleCount)")
                Rectangle().fill(palette.separator).frame(height: 0.5).padding(.leading, 16)
                inventoryRow("Correos en caché", value: "\(cachedEmailCount)")
            }
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
        }
    }

    private func inventoryRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(palette.label)
            Spacer()
            Text(value).foregroundStyle(palette.secondaryLabel)
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
    }

    // MARK: - Acciones irreversibles

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ACCIONES IRREVERSIBLES")
                .font(.caption)
                .foregroundStyle(palette.negative)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                dangerRow(.rules, title: "Borrar reglas de categoría",
                          icon: "tag.slash.fill", tint: palette.negative)
                Rectangle().fill(palette.separator).frame(height: 0.5).padding(.leading, 16)
                dangerRow(.expenses, title: "Borrar todos los gastos",
                          icon: "trash.fill", tint: palette.negative)
                Rectangle().fill(palette.separator).frame(height: 0.5).padding(.leading, 16)
                
                customDangerRow(title: "Borrar rango de fechas", subtitle: "Elimina los gastos de un periodo para volver a descargarlos.", icon: "calendar.badge.minus", tint: palette.negative) {
                    showDateRangeSheet = true
                }
                Rectangle().fill(palette.separator).frame(height: 0.5).padding(.leading, 16)
                
                // Naranja y no rojo: vaciar la caché no borra datos.
                dangerRow(.cache, title: "Vaciar caché de correos",
                          icon: "arrow.triangle.2.circlepath", tint: palette.warning)
            }
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.negative.opacity(0.35), lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
    }

    private func dangerRow(_ action: DestructiveAction, title: String, icon: String, tint: Color) -> some View {
        Button { pendingAction = action } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(tint)
                    // La consecuencia con la cifra real, antes de tocar nada.
                    Text(consequence(action))
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func customDangerRow(title: String, subtitle: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(tint)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func consequence(_ action: DestructiveAction) -> String {
        switch action {
        case .rules:
            return "Los \(expenses.count) gastos pasan a \(Accounting.unclassified)."
        case .expenses:
            return "Se pueden volver a leer del correo. Las reglas se conservan."
        case .cache:
            return "La próxima lectura revisará todo de nuevo. No borra gastos."
        }
    }

    private func confirmLabel(_ action: DestructiveAction) -> String {
        switch action {
        case .rules: return "Borrar reglas"
        case .expenses: return "Borrar gastos"
        case .cache: return "Vaciar caché"
        }
    }

    private var dialogTitle: String {
        switch pendingAction {
        case .rules: return "¿Borrar las reglas de categoría?"
        case .expenses: return "¿Borrar todos los gastos?"
        case .cache: return "¿Vaciar la caché de correos?"
        case .none: return ""
        }
    }

    private var dialogBinding: Binding<Bool> {
        Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } })
    }

    private func perform(_ action: DestructiveAction) {
        switch action {
        case .rules: deleteClassifications()
        case .expenses: deleteExpenses()
        case .cache: gmailSync.resetSyncState()
        }
        pendingAction = nil
    }

    // MARK: - Debug

    @ViewBuilder
    private var debugSection: some View {
        #if DEBUG
        VStack(alignment: .leading, spacing: 8) {
            Text("DEBUG")
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                debugRow("Diagnóstico BBVA", icon: "stethoscope") { gmailSync.diagnosticBBVA() }
                Rectangle().fill(palette.separator).frame(height: 0.5).padding(.leading, 16)
                debugRow("Añadir gasto de prueba", icon: "dice", action: addRandomExpense)
            }
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 16)
        }
        #endif
    }

    #if DEBUG
    private func debugRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 24)
                Text(title)
                Spacer()
            }
            .foregroundStyle(palette.secondaryLabel)
            .padding(.horizontal, 16)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func addRandomExpense() {
        let options = [
            ("Apple Store", "Entretenimiento"),
            ("Starbucks", "Comida"),
            ("Uber", "Transporte"),
            ("Wong", "Supermercado"),
            ("Netflix", "Entretenimiento"),
            ("Oxxo 123", Accounting.unclassified)
        ]
        let selected = options.randomElement()!
        let days = Int.random(in: 0...20)
        let date = Period.calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        let expense = Expense(
            amount: Double.random(in: 10.0...150.0),
            merchant: selected.0,
            date: date,
            category: selected.1,
            isSubscription: selected.0 == "Netflix"
        )
        modelContext.insert(expense)
        try? modelContext.save()
    }
    #endif

    // MARK: - Lógica

    private func deleteClassifications() {
        UserDefaults.standard.removeObject(forKey: MerchantRules.key)
        do {
            let all = try modelContext.fetch(FetchDescriptor<Expense>())
            for expense in all {
                // Una sola fuente de verdad para esta cadena.
                expense.category = Accounting.unclassified
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

    private func deleteExpenses(from startDate: Date, to endDate: Date) {
        let startOfDay = Calendar.current.startOfDay(for: startDate)
        let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate
        
        do {
            let allExpenses = try modelContext.fetch(FetchDescriptor<Expense>())
            let expensesToDelete = allExpenses.filter { $0.date >= startOfDay && $0.date <= endOfDay }
            
            var emailIDsToRemove = Set<String>()
            
            for expense in expensesToDelete {
                if let emailID = expense.emailID {
                    emailIDsToRemove.insert(emailID)
                }
                modelContext.delete(expense)
            }
            
            try modelContext.save()
            
            if !emailIDsToRemove.isEmpty {
                var processedIDs = UserDefaults.standard.stringArray(forKey: "processedEmailIDs") ?? []
                processedIDs.removeAll { emailIDsToRemove.contains($0) }
                UserDefaults.standard.set(processedIDs, forKey: "processedEmailIDs")
                
                var pendingRecoveryIDs = UserDefaults.standard.stringArray(forKey: "pendingRecoveryIDs") ?? []
                pendingRecoveryIDs.removeAll { emailIDsToRemove.contains($0) }
                UserDefaults.standard.set(pendingRecoveryIDs, forKey: "pendingRecoveryIDs")
            }
            
        } catch {
            print("Error al borrar los datos por rango: \(error)")
        }
    }

    private var dateRangeSheet: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Desde", selection: $startDate, displayedComponents: .date)
                    DatePicker("Hasta", selection: $endDate, displayedComponents: .date)
                } header: {
                    Text("Rango de tiempo")
                } footer: {
                    Text("Se eliminarán los gastos dentro de este rango y sus correos asociados podrán ser descargados nuevamente en la próxima sincronización.")
                }
                
                Button(role: .destructive) {
                    deleteExpenses(from: startDate, to: endDate)
                    showDateRangeSheet = false
                } label: {
                    Text("Borrar gastos del rango")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("Borrar por fechas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { showDateRangeSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
