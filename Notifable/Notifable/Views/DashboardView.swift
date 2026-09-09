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

/// Envoltorio: resuelve el periodo guardado y las reglas recurrentes, y con
/// ambos decide **qué tramo del historial** hace falta cargar.
///
/// `@Query` se construye en el `init` y `@AppStorage` no se puede leer desde
/// ahí, así que la pantalla se parte en dos. Lo que se gana: la consulta deja
/// de traerse el historial completo —que con años de correo leído son decenas
/// de miles de objetos, con su relación `payments` resuelta uno a uno— y se
/// queda en el periodo visible. Al filtrar por año se cargará un año; antes se
/// cargaba todo igualmente.
struct DashboardView: View {
    /// Ajustes › Apariencia decide si tocar el nombre de un movimiento filtra
    /// Actividad Reciente por ese comercio, o abre el detalle igual que el
    /// resto de la fila.
    static let tapTitleFiltersKey = "activityTitleTapFilters"

    /// Lleva a la pestaña Categorías. Lo resuelve `ContentView`, que es quien
    /// tiene la pestaña seleccionada.
    var onOpenInbox: () -> Void = {}

    @Binding var scrollToTopTrigger: Bool

    @AppStorage("period") private var period = Period()
    @Query private var recurringRules: [RecurringExpense]

    /// El periodo visible **más** lo que necesita la deduplicación de
    /// recurrentes: si la ventana se quedara corta, un cobro del banco ya
    /// registrado no encontraría su ocurrencia y se anunciaría como pendiente
    /// estando cobrado.
    private var window: DateInterval {
        let visible = period.dataWindow()
        guard let recurring = RecurringEngine.matchWindow(rules: recurringRules) else { return visible }
        return DateInterval(start: min(visible.start, recurring.start),
                            end: max(visible.end, recurring.end))
    }

    var body: some View {
        DashboardContent(onOpenInbox: onOpenInbox,
                         period: $period,
                         scrollToTopTrigger: $scrollToTopTrigger,
                         recurringRules: recurringRules,
                         window: window)
    }
}

private struct DashboardContent: View {
    let onOpenInbox: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    /// Vienen del envoltorio, que ya los consultó para calcular la ventana.
    let recurringRules: [RecurringExpense]
    @Environment(\.colorScheme) var colorScheme

    @Binding var period: Period
    @Binding var scrollToTopTrigger: Bool

    @StateObject private var exchangeRateService = ExchangeRateService.shared

    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue
    @AppStorage(DashboardView.tapTitleFiltersKey) private var tapTitleFilters = true

    init(onOpenInbox: @escaping () -> Void,
         period: Binding<Period>,
         scrollToTopTrigger: Binding<Bool>,
         recurringRules: [RecurringExpense],
         window: DateInterval) {
        self.onOpenInbox = onOpenInbox
        self._period = period
        self._scrollToTopTrigger = scrollToTopTrigger
        self.recurringRules = recurringRules

        let start = window.start
        let end = window.end
        _expenses = Query(filter: #Predicate<Expense> { $0.date >= start && $0.date < end },
                          sort: \Expense.date, order: .reverse)
        _incomes = Query(filter: #Predicate<Income> { $0.date >= start && $0.date < end },
                         sort: \Income.date, order: .reverse)
    }
    
    var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .purple }
    var themeColor: Color { accent.color }

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
    @State private var showPendingSheet = false
    @State private var selectedIncomeForDetails: Income?
    /// La tira de ingresos filtra la actividad reciente a sólo ingresos.
    @State private var showsIncomesOnly = false

    /// Actividad Reciente pagina de 50 en 50 — cargar todo de una para un
    /// historial largo se siente lento y no aporta nada hasta que el usuario
    /// llega ahí abajo.
    @State private var visibleTransactionCount = 50
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
        period.filter(expenses, by: \.date)
    }
    
    var filteredIncomes: [Income] {
        period.filter(incomes, by: \.date)
    }
    
    /// - Note: aquí vivían `totalCombinedPEN`, `expensesByMerchant`,
    ///   `pagedTransactions`, `pendingCount` y `pendingTotal`. Se han quitado a
    ///   propósito: cada acceso rehacía un recorrido del periodo (o una
    ///   ordenación completa), y el cuerpo las leía varias veces por dibujado.
    ///   Ahora el cuerpo las resuelve una sola vez en locales. Si hace falta
    ///   alguna en una subvista, pásala como parámetro; no la reintroduzcas
    ///   como propiedad computada.
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

    /// Dispara la siguiente página cuando la fila que aparece está entre las
    /// últimas 10 visibles — antes de que el usuario llegue al final a secas,
    /// para que no note el salto.
    ///
    /// **Recibe la posición ya calculada.** Antes buscaba la fila con
    /// `pagedTransactions.firstIndex(where:)` y comparaba contra
    /// `searchedTransactions.count`: dos accesos a propiedades computadas que
    /// rehacían el `map` + la concatenación + **la ordenación completa** del
    /// periodo. Y esto corre en el `.onAppear` de cada fila, así que montar la
    /// lista costaba un centenar de ordenaciones del año entero.
    private func loadMoreIfNeeded(index: Int, pageCount: Int, totalCount: Int) {
        if index >= pageCount - 10, visibleTransactionCount < totalCount {
            visibleTransactionCount += 50
        }
    }

    var body: some View {
        // Todo lo caro, una sola vez por dibujado.
        //
        // `totals` es una propiedad computada que recorre el periodo entero, y
        // el cuerpo la leía ocho veces (la tarjeta, los dos banners, la tira de
        // ingresos y el gráfico, que la pide dos veces más). Igual la lista de
        // movimientos, que se ordenaba en cada acceso. Resolverlas aquí no
        // cambia la semántica —siguen recalculándose en cada dibujado, sin
        // caché que se pueda quedar rancia—, sólo deja de repetir el mismo
        // trabajo dentro del mismo dibujado.
        let totals = self.totals
        let topMerchants = Array(totals.byMerchant.prefix(5))
        let awaiting = pendingOccurrences.filter(\.isAwaiting)
        let pendingCount = awaiting.reduce(0) { $0 + $1.dates.count }
        let pendingTotal = Money.sum(awaiting) { $0.totalAmount }
        let transactions = searchedTransactions
        let paged = Array(transactions.prefix(visibleTransactionCount))

        return ZStack {
            TrackableScrollView(scrollToTopTrigger: $scrollToTopTrigger) {
                VStack(spacing: 24) {
                    
                    // Contenedor principal para no tapar el top header
                    VStack(spacing: 20) {
                        
                        // Una sola fila de periodo + scrubber de días.
                        PeriodHeader(period: $period, dailySpent: dailySpent(for:))
                        
                        // Tarjeta principal: el monto leído contra el
                        // presupuesto, con la marca de ritmo.
                        BudgetHeroCard(period: period, totals: totals)
                        
                        // Banner de recurrentes pendientes. Va antes que el de
                        // Bandeja porque afecta a las cifras del mes.
                        if pendingCount > 0 {
                            pendingBanner(count: pendingCount, total: pendingTotal)
                        }
                        
                        // Banner de Bandeja: sólo si hay comercios sin clasificar.
                        if totals.unclassifiedMerchantCount > 0 {
                            inboxBanner(totals: totals)
                        }
                        
                        // Tira de ingresos. Sólo si el usuario los registra.
                        IncomeStrip(totals: totals) {
                            withAnimation(.spring) { showsIncomesOnly.toggle() }
                        } onEnableIncome: {
                            tracksIncome = true
                        }
                        

                        if !topMerchants.isEmpty {
                            chartCard(merchants: topMerchants)
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
                            
                            if transactions.isEmpty {
                                Text(searchText.isEmpty ? "No hay transacciones en este período" : "No se encontraron resultados")
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 10)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            } else {
                                // `LazyVStack`, no `VStack`: con un `VStack` normal
                                // las 50 (y luego 100, 150…) filas cargadas se
                                // montaban y disponían TODAS en cada dibujado,
                                // aunque casi ninguna estuviera en pantalla. Con
                                // `LazyVStack` sólo se construyen las filas cerca
                                // del viewport, que es lo que hace que deslizar no
                                // se sienta más pesado a medida que la lista crece.
                                LazyVStack(spacing: 12) {
                                    ForEach(Array(paged.enumerated()), id: \.element.id) { index, item in
                                        transactionCard(for: item)
                                            .onAppear {
                                                loadMoreIfNeeded(index: index,
                                                                 pageCount: paged.count,
                                                                 totalCount: transactions.count)
                                            }
                                    }
                                }
                            }
                            
                            // Forzar espacio extra si hay pocos elementos (o 0) para que el teclado no los tape
                            if transactions.count < 6 {
                                Color.clear
                                    .frame(height: CGFloat(6 - transactions.count) * 85)
                            }
                        }
                        .padding(.top, 10)
                    }
                    .padding(.bottom, 100) // Padding extra para la Floating Bar solamente
                }
            }
        }
        .onChange(of: searchText) { _, _ in visibleTransactionCount = 50 }
        .onChange(of: period) { _, _ in visibleTransactionCount = 50 }
        .onChange(of: showsIncomesOnly) { _, _ in visibleTransactionCount = 50 }
        .sheet(item: $selectedExpenseForDetails) { expense in
            ExpenseDetailsView(expense: expense)
        }
        .sheet(item: $selectedIncomeForDetails) { income in
            IncomeDetailsView(income: income)
        }
        .sheet(isPresented: $showBudgetSheet) {
            BudgetSheet()
        }
        .sheet(isPresented: $showPendingSheet) {
            PendingConfirmationView()
        }
    }
    
    // MARK: - Subviews

    /// Ocurrencias vencidas de reglas recurrentes esperando confirmación.
    /// No existen como `Expense`, así que no están en ningún total: por eso hay
    /// que anunciarlas, o el mes se ve más barato de lo que es.
    private var pendingOccurrences: [PendingOccurrence] {
        RecurringEngine.pending(rules: recurringRules, expenses: expenses)
    }

    private func pendingBanner(count pendingCount: Int, total pendingTotal: Double) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.warning)
                    .frame(width: 36, height: 36)
                Image(systemName: "clock")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(pendingCount == 1 ? "1 gasto por confirmar" : "\(pendingCount) gastos por confirmar")
                    .font(.subheadline.bold())
                    .foregroundStyle(palette.label)
                Text(Money.format(pendingTotal) + " que aún no cuentan en tu mes")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
            }
            
            Spacer(minLength: 0)
            
            Button { showPendingSheet = true } label: {
                Text("Revisar")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(palette.warning)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(palette.warning.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.warning.opacity(0.4), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }

    /// La Bandeja es trabajo pendiente: se anuncia donde el usuario mira, no
    /// escondida en otra pestaña.
    private func inboxBanner(totals: PeriodTotals) -> some View {
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

    /// Temas pastel de dos colores: Acento 2 sólido, para que la barra
    /// contraste con el resto de la pantalla (que ya está en Acento 1). En
    /// temas de un color no hay segundo acento, así que la barra usa un
    /// degradado del mismo acento para no verse plana.
    private var topMerchantBarFill: AnyShapeStyle {
        if accent.isDuotone {
            return AnyShapeStyle(accent.secondaryColor)
        }
        return AnyShapeStyle(LinearGradient(colors: [accent.color, accent.color.opacity(0.45)],
                                             startPoint: .leading, endPoint: .trailing))
    }

    private func chartCard(merchants expensesByMerchant: [PeriodTotals.MerchantTotal]) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Top Movimientos")
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
                                .foregroundColor(accent.secondaryOnSurface(colorScheme))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        
                        GeometryReader { geo in
                            HStack(spacing: 12) {
                                // Barra horizontal delgada
                                let ratio = Money.ratio(item.total, to: maxTotal) ?? 0
                                let width = CGFloat(ratio) * (geo.size.width - 80) // 80pt reservados para el texto
                                
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(topMerchantBarFill)
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
    
    /// `@ViewBuilder`, no `AnyView`: el borrado de tipo de `AnyView` le quita a
    /// SwiftUI la identidad concreta de cada fila, y con cientos de filas en
    /// una `LazyVStack` eso le cuesta más diffing del que hace falta.
    @ViewBuilder
    private func transactionCard(for item: TransactionItem) -> some View {
        switch item {
        case .expense(let expense):
            expenseCard(for: expense)
        case .income(let income):
            incomeCard(for: income)
        }
    }
    
    /// Una fila de movimiento. Partida en piezas: los ternarios de color dentro
    /// de `.fill()` y `.background()` obligan al comprobador de tipos a probar
    /// todas las sobrecargas de ShapeStyle, y en una expresión larga se rinde.
    private func expenseCard(for expense: Expense) -> some View {
        HStack(spacing: 16) {
            expenseIcon(for: expense)
            expenseInfo(for: expense)

            Spacer()

            expenseAmount(for: expense)
        }
        .surfaceCard(radius: 16)
        .padding(.horizontal)
        .contentShape(Rectangle())
        .onTapGesture { selectedExpenseForDetails = expense }
    }

    @ViewBuilder
    private func expenseIcon(for expense: Expense) -> some View {
        let baseColor = iconColor(for: expense)
        let circleFill: Color = colorScheme == .light ? baseColor : baseColor.opacity(0.15)
        let symbolTint: Color = colorScheme == .light ? Color.white : baseColor
        let icon = iconName(for: expense)

        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle()
                    .fill(circleFill)
                    .frame(width: 48, height: 48)

                if icon == "plin_icon" || icon == "yape_icon" || icon == "bbva_icon" {
                    Image(icon)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                } else {
                    Image(systemName: icon)
                        .foregroundStyle(symbolTint)
                }
            }

            if expense.isDebt {
                badge(systemName: "exclamationmark", tint: .orange)
            } else if !(expense.payments ?? []).isEmpty {
                badge(systemName: "checkmark", tint: .green)
            }
        }
    }

    private func badge(systemName: String, tint: Color) -> some View {
        ZStack {
            Circle().fill(tint)
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 16, height: 16)
        .offset(x: 2, y: -2)
    }

    private func expenseInfo(for expense: Expense) -> some View {
        let baseColor = iconColor(for: expense)
        let tagBackground: Color = colorScheme == .light ? baseColor : baseColor.opacity(0.2)
        let tagForeground: Color = colorScheme == .light ? Color.white : baseColor
        let displayName = Accounting.displayName(expense.merchant)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    withAnimation {
                        if tapTitleFilters {
                            searchText = displayName
                        } else {
                            selectedExpenseForDetails = expense
                        }
                    }
                } label: {
                    Text(displayName)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(palette.label)
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
                    .background(tagBackground)
                    .foregroundStyle(tagForeground)
                    .clipShape(Capsule())

                Text(expense.date.formatted(.dateTime.day().month().hour().minute()))
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
    }

    /// Lo gastado es `amount`. Lo que aún debes es otra cifra y se muestra
    /// aparte, en vez de restarse del gasto (ACCOUNTING.md §2).
    /// En un gasto normal el número es lo que gastaste. En uno marcado "por
    /// cobrar" es **lo que falta que te devuelvan**: si prestaste 100 y ya te
    /// devolvieron 50, la fila dice 50, no 100. El original sigue visible
    /// debajo para no perder de dónde salió.
    ///
    /// (El total del mes sigue contando el gasto completo: lo que cambia aquí
    /// es qué cifra encabeza la fila, no la contabilidad.)
    @ViewBuilder
    private func expenseAmount(for expense: Expense) -> some View {
        let isReceivable = expense.isDebt
        let paid = Accounting.paid(of: expense)
        let outstanding = Accounting.outstanding(of: expense)
        let settled = isReceivable && Money.cents(outstanding) == 0
        // La fila enseña lo que el gasto **costó**, igual que el total del mes:
        // si te devolvieron algo, la cifra grande ya lo descuenta. Mostrar el
        // importe bruto aquí y el neto arriba dejaba una lista que no sumaba lo
        // que decía la cabecera.
        let hasRefunds = Money.cents(paid) > 0
        let displayed = (isReceivable || hasRefunds) ? outstanding : expense.amount

        VStack(alignment: .trailing, spacing: 2) {
            Text("- " + Money.format(displayed, currency: expense.currency))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(settled ? palette.secondaryLabel : palette.label)
                .strikethrough(settled, color: palette.secondaryLabel)

            if settled {
                Text("Saldada")
                    .font(.caption2)
                    .foregroundStyle(palette.positive)
            } else if hasRefunds {
                Text("de " + Money.format(expense.amount, currency: expense.currency)
                     + " · te devolvieron " + Money.format(paid, currency: expense.currency))
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryLabel)
            } else if isReceivable {
                Text("Por cobrar")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    
    private func incomeCard(for income: Income) -> some View {
        HStack(spacing: 16) {
            ZStack {
                let (baseColor, icon) = IncomeStyle.iconAndColor(for: income, accent: accent.incomeColor)

                Circle()
                    .fill(colorScheme == .light ? baseColor : baseColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                
                if icon == "plin_icon" || icon == "yape_icon" || icon == "bbva_icon" {
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
                            if tapTitleFilters {
                                searchText = income.source
                            } else {
                                selectedIncomeForDetails = income
                            }
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
                    let (baseColor, _) = IncomeStyle.iconAndColor(for: income, accent: accent.incomeColor)
                    let tagColor = isDebtPayment ? Color.orange : baseColor
                    let tagText = isDebtPayment ? "Cobro" : income.source
                    
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
                .foregroundStyle(isDebtPayment ? Color.orange : accent.incomeColor)
        }
        .surfaceCard(radius: 16)
        .padding(.horizontal)
        .contentShape(Rectangle())
        .onTapGesture { selectedIncomeForDetails = income }
    }
    
    // MARK: - Helpers
    private func iconName(for expense: Expense) -> String {
        if expense.merchant.hasPrefix("PLIN - ") { return "plin_icon" }
        if expense.merchant.hasPrefix("YAPE - ") { return "yape_icon" }
        if expense.merchant.hasPrefix("BBVA - ") { return "bbva_icon" }
        // Cubre las tres formas en que puede llegar: el recibo de Apple ya
        // vinculado ("Apple: <app>"), sin vincular todavía ("Apple: <app>",
        // ver handleExpenseInsertion) y el cargo suelto del banco antes de
        // que se una ("APPLE.COM/BILL" y similares).
        if expense.merchant.lowercased().contains("apple") { return "applelogo" }

        // Antes había aquí un `switch` con cuatro categorías fijas, así que
        // cambiar un gasto a una categoría propia —o cambiarle el icono en el
        // catálogo— no se reflejaba en esta lista aunque sí en el resto de la
        // app. `CategoryStyle` es el único que sabe de `CategoryCatalog`.
        return CategoryStyle.icon(for: expense.category)
    }
    
    private func iconColor(for expense: Expense) -> Color {
        if expense.merchant.hasPrefix("PLIN - ") { return Color(red: 0, green: 0.7, blue: 0.9) } // Celeste Plin
        if expense.merchant.hasPrefix("YAPE - ") { return Color(red: 0.5, green: 0, blue: 0.5) } // Magenta/Purple
        if expense.merchant.hasPrefix("BBVA - ") { return Color(red: 0.0, green: 0.27, blue: 0.51) } // Azul BBVA
        if expense.merchant.lowercased().contains("apple") { return colorScheme == .dark ? .white : .black }

        return CategoryStyle.color(for: expense.category, accent: themeColor)
    }
}

#Preview {
    DashboardView(scrollToTopTrigger: .constant(false))
        .modelContainer(for: [Expense.self, Income.self], inMemory: true)
}
