import SwiftUI
import SwiftData

/// Configuración.
///
/// Antes eran seis `NavigationLink` idénticos con nombres que no decían qué
/// contenían ("Apariencia y Navegación", "Respaldo y Funciones Online"), ninguna
/// fila mostraba su valor, y el dato que sostiene la app —si la lectura de
/// correo funciona— estaba dos niveles adentro. Ahora: estado arriba, tres
/// secciones agrupadas por intención, y el valor de cada fila a la vista.
struct SettingsView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @Query private var expenses: [Expense]
    @Query private var recurringRules: [RecurringExpense]
    @Query private var quickExpenses: [QuickExpense]

    @StateObject private var gmailAuth = GmailAuthService.shared
    @StateObject private var gmailSync = GmailSyncService.shared

    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.dark.rawValue
    @AppStorage(BudgetStore.monthlyBudgetKey) private var monthlyBudget: Double = 0
    @AppStorage(BudgetStore.enabledKey) private var budgetEnabled = true
    // Se leen aquí para que la fila de la raíz se redibuje al cambiarlos dentro.
    @AppStorage(NotificationSettings.budgetKey) private var notifyBudget = true
    @AppStorage(NotificationSettings.recurringKey) private var notifyRecurring = true
    @AppStorage(NotificationSettings.debtEnabledKey) private var notifyDebt = true
    @AppStorage("syncBBVA") private var syncBBVA = true
    @AppStorage("syncBCP") private var syncBCP = true
    @AppStorage("syncYape") private var syncYape = true
    @AppStorage("syncInterbank") private var syncInterbank = true
    @AppStorage("syncScotiabank") private var syncScotiabank = true

    @State private var query = ""

    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .purple }
    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRaw) ?? .dark }
    private var palette: Palette { Palette(scheme) }

    /// Azul de "Captura automática": el color separa las secciones sin necesidad
    /// de leerlas.
    private var captureTint: Color {
        scheme == .dark ? Color(red: 0.392, green: 0.710, blue: 1.0)
                        : Color(red: 0.0, green: 0.349, blue: 0.698)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if query.isEmpty {
                        statusCard

                        moneySection
                        captureSection
                        appSection
                        versionFooter
                    } else {
                        searchResults
                    }
                }
                .padding(.vertical, 16)
            }
            .background(palette.background)
            .searchable(text: $query, prompt: "Buscar en configuración")
            .navigationTitle("Configuración")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                }
            }
            .appAppearance()
            .appTextSize()
        }
    }

    // MARK: - Estado

    private var status: SettingsStatus {
        SettingsStatus(
            isConnected: gmailAuth.isAuthenticated,
            account: gmailAuth.isAuthenticated ? "Sólo lectura del correo" : nil,
            lastSync: gmailSync.lastSyncDate,
            activeBankCount: BankSource.activeCount,
            totalBankCount: BankSource.all.count,
            expensesThisMonth: expensesThisMonth,
            unclassifiedMerchants: unclassifiedMerchantCount,
            pendingRecurring: 0
        )
    }

    private var expensesThisMonth: Int {
        let period = Period(granularity: .mes, reference: Date())
        return expenses.filter { period.contains($0.date) }.count
    }

    private var unclassifiedMerchantCount: Int {
        Set(expenses.filter { $0.category == Accounting.unclassified }.map(\.merchant)).count
    }

    /// La tarjeta entera lleva a Gmail y bancos, pero sólo cuando hay cuenta:
    /// sin conectar, el botón de dentro es la única acción y no debe quedar
    /// tapado por un enlace.
    @ViewBuilder
    private var statusCard: some View {
        if gmailAuth.isAuthenticated {
            NavigationLink {
                GmailBanksView()
            } label: {
                SettingsStatusCard(status: status, accent: accent.color) {}
            }
            .buttonStyle(.plain)
        } else {
            SettingsStatusCard(status: status, accent: accent.color) {
                gmailAuth.signIn()
            }
        }
    }

    // MARK: - Secciones

    private var moneySection: some View {
        SettingsSection(title: "Tu dinero") {
            SettingsRow(title: "Presupuesto", icon: "chart.bar.fill",
                        tint: accent.color, value: budgetValue) {
                BudgetScreen()
            }
            SettingsSeparator()
            SettingsRow(title: "Recurrentes y atajos", icon: "arrow.clockwise",
                        tint: accent.color, value: recurringValue) {
                RecurringManagementView()
            }
            SettingsSeparator()
            SettingsRow(title: "Categorías y reglas", icon: "tray.full.fill",
                        tint: accent.color, value: rulesValue) {
                CategoryRulesScreen()
            }
        }
    }

    private var captureSection: some View {
        SettingsSection(title: "Captura automática") {
            SettingsRow(title: "Gmail y bancos", icon: "building.columns.fill",
                        tint: captureTint, value: gmailValue) {
                GmailBanksView()
            }
            SettingsSeparator()
            SettingsRow(title: "Leer un rango pasado", icon: "calendar",
                        tint: captureTint, value: "Acción") {
                RangeSyncView()
            }
        }
    }

    private var appSection: some View {
        SettingsSection(title: "La app") {
            SettingsRow(title: "Apariencia", icon: "paintbrush.fill",
                        tint: .orange, value: appearance.rawValue, valueDot: accent.color) {
                AppearanceSettingsView()
            }
            SettingsSeparator()
            SettingsRow(title: "Notificaciones", icon: "bell.badge.fill",
                        tint: .orange, value: notificationsValue) {
                NotificationSettingsView()
            }
            SettingsSeparator()
            SettingsRow(title: "Datos y respaldo", icon: "externaldrive.fill",
                        tint: .gray, value: "\(expenses.count) gastos") {
                DataBackupView()
            }
        }
    }

    // MARK: - Valores de cada fila
    //
    // Ninguno queda vacío: "Sin definir" y "Ninguna" también son información.

    private var budgetValue: String {
        guard BudgetStore.hasBudget(monthlyBudget: monthlyBudget, enabled: budgetEnabled) else {
            return "Sin definir"
        }
        return Money.format(monthlyBudget)
    }

    private var recurringValue: String {
        let active = recurringRules.filter { !$0.isPaused }.count
        if active == 0 && quickExpenses.isEmpty { return "Ninguno" }
        if active == 0 { return "\(quickExpenses.count) atajos" }
        return active == 1 ? "1 activo" : "\(active) activos"
    }

    private var rulesValue: String {
        let count = MerchantRules.all().count
        if count == 0 { return "Ninguna" }
        return count == 1 ? "1 regla" : "\(count) reglas"
    }

    private var gmailValue: String {
        guard gmailAuth.isAuthenticated else { return "Sin conectar" }
        return BankSource.summaryLabel
    }

    private var notificationsValue: String {
        let count = NotificationSettings.activeCount()
        if count == 0 { return "Ninguna" }
        return count == 1 ? "1 activa" : "\(count) activas"
    }

    // MARK: - Búsqueda

    @ViewBuilder
    private var searchResults: some View {
        let results = SettingsEntry.matching(query)

        if results.isEmpty {
            ContentUnavailableView("Nada coincide con «\(query)»",
                                   systemImage: "magnifyingglass",
                                   description: Text("Prueba con otra palabra."))
                .padding(.top, 40)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                    searchRow(entry)
                    if index < results.count - 1 { SettingsSeparator() }
                }
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

    @ViewBuilder
    private func searchRow(_ entry: SettingsEntry) -> some View {
        NavigationLink {
            destination(for: entry.destination)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .foregroundStyle(palette.label)
                    // De dónde viene: sin esto, el resultado no dice dónde vive.
                    Text(entry.section)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.tertiaryLabel)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func destination(for id: String) -> some View {
        switch id {
        case "budget":        BudgetScreen()
        case "recurring":     RecurringManagementView()
        case "rules":         CategoryRulesScreen()
        case "gmail":         GmailBanksView()
        case "range":         RangeSyncView()
        case "appearance":    AppearanceSettingsView()
        case "notifications": NotificationSettingsView()
        default:              DataBackupView()
        }
    }

    // MARK: - Pie

    private var versionFooter: some View {
        Text("AgruPay 1.0 · PoC")
            .font(.caption)
            .foregroundStyle(palette.tertiaryLabel)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }
}

/// Presupuesto: aquí, en "Tu dinero", y no dentro de "Apariencia y Navegación",
/// que es donde estaba un ajuste financiero.
struct BudgetScreen: View {
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue

    var body: some View {
        Form {
            BudgetSettingsSection(tint: AppThemeColor(rawValue: appAccentColor)?.color ?? .purple)
        }
        .navigationTitle("Presupuesto")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Las reglas de comercio, que antes sólo se podían borrar desde "Gestión de
/// Datos Avanzada" y en bloque.
struct CategoryRulesScreen: View {

    @Environment(\.colorScheme) private var scheme
    @State private var rules: [String: String] = [:]

    private var palette: Palette { Palette(scheme) }

    private var sorted: [(merchant: String, category: String)] {
        rules.map { (merchant: $0.key, category: $0.value) }
            .sorted { $0.merchant.localizedCaseInsensitiveCompare($1.merchant) == .orderedAscending }
    }

    var body: some View {
        List {
            if sorted.isEmpty {
                Text("Todavía no has clasificado ningún comercio. Al asignarle una categoría a uno en la Bandeja, la regla aparece aquí.")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
            } else {
                Section {
                    ForEach(sorted, id: \.merchant) { rule in
                        HStack {
                            Text(Accounting.displayName(rule.merchant))
                                .lineLimit(1)
                            Spacer()
                            Text(rule.category)
                                .foregroundStyle(palette.secondaryLabel)
                        }
                    }
                    .onDelete(perform: delete)
                } footer: {
                    Text("Cada regla clasifica sola los movimientos futuros de ese comercio. Desliza para borrar una.")
                }
            }
        }
        .navigationTitle("Categorías y reglas")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { rules = MerchantRules.all() }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            MerchantRules.remove(sorted[index].merchant)
        }
        rules = MerchantRules.all()
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Expense.self, Income.self, RecurringExpense.self, QuickExpense.self],
                        inMemory: true)
}
