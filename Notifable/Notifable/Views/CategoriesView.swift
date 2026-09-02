import SwiftUI
import SwiftData
import Charts

enum CategoryTab: String, CaseIterable, Identifiable {
    var id: String { rawValue }

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

    /// Paleta con contraste verificado. Sustituye a `Color.primary.opacity(0.05)`,
    /// que en modo claro es #F2F2F2 sobre blanco: 4 % de diferencia de luminancia,
    /// invisible al sol o con el brillo bajo.
    private var palette: Palette { Palette(colorScheme) }
    
    /// En AppStorage, no en @State: el banner de Resumen necesita poder dejar
    /// la pestaña abierta en la Bandeja antes de navegar hasta aquí.
    @AppStorage("categoriesSegment") private var selectedTab: CategoryTab = .misCategorias
    @State private var selectedMerchantToCategorize: MerchantWrapper?
    @State private var selectedMerchantToUncategorize: (merchant: String, category: String)?
    @State private var expandedMerchants: Set<String> = []
    @State private var expandedCategories: Set<String> = []
    @State private var showPercentages: Bool = false
    @State private var activeToasts: [ToastNotification] = []
    @State private var highlightedID: String?
    @State private var searchText = ""
    @State private var selectedChartCategory: String?
    @State private var showClassifyFlow = false
    /// Aplicar una categoría es reversible: en vez de un alert previo, un toast
    /// con "Deshacer" durante unos segundos.
    @State private var pendingUndo: UndoToken?
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


    // MARK: - Bandeja

    /// Comercios distintos vistos alguna vez, y cuántos están ya clasificados.
    /// Se cuenta sobre todo el historial, no sobre el periodo: la Bandeja es una
    /// tarea pendiente, no una cifra del mes.
    var totalMerchantCount: Int {
        Set(expenses.map(\.merchant)).count
    }

    var classifiedMerchantCount: Int {
        let pending = Set(expenses.filter { $0.category == Accounting.unclassified }.map(\.merchant))
        return max(0, totalMerchantCount - pending.count)
    }

    /// Comercios pendientes de todo el historial, para el modo una-por-una.
    var pendingGroups: [InboxGroup] {
        let pending = expenses.filter { $0.category == Accounting.unclassified }
        var grouped: [String: [Expense]] = [:]
        for expense in pending { grouped[expense.merchant, default: []].append(expense) }

        let rate = exchangeRateService.usdToPenRate
        return grouped
            .map { merchant, items in
                let cents = items.reduce(0) { $0 + Accounting.penCents($1.accountingSnapshot, fallbackRate: rate) }
                return InboxGroup(merchant: merchant,
                                  expenses: items.sorted { $0.date > $1.date },
                                  total: Money.value(cents))
            }
            .sorted {
                $0.expenses.count == $1.expenses.count
                    ? $0.merchant < $1.merchant
                    : $0.expenses.count > $1.expenses.count
            }
    }

    func suggestion(for group: InboxGroup) -> CategorySuggestion? {
        SuggestionEngine.suggest(for: group.merchant,
                                 rules: MerchantRules.all(),
                                 history: expenses)
    }

    func frequentCategories(excluding suggestion: CategorySuggestion?) -> [String] {
        SuggestionEngine.frequentCategories(history: expenses, excluding: suggestion?.category)
    }

    @ViewBuilder
    private func merchantCard(for group: InboxGroup) -> some View {
        let hint = suggestion(for: group)
        InboxMerchantCard(
            group: group,
            suggestion: hint,
            frequentCategories: frequentCategories(excluding: hint),
            isExpanded: expandedMerchants.contains(group.merchant),
            isHighlighted: highlightedID == group.merchant,
            onToggle: { toggleMerchant(group.merchant) },
            onPick: { apply($0, to: group.merchant) },
            onOther: { selectedMerchantToCategorize = MerchantWrapper(id: group.merchant) }
        )
        .id(group.merchant)
    }

    private func toggleMerchant(_ merchant: String) {
        withAnimation(.spring) {
            if expandedMerchants.contains(merchant) {
                expandedMerchants.remove(merchant)
            } else {
                expandedMerchants.removeAll()      // sólo uno expandido a la vez
                expandedMerchants.insert(merchant)
            }
        }
    }

    /// Guarda la regla, reclasifica lo pasado y ofrece deshacer.
    func apply(_ category: String, to merchant: String) {
        let token = MerchantRules.apply(category, to: merchant, in: expenses)
        try? modelContext.save()

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            expandedMerchants.remove(merchant)
            pendingUndo = token
        }

        // El toast se retira solo a los 4 s, salvo que ya lo hayan deshecho.
        let id = token.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation(.easeInOut) {
                if pendingUndo?.id == id { pendingUndo = nil }
            }
        }
    }

    private func undoLastApply() {
        guard let token = pendingUndo else { return }
        withAnimation(.spring) {
            MerchantRules.undo(token, in: expenses)
            try? modelContext.save()
            pendingUndo = nil
        }
    }

    /// El toast de deshacer. Sin alert previo: aplicar es reversible.
    private var undoToast: some View {
        Group {
            if let token = pendingUndo {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(palette.positive)
                    Text(Accounting.displayName(token.merchant) + " → " + token.category)
                        .font(.subheadline)
                        .foregroundStyle(palette.label)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button("Deshacer") { undoLastApply() }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(themeColor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(palette.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(palette.hairline, lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
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
                    .background(palette.surface)
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
                                    .fill(palette.surfaceElevated)
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
        .overlay(alignment: .bottom) {
            undoToast
                .padding(.bottom, 110)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: pendingUndo)
        }
        .sheet(isPresented: $showClassifyFlow) {
            ClassifyFlowView(
                groups: pendingGroups,
                suggestion: { suggestion(for: $0) },
                frequentCategories: { frequentCategories(excluding: $0) },
                onPick: { group, category in apply(category, to: group.merchant) },
                onOther: { group in
                    showClassifyFlow = false
                    selectedMerchantToCategorize = MerchantWrapper(id: group.merchant)
                }
            )
        }
        .sheet(item: $selectedMerchantToCategorize) { wrapper in
            AssignCategoryView(merchant: wrapper.id, existingCategories: allCategories) { newCategory in
                // Misma ruta que los chips: guarda la regla y deja deshacer.
                apply(newCategory, to: wrapper.id)
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
            donutHeader
                .padding(.bottom, 8)

            donutChart
        }
        .surfaceCard(radius: 24)
        .padding(.horizontal)
    }

    private var donutHeader: some View {
        HStack {
            Text("Desglose")
                .font(.headline)
            Spacer()

            if selectedChartCategory != nil {
                Button {
                    withAnimation(.spring) { selectedChartCategory = nil }
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
    }

    private var donutChart: some View {
        let grandTotal = totals.spent
        let domain = chartTotals.map { $0.category }
        let range = chartTotals.map { chartColor(for: $0.category) }

        return Chart(chartTotals) { item in
            SectorMark(
                angle: .value("Total", item.total),
                innerRadius: .ratio(0.6),
                angularInset: 2.0
            )
            .cornerRadius(4)
            .foregroundStyle(chartColor(for: item.category))
            .opacity(sectorOpacity(for: item.category))
            .annotation(position: .overlay) {
                sectorLabel(for: item, of: grandTotal)
            }
        }
        .chartForegroundStyleScale(domain: domain, range: range)
        .chartLegend(position: .bottom, alignment: .center, spacing: 16)
        .frame(height: 250)
        .chartOverlay { _ in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        selectCategory(at: location, in: geometry.size)
                    }
            }
        }
    }

    private func sectorOpacity(for category: String) -> Double {
        guard let selected = selectedChartCategory else { return 1.0 }
        return selected == category ? 1.0 : 0.3
    }

    /// Etiqueta dentro del sector. `Money.percent` devuelve `nil` cuando el
    /// total es cero, así que nunca sale "nan%" (ACCOUNTING.md §13).
    @ViewBuilder
    private func sectorLabel(for item: PeriodTotals.CategoryTotal, of grandTotal: Double) -> some View {
        let percentage = Money.percent(item.total, of: grandTotal) ?? 0
        if percentage > 6.0 {
            Text(showPercentages
                 ? Money.formatPercent(item.total, of: grandTotal)
                 : Money.formatCompact(item.total))
                .font(.caption2)
                .fontWeight(.heavy)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 1)
                .shadow(color: .black.opacity(0.3), radius: 3)
        }
    }

    /// Traduce el punto tocado en la dona a la categoría de ese sector.
    private func selectCategory(at location: CGPoint, in size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = location.x - center.x
        let dy = location.y - center.y
        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += 2 * .pi }

        let valueAtAngle = (angle / (2 * .pi)) * totals.spent

        withAnimation(.spring) {
            let selected = findCategory(at: valueAtAngle)
            if selectedChartCategory == selected {
                selectedChartCategory = nil
            } else {
                selectedChartCategory = selected
                if let selected { expandedCategories.insert(selected) }
            }
        }
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
                    InboxProgressCard(classified: classifiedMerchantCount,
                                      total: totalMerchantCount) {
                        showClassifyFlow = true
                    }
                    .padding(.bottom, 4)
                    
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
                    .background(palette.surface)
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    
                    if filteredInboxGroups.isEmpty {
                        ContentUnavailableView("No se encontraron resultados", systemImage: "magnifyingglass", description: Text("Prueba con otro término de búsqueda."))
                    } else {
                        ForEach(filteredInboxGroups) { group in
                            merchantCard(for: group)
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
    

    /// Una fila de categoría, partida en piezas por el mismo motivo que la
    /// tarjeta de la Bandeja: el comprobador de tipos no termina una expresión
    /// de este tamaño.
    private func categoryCard(for item: CategoryRow) -> some View {
        let isExpanded = expandedCategories.contains(item.category)
        let background: Color = highlightedID == item.category
            ? themeColor.opacity(0.15)
            : palette.surface

        return VStack(spacing: 0) {
            categoryHeader(for: item, isExpanded: isExpanded)

            if isExpanded {
                categoryMerchants(for: item)
            }
        }
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
        .id(item.category)
    }

    private func categoryHeader(for item: CategoryRow, isExpanded: Bool) -> some View {
        let baseColor = iconColor(for: item.category)
        let isLight = colorScheme == .light
        let circleFill: Color = isLight ? baseColor : baseColor.opacity(0.2)
        let iconTint: Color = isLight ? Color.white : baseColor

        return HStack {
            ZStack {
                Circle()
                    .fill(circleFill)
                    .frame(width: 40, height: 40)
                Image(systemName: iconName(for: item.category))
                    .foregroundStyle(iconTint)
            }

            Text(item.category)
                .font(.headline)

            Spacer()

            Text(Money.format(item.total))
                .font(.subheadline)
                .bold()
                .foregroundStyle(.primary)

            Image(systemName: "chevron.down")
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
        }
        .padding()
        .contentShape(Rectangle())
        .onTapGesture { toggleCategory(item.category) }
        .onLongPressGesture(minimumDuration: 0.5) { toggleCategory(item.category) }
        .opacity(Money.isZero(item.total) ? 0.4 : 1.0)
    }

    private func categoryMerchants(for item: CategoryRow) -> some View {
        VStack(spacing: 8) {
            Divider().background(palette.separator)

            ForEach(item.merchants) { merchantItem in
                HStack {
                    Text(Accounting.displayName(merchantItem.merchant))
                        .font(.caption)
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(Money.format(merchantItem.total))
                        .font(.caption).bold()
                        .padding(.trailing, 8)

                    Button {
                        selectedMerchantToUncategorize = (merchant: merchantItem.merchant, category: item.category)
                    } label: {
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

    private func toggleCategory(_ category: String) {
        withAnimation(.spring) {
            if expandedCategories.contains(category) {
                expandedCategories.remove(category)
            } else {
                expandedCategories.insert(category)
            }
        }
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
        // Sin borrar la regla, el siguiente correo del comercio volvería a
        // clasificarse solo y el usuario no entendería por qué.
        MerchantRules.remove(merchant)
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
