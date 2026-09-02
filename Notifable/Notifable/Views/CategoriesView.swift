import SwiftUI
import SwiftData
import Charts

enum CategoryTab: String, CaseIterable {
    case misCategorias = "Mis Categorías"
    case inbox = "Bandeja (Sin Clasificar)"
}

/// Un comercio de la Bandeja con sus gastos sin clasificar.
///
/// Antes esto era una tupla con etiquetas. El comprobador de tipos de Swift
/// tarda un tiempo exponencial en resolver tuplas etiquetadas dentro de cadenas
/// `map`/`sorted`, y acababa rindiéndose ("unable to type-check this expression
/// in reasonable time"). Un `struct` con tipos explícitos se resuelve al vuelo.
struct InboxGroup: Identifiable {
    let merchant: String
    let expenses: [Expense]
    let total: Double
    var id: String { merchant }
}

/// Una fila de "Mis Categorías". Mismo motivo que `InboxGroup`.
struct CategoryRow: Identifiable {
    let category: String
    let total: Double
    let merchants: [PeriodTotals.MerchantTotal]
    var id: String { category }
}


struct MerchantWrapper: Identifiable {
    let id: String
}

struct ToastNotification: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let targetTab: CategoryTab
    let targetID: String
    let systemImage: String
    let color: Color
}

struct CategoriesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Environment(\.colorScheme) var colorScheme
    
    @Binding var scrollOffset: CGFloat
    @Binding var scrollToTopTrigger: Bool
    
    @StateObject private var exchangeRateService = ExchangeRateService.shared
    
    /// El mismo `Period` que Resumen y Ritmo.
    @AppStorage("period") private var period = Period()
    
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.purple.rawValue
    
    var themeColor: Color { AppThemeColor(rawValue: appAccentColor)?.color ?? .purple }
    
    @State private var selectedTab: CategoryTab = .misCategorias
    @State private var selectedMerchantToCategorize: MerchantWrapper?
    @State private var selectedMerchantToUncategorize: (merchant: String, category: String)?
    @State private var expandedMerchants: Set<String> = []
    @State private var expandedCategories: Set<String> = []
    @State private var showPercentages: Bool = false
    @State private var activeToasts: [ToastNotification] = []
    @State private var highlightedID: String?
    @State private var searchText = ""
    @State private var selectedChartCategory: String?
    @Namespace private var animation
    
    // MARK: - Totales
    //
    // Todo viene de `Accounting.totals`: el mismo criterio y las mismas cifras
    // que Resumen. Antes esta vista sumaba `amount` mientras Resumen sumaba
    // `unpaidAmount`, y cada gasto en USD se convertía por separado antes de
    // sumar (ACCOUNTING.md §2 y §10).
    
    var totals: PeriodTotals {
        Accounting.totals(expenses: expenses,
                          incomes: [],
                          period: period,
                          usdToPen: exchangeRateService.usdToPenRate)
    }
    
    func dailySpent(for period: Period) -> [PeriodTotals.DayTotal] {
        Accounting.totals(expenses: expenses,
                          incomes: [],
                          period: period,
                          usdToPen: exchangeRateService.usdToPenRate).dailySpent
    }
    
    var filteredExpenses: [Expense] {
        expenses.filter { period.contains($0.date) }
    }
    
    var allCategories: [String] {
        let defaults = ["Comida", "Transporte", "Entretenimiento", "Supermercado", "Otros"]
        let existing = Set(expenses.map { $0.category }.filter { $0 != Accounting.unclassified })
        return Array(existing.union(defaults)).sorted()
    }
    
    /// Comercios sin clasificar del periodo, agrupados.
    var inboxGroups: [InboxGroup] {
        let totalByMerchant = merchantTotalsByName
        var grouped: [String: [Expense]] = [:]
        for expense in filteredExpenses where expense.category == Accounting.unclassified {
            grouped[expense.merchant, default: []].append(expense)
        }

        var result: [InboxGroup] = []
        result.reserveCapacity(grouped.count)
        for (merchant, items) in grouped {
            result.append(InboxGroup(merchant: merchant,
                                     expenses: items.sorted { $0.date > $1.date },
                                     total: totalByMerchant[merchant]?.total ?? 0))
        }
        return result.sorted { lhs, rhs in
            if lhs.expenses.count == rhs.expenses.count { return lhs.merchant < rhs.merchant }
            return lhs.expenses.count > rhs.expenses.count
        }
    }

    var filteredInboxGroups: [InboxGroup] {
        guard !searchText.isEmpty else { return inboxGroups }
        return inboxGroups.filter { $0.merchant.localizedCaseInsensitiveContains(searchText) }
    }

    /// Datos de la dona: todas las categorías del periodo, incluida Sin Clasificar.
    var chartTotals: [PeriodTotals.CategoryTotal] { totals.byCategory }

    private var merchantTotalsByName: [String: PeriodTotals.MerchantTotal] {
        var map: [String: PeriodTotals.MerchantTotal] = [:]
        for item in totals.byMerchant { map[item.merchant] = item }
        return map
    }

    /// Filas de "Mis Categorías": sin la bandeja, con sus comercios y las
    /// categorías vacías al final para poder asignarlas.
    var categoryTotals: [CategoryRow] {
        let totalByMerchant = merchantTotalsByName

        var merchantsByCategory: [String: Set<String>] = [:]
        for expense in filteredExpenses where expense.category != Accounting.unclassified {
            merchantsByCategory[expense.category, default: []].insert(expense.merchant)
        }

        var rows: [CategoryRow] = []
        for item in totals.byCategory where item.category != Accounting.unclassified {
            let names = merchantsByCategory[item.category] ?? []
            var merchants: [PeriodTotals.MerchantTotal] = []
            merchants.reserveCapacity(names.count)
            for name in names {
                if let merchant = totalByMerchant[name] { merchants.append(merchant) }
            }
            merchants.sort { lhs, rhs in
                let l = Money.cents(lhs.total)
                let r = Money.cents(rhs.total)
                return l == r ? lhs.merchant < rhs.merchant : l > r
            }
            rows.append(CategoryRow(category: item.category, total: item.total, merchants: merchants))
        }

        // Las categorías sin gasto en el periodo van al final, en gris.
        let existing = Set(rows.map(\.category))
        for category in allCategories where !existing.contains(category) {
            rows.append(CategoryRow(category: category, total: 0, merchants: []))
        }

        return rows.sorted { lhs, rhs in
            let l = Money.cents(lhs.total)
            let r = Money.cents(rhs.total)
            return l == r ? lhs.category < rhs.category : l > r
        }
    }


    var body: some View {
        ScrollViewReader { proxy in
            TrackableScrollView(scrollOffset: $scrollOffset, scrollToTopTrigger: $scrollToTopTrigger) {
                VStack(spacing: 24) {
                    // 1. Periodo: una sola fila, compartida con las otras pestañas.
                    PeriodHeader(period: $period, dailySpent: dailySpent(for:))
                        .id("TOP")
                    
                    // 2. Gráfico de Dona (sólo si estamos en Mis Categorías y hay datos)
                    if selectedTab == .misCategorias && !chartTotals.isEmpty {
                        donutChartView
                    }
                    
                    // 3. Segmented Picker (Mis Categorías vs Bandeja)
                    HStack(spacing: 0) {
                        ForEach([CategoryTab.misCategorias, CategoryTab.inbox], id: \.self) { tab in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedTab = tab
                                    
                                    // Scroll up smoothly if changing tabs to avoid broken layouts
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            proxy.scrollTo("TOP", anchor: .top)
                                        }
                                    }
                                }
                            } label: {
                                Text(tab.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(selectedTab == tab ? .semibold : .regular)
                                    .foregroundStyle(selectedTab == tab ? .white : (colorScheme == .dark ? .white : .black))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        ZStack {
                                            if selectedTab == tab {
                                                Capsule()
                                                    .fill(themeColor.opacity(0.8))
                                                    .shadow(color: themeColor.opacity(0.3), radius: 8, x: 0, y: 4)
                                                    .matchedGeometryEffect(id: "TAB", in: animation)
                                            }
                                        }
                                    )
                            }
                        }
                    }
                    .background(Color.primary.opacity(0.05))
                    .clipShape(Capsule())
                    .padding(.horizontal)
                    .padding(.bottom, -12) // Reduce the 24 spacing to 12
                    
                    // 4. Lista de Categorías o Bandeja
                    if selectedTab == .misCategorias {
                        misCategoriasListView
                    } else {
                        inboxView
                    }
                }
                .padding(.bottom, 100)
            }
            .overlay(alignment: .bottomTrailing) {
                // Toast Notifications flotantes (Apilados)
                VStack(alignment: .trailing, spacing: 10) {
                    ForEach(activeToasts) { toast in
                        Button(action: {
                            let targetTab = toast.targetTab
                            let targetID = toast.targetID
                            
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedTab = targetTab
                                activeToasts.removeAll { $0.id == toast.id }
                                
                                // Si vamos a Mis Categorías, expandir la categoría destino
                                if targetTab == .misCategorias {
                                    expandedCategories.insert(targetID)
                                }
                            }
                            
                            // Esperar a que cambie la pestaña y hacer scroll
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    proxy.scrollTo(targetID, anchor: .top)
                                }
                                withAnimation(.spring) {
                                    highlightedID = targetID
                                }
                                
                                // Quitar highlight después de unos segundos
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                    withAnimation(.easeOut) {
                                        if highlightedID == targetID {
                                            highlightedID = nil
                                        }
                                    }
                                }
                            }
                        }) {
                            HStack {
                                Image(systemName: toast.systemImage)
                                    .foregroundStyle(toast.color)
                                Text(toast.message)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(colorScheme == .light ? .black : .white)
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundStyle(.gray)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(colorScheme == .light ? Color.white : Color(UIColor.systemGray6))
                                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                            )
                        }
                        .buttonStyle(.plain)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, 110)
                .allowsHitTesting(!activeToasts.isEmpty)
            }
        }
        .onChange(of: scrollToTopTrigger) { _, _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = .misCategorias
                expandedCategories.removeAll()
                expandedMerchants.removeAll()
            }
        }
        .sheet(item: $selectedMerchantToCategorize) { wrapper in
            AssignCategoryView(merchant: wrapper.id, existingCategories: allCategories) { newCategory in
                let uncategorized = expenses.filter { $0.merchant == wrapper.id && $0.category == Accounting.unclassified }
                for expense in uncategorized {
                    expense.category = newCategory
                }
                try? modelContext.save()
                
                showToast(message: "Gastos de \(wrapper.id) movidos a \(newCategory)", tab: .misCategorias, id: newCategory, icon: "checkmark.circle.fill", color: .green)
            }
            .presentationDetents([.fraction(0.8)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
        }
        .alert("¿Desclasificar Gastos?", isPresented: Binding(
            get: { selectedMerchantToUncategorize != nil },
            set: { if !$0 { selectedMerchantToUncategorize = nil } }
        )) {
            Button("Cancelar", role: .cancel) {
                selectedMerchantToUncategorize = nil
            }
            Button("Desclasificar", role: .destructive) {
                if let target = selectedMerchantToUncategorize {
                    uncategorize(merchant: target.merchant, from: target.category)
                    selectedMerchantToUncategorize = nil
                }
            }
        } message: {
            if let target = selectedMerchantToUncategorize {
                Text("¿Estás seguro de que deseas enviar los gastos de \(target.merchant) a Sin Clasificar?")
            }
        }
    }
    
    // MARK: - Mis Categorías
    
    private func chartColor(for category: String) -> Color {
        switch category {
        case Accounting.unclassified: return .gray
        case "Comida": return .orange
        case "Transporte": return .blue
        case "Entretenimiento": return themeColor
        case "Supermercado": return .teal
        case "Otros": return .green
        default:
            // Generate a stable color from the category name hash
            let hash = abs(category.hashValue)
            let hue = Double(hash % 360) / 360.0
            return Color(hue: hue, saturation: 0.6, brightness: 0.8)
        }
    }
    
    private var donutChartView: some View {
        VStack {
            HStack {
                Text("Desglose")
                    .font(.headline)
                Spacer()
                
                if selectedChartCategory != nil {
                    Button {
                        withAnimation(.spring) {
                            selectedChartCategory = nil
                        }
                    } label: {
                        Text("Ver todo")
                            .font(.caption)
                            .foregroundStyle(themeColor)
                    }
                }
                
                Picker("Vista", selection: $showPercentages) {
                    Text("Moneda").tag(false)
                    Text("Porcentaje").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
            .padding(.bottom, 8)
            
            let grandTotal = totals.spent
            
            Chart(chartTotals, id: \.category) { item in
                SectorMark(
                    angle: .value("Total", item.total),
                    innerRadius: .ratio(0.6),
                    angularInset: 2.0
                )
                .cornerRadius(4)
                .foregroundStyle(chartColor(for: item.category))
                .opacity(selectedChartCategory == nil || selectedChartCategory == item.category ? 1.0 : 0.3)
                .annotation(position: .overlay) {
                    // `percent` devuelve nil si el total es cero: nunca "nan%".
                    let percentage = Money.percent(item.total, of: grandTotal) ?? 0
                    if percentage > 6.0 {
                        if showPercentages {
                            Text(Money.formatPercent(item.total, of: grandTotal))
                                .font(.caption2)
                                .fontWeight(.heavy)
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 1)
                                .shadow(color: .black.opacity(0.3), radius: 3)
                        } else {
                            Text(Money.formatCompact(item.total))
                                .font(.caption2)
                                .fontWeight(.heavy)
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 1)
                                .shadow(color: .black.opacity(0.3), radius: 3)
                        }
                    }
                }
            }
            .chartForegroundStyleScale(
                domain: chartTotals.map { $0.category },
                range: chartTotals.map { chartColor(for: $0.category) }
            )
            .chartLegend(position: .bottom, alignment: .center, spacing: 16)
            .frame(height: 250)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { location in
                            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                            let dx = location.x - center.x
                            let dy = location.y - center.y
                            var angle = atan2(dy, dx)
                            angle += .pi / 2
                            if angle < 0 {
                                angle += 2 * .pi
                            }
                            
                            let valueAtAngle = (angle / (2 * .pi)) * totals.spent
                            
                            withAnimation(.spring) {
                                let selected = findCategory(at: valueAtAngle)
                                if selectedChartCategory == selected {
                                    selectedChartCategory = nil
                                } else {
                                    selectedChartCategory = selected
                                    if let cat = selected {
                                        expandedCategories.insert(cat)
                                    }
                                }
                            }
                        }
                }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal)
    }
    
    private func findCategory(at value: Double) -> String? {
        var accumulatedTotal = 0.0
        for item in chartTotals {
            accumulatedTotal = Money.add(accumulatedTotal, item.total)
            if value <= accumulatedTotal {
                return item.category
            }
        }
        return nil
    }
    
    private var misCategoriasListView: some View {
        Group {
            if categoryTotals.isEmpty {
                ContentUnavailableView("No hay gastos", systemImage: "tray.fill", description: Text("Los gastos clasificados aparecerán aquí."))
            } else {
                VStack(spacing: 12) {
                    let displayedCategories = selectedChartCategory != nil ? categoryTotals.filter { $0.category == selectedChartCategory } : categoryTotals
                    ForEach(displayedCategories) { item in
                        categoryCard(for: item)
                    }
                    
                    // Relleno mínimo para que los últimos elementos sean scrolleables
                    if categoryTotals.count < 6 {
                        Color.clear
                            .frame(height: CGFloat(6 - categoryTotals.count) * 85)
                    }
                }
            }
        }
    }
    
    // MARK: - Bandeja (Inbox)
    private var inboxView: some View {
        Group {
            if inboxGroups.isEmpty {
                ContentUnavailableView("Bandeja Vacía", systemImage: "checkmark.circle.fill", description: Text("Todos tus gastos están clasificados."))
            } else {
                VStack(spacing: 12) {
                    // Barra de búsqueda para bandeja
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Buscar comercio sin clasificar...", text: $searchText)
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
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    
                    if filteredInboxGroups.isEmpty {
                        ContentUnavailableView("No se encontraron resultados", systemImage: "magnifyingglass", description: Text("Prueba con otro término de búsqueda."))
                    } else {
                        ForEach(filteredInboxGroups) { group in
                            inboxCard(for: group)
                        }
                    } // Cierra el else
                    
                    // Relleno mínimo para que los últimos elementos sean scrolleables en la bandeja
                    if filteredInboxGroups.count < 6 {
                        Color.clear
                            .frame(height: CGFloat(6 - filteredInboxGroups.count) * 85)
                    }
                }
                .padding(.top)
            }
        }
    }
    

    /// Una fila de categoría. Extraída del cuerpo de la lista: SwiftUI compone
    /// una única expresión gigante por vista, y pasado cierto tamaño el
    /// comprobador de tipos se rinde. Cada `func` es un punto de corte.
    @ViewBuilder
    private func categoryCard(for item: CategoryRow) -> some View {
        VStack(spacing: 0) {
            HStack {
                ZStack {
                    let baseColor = iconColor(for: item.category)
                    Circle()
                        .fill(colorScheme == .light ? baseColor : baseColor.opacity(0.2))
                        .frame(width: 40, height: 40)
                    Image(systemName: iconName(for: item.category))
                        .foregroundStyle(colorScheme == .light ? .white : baseColor)
                }
                
                Text(item.category)
                    .font(.headline)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Money.format(item.total))
                        .font(.subheadline)
                        .bold()
                        .foregroundStyle(.primary)
                }
                
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(expandedCategories.contains(item.category) ? 180 : 0))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
            }
            .padding()
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring) {
                    if expandedCategories.contains(item.category) {
                        expandedCategories.remove(item.category)
                    } else {
                        expandedCategories.insert(item.category)
                    }
                }
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                withAnimation(.spring) {
                    if expandedCategories.contains(item.category) {
                        expandedCategories.remove(item.category)
                    } else {
                        expandedCategories.insert(item.category)
                    }
                }
            }
            .opacity(Money.isZero(item.total) ? 0.4 : 1.0)
            
            if expandedCategories.contains(item.category) {
                VStack(spacing: 8) {
                    Divider().background(Color.primary.opacity(0.1))
                    
                    ForEach(item.merchants, id: \.merchant) { merchantItem in
                        HStack {
                            Text(Accounting.displayName(merchantItem.merchant))
                                .font(.caption)
                                .foregroundStyle(.primary)
                            
                            Spacer()
                            
                            Text(Money.format(merchantItem.total))
                                .font(.caption).bold()
                                .padding(.trailing, 8)
                            
                            Button(action: {
                                selectedMerchantToUncategorize = (merchant: merchantItem.merchant, category: item.category)
                            }) {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                                    .bold()
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .background(Color.red)
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .background(highlightedID == item.category ? themeColor.opacity(0.15) : Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
        .id(item.category)
    }

    /// Una tarjeta de comercio de la Bandeja.
    private func inboxCard(for group: InboxGroup) -> some View {
        let isWallet = group.merchant.hasPrefix("PLIN - ") || group.merchant.hasPrefix("YAPE - ")
        let circleFill: Color = isWallet ? Color.primary.opacity(0.1) : Color.gray.opacity(0.15)
        let circleShadow: Color = isWallet ? Color.primary.opacity(0.05) : Color.clear
        
        return VStack(spacing: 0) {
            HStack {
                ZStack {
                    Circle()
                        .fill(circleFill)
                        .frame(width: 40, height: 40)
                        .shadow(color: circleShadow, radius: 2)
                    
                    if group.merchant.hasPrefix("PLIN - ") {
                        Image("plin_icon")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 26, height: 26)
                            .clipShape(Circle())
                    } else if group.merchant.hasPrefix("YAPE - ") {
                        Image("yape_icon")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 26, height: 26)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "tray.fill")
                            .foregroundStyle(.gray)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(Accounting.displayName(group.merchant))
                        .font(.headline)
                    Text("\(group.expenses.count) transac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Right Side Grouping
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(Money.format(group.total))
                            .font(.subheadline).bold()
                        
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(expandedMerchants.contains(group.merchant) ? 180 : 0))
                            .foregroundStyle(.secondary)
                    }
                    
                    Button {
                        selectedMerchantToCategorize = MerchantWrapper(id: group.merchant)
                    } label: {
                        Text("Asignar")
                            .font(.caption).bold()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring) {
                    if expandedMerchants.contains(group.merchant) {
                        expandedMerchants.remove(group.merchant)
                    } else {
                        expandedMerchants.insert(group.merchant)
                    }
                }
            }
            
            if expandedMerchants.contains(group.merchant) {
                VStack(spacing: 8) {
                    Divider().background(Color.primary.opacity(0.1))
                    
                    ForEach(group.expenses) { expense in
                        HStack {
                            Text(expense.date, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(Money.format(expense.amount, currency: expense.currency))
                                .font(.caption).bold()
                                .foregroundStyle(expense.currency == "PEN" ? .primary : .green)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .padding()
        .background(highlightedID == group.merchant ? themeColor.opacity(0.15) : Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
        .id(group.merchant)
    }

    // MARK: - Helpers
    private func iconName(for category: String) -> String {
        switch category {
        case "Comida": return "fork.knife"
        case "Transporte": return "car.fill"
        case "Entretenimiento": return "play.tv.fill"
        default: return "bag.fill"
        }
    }
    private func iconColor(for category: String) -> Color {
        if category == Accounting.unclassified {
            return themeColor
        }
        switch category {
        case "Comida": return .orange
        case "Transporte": return .blue
        case "Entretenimiento": return themeColor
        default: return .green
        }
    }
    
    private func uncategorize(merchant: String, from category: String) {
        let expensesToUpdate = expenses.filter { $0.category == category && $0.merchant == merchant }
        for expense in expensesToUpdate {
            expense.category = Accounting.unclassified
        }
        try? modelContext.save()
        
        showToast(message: "Gastos de \(merchant) enviados a Sin Clasificar", tab: .inbox, id: merchant, icon: "tray.fill", color: .orange)
    }
    
    private func showToast(message: String, tab: CategoryTab, id: String, icon: String, color: Color) {
        let newToast = ToastNotification(message: message, targetTab: tab, targetID: id, systemImage: icon, color: color)
        
        withAnimation(.spring) {
            activeToasts.append(newToast)
        }
        
        // Auto-hide toast after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation(.easeInOut) {
                activeToasts.removeAll { $0.id == newToast.id }
            }
        }
    }
}

// Subvista para asignar la categoría
struct AssignCategoryView: View {
    let merchant: String
    let existingCategories: [String]
    var onAssign: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isDarkMode") private var isDarkMode = true
    @State private var searchText = ""
    @State private var isCreatingNew = false
    @State private var newCategoryName = ""
    
    var filteredCategories: [String] {
        if searchText.isEmpty {
            return existingCategories
        } else {
            return existingCategories.filter { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    @ViewBuilder
    private var contentList: some View {
        List {
            if isCreatingNew {
                Section(header: Text("Nueva Categoría")) {
                    TextField("Nombre de la categoría", text: $newCategoryName)
                    Button("Crear y Asignar") {
                        let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            onAssign(trimmed)
                            dismiss()
                        }
                    }
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .foregroundStyle(.blue)
                }
            } else {
                Section(header: Text("Crear")) {
                    Button {
                        withAnimation {
                            isCreatingNew = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Crear nueva categoría")
                        }
                    }
                }
                
                Section(header: Text("Asignar a \(merchant)")) {
                    ForEach(filteredCategories, id: \.self) { cat in
                        Button(cat) {
                            onAssign(cat)
                            dismiss()
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if existingCategories.count > 10 {
                    contentList
                        .searchable(text: $searchText, prompt: "Buscar categoría")
                } else {
                    contentList
                }
            }
            .navigationTitle(isCreatingNew ? "Nueva Categoría" : "Seleccionar Categoría")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        if isCreatingNew {
                            withAnimation {
                                isCreatingNew = false
                                newCategoryName = ""
                            }
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .preferredColorScheme(isDarkMode ? .dark : .light)
        }
    }
}

#Preview {
    CategoriesView(scrollOffset: .constant(100), scrollToTopTrigger: .constant(false))
        .modelContainer(for: [Expense.self, Income.self], inMemory: true)
}
