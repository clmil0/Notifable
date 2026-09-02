import SwiftUI
import SwiftData
import Charts

enum TransactionItem: Identifiable {
    case expense(Expense)
    case income(Income)
    
    var id: UUID {
        switch self {
        case .expense(let e): return e.id
        case .income(let i): return i.id
        }
    }
    
    var date: Date {
        switch self {
        case .expense(let e): return e.date
        case .income(let i): return i.date
        }
    }
}

struct DashboardView: View {
    /// Lleva a la pestaña Categorías. Lo resuelve `ContentView`, que es quien
    /// tiene la pestaña seleccionada.
    var onOpenInbox: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \Income.date, order: .reverse) private var incomes: [Income]
    @Environment(\.colorScheme) var colorScheme
    
    @Binding var scrollOffset: CGFloat
    @Binding var scrollToTopTrigger: Bool
    
    @StateObject private var exchangeRateService = ExchangeRateService.shared
    
    /// Un solo periodo para toda la app. Sustituye a `dashboardFilter` +
    /// `categoriesFilter` + `syncFilters` + tres `referenceDate` independientes.
    @AppStorage("period") private var period = Period()
    
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.purple.rawValue
    
    var themeColor: Color { AppThemeColor(rawValue: appAccentColor)?.color ?? .purple }

    /// Paleta con contraste verificado. Sustituye a `Color.primary.opacity(0.05)`,
    /// que en modo claro es #F2F2F2 sobre blanco: 4 % de diferencia de luminancia,
    /// invisible al sol o con el brillo bajo.
    private var palette: Palette { Palette(colorScheme) }
    
    @State private var searchText: String = ""
    
    @State private var isPressingTotalCombined = false
    @State private var isPressingTotalPEN = false
    @State private var isPressingTotalUSD = false
    
    @State private var selectedExpenseForDetails: Expense? = nil
    @State private var showBudgetSheet = false
    /// La tira de ingresos filtra la actividad reciente a sólo ingresos.
    @State private var showsIncomesOnly = false
    @AppStorage(BudgetStore.tracksIncomeKey) private var tracksIncome = true
    @AppStorage("categoriesSegment") private var categoriesSegment = CategoryTab.misCategorias
    
    // MARK: - Totales
    //
    // Única fuente de verdad: `Accounting.totals`. Antes esta vista sumaba
    // `unpaidAmount` mientras Categorías sumaba `amount`, así que el mismo mes
    // mostraba dos cifras distintas (ACCOUNTING.md §2). El filtrado por fecha
    // también vivía aquí duplicado, con el extremo derecho inclusivo (§1).
    
    var totals: PeriodTotals {
        Accounting.totals(expenses: expenses,
                          incomes: incomes,
                          period: period,
                          usdToPen: exchangeRateService.usdToPenRate)
    }
    
    func dailySpent(for period: Period) -> [PeriodTotals.DayTotal] {
        Accounting.totals(expenses: expenses,
                          incomes: incomes,
                          period: period,
                          usdToPen: exchangeRateService.usdToPenRate).dailySpent
    }
    
    var filteredExpenses: [Expense] {
        expenses.filter { period.contains($0.date) }
    }
    
    var filteredIncomes: [Income] {
        incomes.filter { period.contains($0.date) }
    }
    
    /// Gasto del periodo en soles.
    var totalCombinedPEN: Double { totals.spent }
    
    /// Ingreso del periodo, sin los abonos a deuda (ACCOUNTING.md §3).
    var totalCombinedIncomePEN: Double { totals.income }
    
    var expensesByMerchant: [PeriodTotals.MerchantTotal] {
        Array(totals.byMerchant.prefix(5))
    }

    var searchedTransactions: [TransactionItem] {
        let exps = showsIncomesOnly ? [] : filteredExpenses.map { TransactionItem.expense($0) }
        let incs = filteredIncomes.map { TransactionItem.income($0) }
        let allTransactions = (exps + incs).sorted { $0.date > $1.date }
        
        if searchText.isEmpty { return allTransactions }
        
        return allTransactions.filter { item in
            switch item {
            case .expense(let e):
                return e.merchant.localizedCaseInsensitiveContains(searchText) || e.category.localizedCaseInsensitiveContains(searchText)
            case .income(let i):
                let hasSourceMatch = i.source.localizedCaseInsensitiveContains(searchText)
                let hasNotesMatch = i.notes?.localizedCaseInsensitiveContains(searchText) ?? false
                let hasCategoryMatch = "Ingreso".localizedCaseInsensitiveContains(searchText)
                return hasSourceMatch || hasNotesMatch || hasCategoryMatch
            }
        }
    }

    var body: some View {
        ZStack {
            TrackableScrollView(scrollOffset: $scrollOffset, scrollToTopTrigger: $scrollToTopTrigger) {
                VStack(spacing: 24) {
                    
                    // Contenedor principal para no tapar el top header
                    VStack(spacing: 20) {
                        
                        // Una sola fila de periodo + scrubber de días.
                        PeriodHeader(period: $period, dailySpent: dailySpent(for:))
                        
                        // Tarjeta principal: el monto leído contra el
                        // presupuesto, con la marca de ritmo.
                        BudgetHeroCard(period: period, totals: totals) {
                            showBudgetSheet = true
                        }
                        
                        // Banner de Bandeja: sólo si hay comercios sin clasificar.
                        if totals.unclassifiedMerchantCount > 0 {
                            inboxBanner
                        }
                        
                        // Tira de ingresos. Sólo si el usuario los registra.
                        IncomeStrip(totals: totals) {
                            withAnimation(.spring) { showsIncomesOnly.toggle() }
                        } onEnableIncome: {
                            tracksIncome = true
                        }
                        

                        if !expensesByMerchant.isEmpty {
                            chartCard
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Actividad Reciente")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                
                                Spacer()
                                
                                // Al tocar la tira de ingresos la lista se filtra;
                                // el chip dice que hay un filtro puesto y lo quita.
                                if showsIncomesOnly {
                                    Button {
                                        withAnimation(.spring) { showsIncomesOnly = false }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text("Sólo ingresos")
                                            Image(systemName: "xmark")
                                        }
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(themeColor)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                            
                            // Barra de búsqueda por proximidad
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                TextField("Buscar por comercio...", text: $searchText)
                                    .disableAutocorrection(true)
                                
                                if !searchText.isEmpty {
                                    Button {
                                        withAnimation {
                                            searchText = ""
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(10)
                            .background(palette.surface)
                            .cornerRadius(10)
                            .padding(.horizontal)
                            
                            if searchedTransactions.isEmpty {
                                Text(searchText.isEmpty ? "No hay transacciones en este período" : "No se encontraron resultados")
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 10)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            } else {
                                ForEach(searchedTransactions) { item in
                                    transactionCard(for: item)
                                }
                            }
                            
                            // Forzar espacio extra si hay pocos elementos (o 0) para que el teclado no los tape
                            if searchedTransactions.count < 6 {
                                Color.clear
                                    .frame(height: CGFloat(6 - searchedTransactions.count) * 85)
                            }
                        }
                        .padding(.top, 10)
                    }
                    .padding(.bottom, 100) // Padding extra para la Floating Bar solamente
                }
            }
        }
        .sheet(item: $selectedExpenseForDetails) { expense in
            ExpenseDetailsView(expense: expense)
        }
        .sheet(isPresented: $showBudgetSheet) {
            BudgetSheet()
        }
    }
    
    // MARK: - Subviews

    /// La Bandeja es trabajo pendiente: se anuncia donde el usuario mira, no
    /// escondida en otra pestaña.
    private var inboxBanner: some View {
        let accent = AppThemeColor(rawValue: appAccentColor) ?? .purple
        let merchants = totals.unclassifiedMerchantCount
        
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.color)
                    .frame(width: 36, height: 36)
                Image(systemName: "tray.full.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(merchants == 1 ? "1 comercio sin clasificar" : "\(merchants) comercios sin clasificar")
                    .font(.subheadline.bold())
                    .foregroundStyle(palette.label)
                Text(Money.format(totals.unclassifiedTotal) + " sin categoría")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
            }
            
            Spacer(minLength: 0)
            
            Button {
                categoriesSegment = .inbox
                onOpenInbox()
            } label: {
                Text("Clasificar")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(accent.color)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(accent.softFill(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent.color.opacity(0.4), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Top Comercios")
                .font(.headline)
            
            let maxTotal = expensesByMerchant.map { $0.total }.max() ?? 0
            
            VStack(spacing: 16) {
                ForEach(expensesByMerchant, id: \.merchant) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        let displayName = Accounting.displayName(item.merchant)
                        
                        Button {
                            withAnimation {
                                searchText = displayName
                            }
                        } label: {
                            Text(displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.accentColor)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        
                        GeometryReader { geo in
                            HStack(spacing: 12) {
                                // Barra horizontal delgada
                                let ratio = Money.ratio(item.total, to: maxTotal) ?? 0
                                let width = CGFloat(ratio) * (geo.size.width - 80) // 80pt reservados para el texto
                                
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.accentColor.opacity(0.8))
                                    .frame(width: max(width, 4), height: 6) // Barra delgada
                                
                                // Valor a la derecha
                                Text(Money.format(item.total))
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                    .frame(width: 70, alignment: .leading)
                            }
                        }
                        .frame(height: 12)
                    }
                }
            }
            .padding(.top, 4)
        }
        .surfaceCard(radius: 24)
        .padding(.horizontal)
    }
    
    private func transactionCard(for item: TransactionItem) -> some View {
        switch item {
        case .expense(let expense):
            return AnyView(expenseCard(for: expense))
        case .income(let income):
            return AnyView(incomeCard(for: income))
        }
    }
    
    private func expenseCard(for expense: Expense) -> some View {
        HStack(spacing: 16) {
            ZStack(alignment: .topTrailing) {
                let baseColor = iconColor(for: expense)
                
                ZStack {
                    Circle()
                        .fill(colorScheme == .light ? baseColor : baseColor.opacity(0.15))
                        .frame(width: 48, height: 48)
                    
                    let icon = iconName(for: expense)
                    if icon == "plin_icon" || icon == "yape_icon" {
                        Image(icon)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: icon)
                            .foregroundStyle(colorScheme == .light ? .white : baseColor)
                    }
                }
                
                if expense.isDebt {
                    ZStack {
                        Circle()
                            .fill(Color.orange)
                        
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 16, height: 16)
                    .offset(x: 2, y: -2)
                } else if !(expense.payments ?? []).isEmpty {
                    ZStack {
                        Circle()
                            .fill(Color.green)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 16, height: 16)
                    .offset(x: 2, y: -2)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    let displayName = Accounting.displayName(expense.merchant)
                    
                    Button {
                        withAnimation {
                            searchText = displayName
                        }
                    } label: {
                        Text(displayName)
                            .font(.headline)
                            .lineLimit(1)
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    
                    if expense.isSubscription {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                            .foregroundStyle(themeColor)
                    }
                }
                
                HStack(spacing: 6) {
                    Text(expense.category)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(colorScheme == .light ? iconColor(for: expense) : iconColor(for: expense).opacity(0.2))
                        .foregroundStyle(colorScheme == .light ? .white : iconColor(for: expense))
                        .clipShape(Capsule())
                    
                    Text(expense.date.formatted(.dateTime.day().month().hour().minute()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
            
            Spacer()
            
            // Lo gastado es `amount`. Lo que aún debes es otra cifra y se
            // muestra aparte, en vez de restarse del gasto (ACCOUNTING.md §2).
            VStack(alignment: .trailing, spacing: 2) {
                Text("- " + Money.format(expense.amount, currency: expense.currency))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                
                if expense.isDebt {
                    let pending = Accounting.outstanding(of: expense)
                    Text("debes " + Money.format(pending, currency: expense.currency))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .surfaceCard(radius: 16)
        .padding(.horizontal)
        .contextMenu {
            Button {
                withAnimation {
                    expense.isDebt.toggle()
                    try? modelContext.save()
                    
                    // Actualizar las notificaciones de deudas
                    let descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.isDebt == true })
                    let hasDebts = (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
                    NotificationManager.shared.updateDebtNotification(hasDebts: hasDebts)
                    NotificationManager.shared.requestPermission()
                }
            } label: {
                Label(expense.isDebt ? "Desmarcar deuda" : "Marcar como deuda", systemImage: expense.isDebt ? "xmark.circle" : "exclamationmark.circle")
            }
            
            Button {
                selectedExpenseForDetails = expense
            } label: {
                Label("Detalles", systemImage: "info.circle")
            }
            
            Button(role: .destructive) {
                withAnimation {
                    if let emailID = expense.emailID {
                        var recoveryIDs = UserDefaults.standard.stringArray(forKey: "pendingRecoveryIDs") ?? []
                        if !recoveryIDs.contains(emailID) {
                            recoveryIDs.append(emailID)
                            UserDefaults.standard.set(recoveryIDs, forKey: "pendingRecoveryIDs")
                        }
                    }
                    modelContext.delete(expense)
                }
            } label: {
                Label("Eliminar", systemImage: "trash")
            }
        }
    }
    
    private func incomeCard(for income: Income) -> some View {
        HStack(spacing: 16) {
            ZStack {
                let (baseColor, icon) = incomeIconAndColor(for: income)
                
                Circle()
                    .fill(colorScheme == .light ? baseColor : baseColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                
                if icon == "plin_icon" || icon == "yape_icon" {
                    Image(icon)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                } else {
                    Image(systemName: icon)
                        .foregroundStyle(colorScheme == .light ? .white : baseColor)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    let displayTitle = income.title ?? income.source
                    Button {
                        withAnimation {
                            searchText = income.source
                        }
                    } label: {
                        Text(displayTitle)
                            .font(.headline)
                            .lineLimit(1)
                            .foregroundColor(income.isDebtPayment ? .orange : .primary)
                    }
                    .buttonStyle(.plain)
                }
                
                HStack(spacing: 6) {
                    let isDebtPayment = income.isDebtPayment
                    let (baseColor, _) = incomeIconAndColor(for: income)
                    let tagColor = isDebtPayment ? Color.orange : baseColor
                    let tagText = isDebtPayment ? "Deuda" : income.source
                    
                    Text(tagText)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(colorScheme == .light ? tagColor : tagColor.opacity(0.2))
                        .foregroundStyle(colorScheme == .light ? .white : tagColor)
                        .clipShape(Capsule())
                    
                    Text(income.date.formatted(.dateTime.day().month().hour().minute()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
            
            Spacer()
            
            let isDebtPayment = income.isDebtPayment
            Text(Money.format(income.amount, currency: income.currency))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(isDebtPayment ? Color.orange : .green)
        }
        .surfaceCard(radius: 16)
        .padding(.horizontal)
        .contextMenu {
            Button(role: .destructive) {
                withAnimation {
                    modelContext.delete(income)
                }
            } label: {
                Label("Eliminar", systemImage: "trash")
            }
        }
    }
    
    // MARK: - Helpers
    private func iconName(for expense: Expense) -> String {
        if expense.category == "Sin Clasificar" {
            if expense.merchant.hasPrefix("PLIN - ") { return "plin_icon" }
            if expense.merchant.hasPrefix("YAPE - ") { return "yape_icon" }
        }
        switch expense.category {
        case "Comida": return "fork.knife"
        case "Transporte": return "car.fill"
        case "Entretenimiento": return "play.tv.fill"
        default: return "bag.fill"
        }
    }
    
    private func iconColor(for expense: Expense) -> Color {
        if expense.category == "Sin Clasificar" {
            if expense.merchant.hasPrefix("PLIN - ") { return Color(red: 0, green: 0.7, blue: 0.9) } // Celeste Plin
            if expense.merchant.hasPrefix("YAPE - ") { return Color(red: 0.5, green: 0, blue: 0.5) } // Magenta/Purple
        }
        switch expense.category {
        case "Comida": return .orange
        case "Transporte": return .blue
        case "Entretenimiento": return themeColor
        default: return .green
        }
    }
    
    private func incomeIconAndColor(for income: Income) -> (Color, String) {
        switch income.source {
        case "Plin":
            return (Color(red: 0, green: 0.7, blue: 0.9), "plin_icon")
        case "Yape":
            return (Color(red: 0.5, green: 0, blue: 0.5), "yape_icon")
        case "Efectivo":
            return (.yellow, "banknote.fill")
        default:
            return (.green, "arrow.down.left.circle.fill")
        }
    }
}

#Preview {
    DashboardView(scrollOffset: .constant(100), scrollToTopTrigger: .constant(false))
        .modelContainer(for: [Expense.self, Income.self], inMemory: true)
}
