import SwiftUI
import SwiftData

/// El dashboard único (`1b`): la pantalla de entrada de la app.
///
/// Sustituye a las tres pestañas. Arriba, cuánto llevas gastado en el mes y
/// contra el anterior; debajo, el gráfico de la semana contra la pasada; las
/// tiras de stats; la cuadrícula de accesos —Historial, Categorías,
/// Pendientes, Amigos—, y lo comprometido del mes. La lista de días ya no vive
/// aquí: está en Historial (Movimientos), a un toque.
///
/// El chip «Todas las cuentas» filtra **todo** lo de esta pantalla, y el
/// mismo filtro llega a Movimientos (`AccountFilter`).
struct DashboardView: View {
    /// Meses hacia atrás desde el actual. Vive en `DashboardScreen`: cambiarlo
    /// tiene que volver a construir las consultas.
    @Binding var monthOffset: Int
    let progress: ScrollProgress
    let onOpen: (AppSection) -> Void
    let onSettings: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme

    /// El mes mostrado y el anterior (o las seis semanas del gráfico, si
    /// arrancan antes), nada más.
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    /// Sólo si existe algo sin clasificar, de cualquier fecha.
    @Query private var anyUnclassified: [Expense]
    /// Lo marcado por cobrar: poco, y lo que dice la tarjeta de Amigos.
    @Query private var debtExpenses: [Expense]

    @StateObject private var rates = ExchangeRateService.shared
    @StateObject private var accountBook = AccountBook.shared
    @AppStorage(BudgetStore.monthlyBudgetKey) private var monthlyBudget = 0.0
    @AppStorage(BudgetStore.enabledKey) private var budgetEnabled = false

    @State private var filter = AccountFilter.shared
    @State private var social = SocialProfileStore.shared
    @State private var catalog: AccountCatalog?
    @State private var chartMode: SpendBarChart.Mode = .week
    @State private var selectedColumn: Int?
    @State private var openStat: StatDetail?
    @State private var scrollToTop = false

    private let month: Period

    init(monthOffset: Binding<Int>,
         progress: ScrollProgress,
         onOpen: @escaping (AppSection) -> Void,
         onSettings: @escaping () -> Void) {
        self._monthOffset = monthOffset
        self.progress = progress
        self.onOpen = onOpen
        self.onSettings = onSettings

        let shown = Self.month(offset: monthOffset.wrappedValue)
        self.month = shown
        // El mes anterior (para el delta del titular) o, si empiezan antes,
        // las seis semanas del gráfico en modo «Mes».
        let sixWeeks = Self.lastSixWeeks(endingAt: Self.referenceDay(for: shown,
                                                                      isCurrent: monthOffset.wrappedValue == 0))
        let start = min(shown.previous.interval.start, sixWeeks.first?.interval.start ?? .distantFuture)
        let end = shown.interval.end

        _expenses = Query(filter: #Predicate<Expense> { $0.date >= start && $0.date < end },
                          sort: \Expense.date, order: .reverse)
        _incomes = Query(filter: #Predicate<Income> { $0.date >= start && $0.date < end },
                         sort: \Income.date, order: .reverse)

        let unclassifiedName = Accounting.unclassified
        var anyDescriptor = FetchDescriptor<Expense>(predicate: #Predicate<Expense> {
            $0.category == unclassifiedName && !$0.isTransfer && !$0.isVoided && !$0.isReversal
        })
        anyDescriptor.fetchLimit = 1
        _anyUnclassified = Query(anyDescriptor)
        _debtExpenses = Query(filter: #Predicate<Expense> { $0.isDebt && !$0.isTransfer })
    }

    static func month(offset: Int) -> Period {
        var period = Period(granularity: .mes, reference: Date())
        for _ in 0..<max(0, offset) { period = period.previous }
        return period
    }

    private var palette: Palette { Palette(scheme) }
    private var accent: AppThemeColor { .current }
    private var rate: Double { rates.usdToPenRate }
    private var isCurrentMonth: Bool { monthOffset == 0 }

    // MARK: - Filtro de cuenta

    private var filteredExpenses: [Expense] {
        guard let account = filter.selection, let catalog else { return expenses }
        return expenses.filter { AccountFilter.matches($0, account: account, catalog: catalog) }
    }

    private var filteredIncomes: [Income] {
        guard let account = filter.selection, let catalog else { return incomes }
        return incomes.filter { AccountFilter.matches($0, account: account, catalog: catalog) }
    }

    /// Las cuentas marcadas como tuyas, en el orden del carrusel.
    private var accounts: [DetectedAccount] {
        guard let catalog else { return [] }
        return accountBook.preferences.carousel(from: catalog)
    }

    private var selectedAccountName: String {
        guard let key = filter.selection,
              let account = catalog?.accounts[key] else { return "Todas las cuentas" }
        return accountBook.preferences.name(for: account)
    }

    /// El catálogo necesita el historial entero —de él salen los alias de las
    /// tarjetas y a qué banco llega cada Plin—, así que se arma fuera del
    /// cuerpo y una sola vez por aparición, no en cada dibujado.
    private func loadCatalog() {
        let all = (try? modelContext.fetch(FetchDescriptor<Expense>())) ?? []
        let allIncomes = (try? modelContext.fetch(FetchDescriptor<Income>())) ?? []
        catalog = AccountCatalog(expenses: all, incomes: allIncomes)
        if let key = filter.selection, !accounts.contains(where: { $0.key == key }) {
            filter.selection = nil
        }
    }

    // MARK: - Cuerpo

    var body: some View {
        let expenses = filteredExpenses
        let incomes = filteredIncomes
        // Una sola conversión a snapshots por dibujado: cada `totals` sobre
        // los modelos volvía a convertirlos todos, y el gráfico de seis
        // semanas pedía seis.
        let snapshots = (expenses: expenses.map(\.accountingSnapshot),
                         incomes: incomes.map(\.accountingSnapshot))
        let totals = Accounting.totals(expenses: snapshots.expenses, incomes: snapshots.incomes,
                                       period: month, usdToPen: rate)
        let previous = Accounting.totals(expenses: snapshots.expenses, incomes: snapshots.incomes,
                                         period: month.previous, usdToPen: rate)
        let chart = chartColumns(snapshots.expenses, snapshots.incomes)

        ZStack(alignment: .top) {
            TrackableScrollView(scrollToTopTrigger: $scrollToTop) {
                VStack(alignment: .leading, spacing: 0) {
                    hero(totals: totals, previous: previous)
                        .padding(.bottom, 20)

                    chartBlock(chart)
                        .padding(.bottom, 30)

                    statsBlock(totals: totals, expenses: expenses)

                    grid(totals: totals, expenses: expenses, incomes: incomes)
                        .padding(.bottom, 28)

                    if isCurrentMonth {
                        CommittedSection(rate: rate)
                    }
                }
                .padding(.horizontal, ShellMetrics.sideInset)
                .padding(.top, ShellMetrics.contentTopInset)
                .padding(.bottom, 140)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                progress.update(offset)
            }

            header
        }
        .task { loadCatalog() }
        .onChange(of: self.expenses.count) { _, _ in loadCatalog() }
        .onChange(of: chartMode) { _, _ in selectedColumn = nil }
        .onChange(of: monthOffset) { _, _ in selectedColumn = nil }
        .sheet(item: $openStat) { StatSheet(stat: $0) }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            accountChip
            Spacer(minLength: 8)
            ShellCircleButton(icon: "slider.horizontal.3", label: "Configuración", action: onSettings)
        }
        .padding(.horizontal, ShellMetrics.sideInset)
        .frame(height: ShellMetrics.headerHeight)
        .background(ShellHeaderBackground(progress: progress))
    }

    private var accountChip: some View {
        Menu {
            Button {
                filter.selection = nil
            } label: {
                if filter.selection == nil {
                    Label("Todas las cuentas", systemImage: "checkmark")
                } else {
                    Text("Todas las cuentas")
                }
            }

            if !accounts.isEmpty {
                Divider()
                ForEach(accounts) { account in
                    let name = accountBook.preferences.name(for: account)
                    Button {
                        filter.selection = account.key
                    } label: {
                        if filter.selection == account.key {
                            Label(name, systemImage: "checkmark")
                        } else {
                            Text(account.digits.map { name + " ••" + $0 } ?? name)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: filter.selection == nil ? "building.columns.fill" : "creditcard.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent.onSurface(scheme))
                    .frame(width: 22, height: 22)
                    .background(accent.softFill(scheme), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                Text(selectedAccountName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.label)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.secondaryLabel)
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .frame(height: ShellMetrics.circleButton)
            .background(palette.surface, in: Capsule())
            .overlay(Capsule().stroke(palette.hairline, lineWidth: 0.5))
        }
        .accessibilityLabel("Cuenta: " + selectedAccountName)
    }

    // MARK: - Titular

    private var monthName: String {
        let name = Period.spanishMonthName(for: month.reference)
        let calendar = Period.calendar
        guard calendar.component(.year, from: month.reference) != calendar.component(.year, from: Date())
        else { return name }
        return name + " " + String(calendar.component(.year, from: month.reference))
    }

    private func hero(totals: PeriodTotals, previous: PeriodTotals) -> some View {
        let spent = totals.spent
        let isEmpty = Money.isZero(spent) && Money.isZero(totals.income)
        let formatted = Money.format(spent)
        // «S/ 2,612» grande y «.00» chico: los céntimos casi nunca importan y
        // a 46 pt se comían un tercio del ancho.
        let split = formatted.lastIndex(of: ".").map { (formatted[..<$0], formatted[$0...]) }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Gastado en " + monthName.lowercased())
                    .textCase(.uppercase)
                    .font(.system(size: 12.5, weight: .semibold))
                    .tracking(0.25)
                    .foregroundStyle(palette.secondaryLabel)

                Spacer(minLength: 8)

                // El pasado se navega desde aquí, un mes por toque.
                monthArrow("chevron.left", label: "Mes anterior") { monthOffset += 1 }
                monthArrow("chevron.right", label: "Mes siguiente", disabled: isCurrentMonth) {
                    monthOffset = max(0, monthOffset - 1)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(split.map { String($0.0) } ?? formatted)
                    .font(.system(size: 46, weight: .bold))
                    .tracking(-1.8)
                    .monospacedDigit()
                    .foregroundStyle(isEmpty ? palette.tertiaryLabel : palette.label)
                    .contentTransition(.numericText())
                if let cents = split?.1 {
                    Text(String(cents))
                        .font(.system(size: 18, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(palette.secondaryLabel)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Gasto de " + monthName + ": " + formatted)

            HStack(spacing: 10) {
                deltaChip(spent: spent, previous: previous.spent)

                if !isCurrentMonth {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { monthOffset = 0 }
                    } label: {
                        Text("Volver a este mes")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(accent.onSurface(scheme))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 2)
        .padding(.top, 4)
    }

    private func monthArrow(_ icon: String, label: String, disabled: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { action() }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(disabled ? palette.tertiaryLabel.opacity(0.5) : palette.secondaryLabel)
                .frame(width: 28, height: 28)
                .background(palette.surface, in: Circle())
                .overlay(Circle().stroke(palette.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    /// «↑ S/ 318 vs. agosto». Sin mes anterior con datos no hay comparación,
    /// y el chip no se dibuja en vez de inventar un «↑ 100 %».
    @ViewBuilder
    private func deltaChip(spent: Double, previous: Double) -> some View {
        let delta = Money.subtract(spent, previous)
        if !Money.isZero(previous), !Money.isZero(delta) {
            let isUp = Money.cents(delta) > 0
            HStack(spacing: 4) {
                Image(systemName: isUp ? "arrow.up" : "arrow.down")
                    .font(.system(size: 11, weight: .bold))
                Text(Money.formatCompact(abs(delta)) + " vs. "
                     + Period.spanishMonthName(for: month.previous.reference).lowercased())
                    .font(.system(size: 12.5, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(isUp ? palette.expenseText : palette.income)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(isUp ? palette.expenseSoft : palette.incomeSoft,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: - Gráfico

    private struct ChartData {
        let columns: [SpendBarChart.Column]
        let title: String
        let subtitle: String
        let defaultSelection: Int?
    }

    /// Hasta dónde llega el gráfico: hoy en el mes en curso; en un mes pasado,
    /// su último día.
    private var referenceDay: Date {
        Self.referenceDay(for: month, isCurrent: isCurrentMonth)
    }

    private static func referenceDay(for month: Period, isCurrent: Bool) -> Date {
        if isCurrent { return Date() }
        let end = month.interval.end
        return Period.calendar.date(byAdding: .day, value: -1, to: end) ?? end
    }

    /// Las seis semanas del modo «Mes», de la más antigua a la actual.
    private static func lastSixWeeks(endingAt day: Date) -> [Period] {
        var week = Period(granularity: .semana, reference: day)
        var result: [Period] = []
        for _ in 0..<6 {
            result.append(week)
            week = week.previous
        }
        return result.reversed()
    }

    private func chartColumns(_ expenses: [ExpenseSnapshot], _ incomes: [IncomeSnapshot]) -> ChartData {
        let calendar = Period.calendar
        let end = calendar.startOfDay(for: referenceDay)
        let spanish = Locale(identifier: "es_ES")

        switch chartMode {
        case .week:
            // Los últimos siete días, terminando en `end`: no la semana de
            // lunes a domingo, que el lunes sería una sola barra.
            let start = calendar.date(byAdding: .day, value: -6, to: end) ?? end
            let range = Period(granularity: .rango, reference: end, customStart: start, customEnd: end)
            let totals = Accounting.totals(expenses: expenses, incomes: incomes, period: range, usdToPen: rate)
            let letters = [1: "D", 2: "L", 3: "M", 4: "M", 5: "J", 6: "V", 7: "S"]
            let columns = range.days.enumerated().map { index, day in
                SpendBarChart.Column(
                    id: index,
                    label: letters[calendar.component(.weekday, from: day)] ?? "",
                    accessibilityLabel: day.formatted(.dateTime.weekday(.wide).day().locale(spanish)),
                    total: totals.dailySpent.first { calendar.isDate($0.date, inSameDayAs: day) }?.total ?? 0)
            }
            let count = totals.expenseCount
            return ChartData(columns: columns,
                             title: isCurrentMonth ? "Últimos 7 días" : "Últimos 7 días de " + monthName.lowercased(),
                             subtitle: Money.formatCompact(totals.spent) + " · "
                                + (count == 1 ? "1 movimiento" : "\(count) movimientos"),
                             defaultSelection: Self.defaultSelection(columns))

        case .month:
            let weeks = Self.lastSixWeeks(endingAt: end)
            var spent = 0.0
            var count = 0
            let columns = weeks.enumerated().map { index, week in
                let totals = Accounting.totals(expenses: expenses, incomes: incomes, period: week, usdToPen: rate)
                spent = Money.add(spent, totals.spent)
                count += totals.expenseCount
                let start = week.interval.start
                return SpendBarChart.Column(
                    id: index,
                    label: index == weeks.count - 1 && isCurrentMonth ? "Esta" : dayMonth(start),
                    accessibilityLabel: "Semana del " + dayMonth(start),
                    total: totals.spent)
            }
            return ChartData(columns: columns,
                             title: "Últimas 6 semanas",
                             subtitle: Money.formatCompact(spent) + " · "
                                + (count == 1 ? "1 movimiento" : "\(count) movimientos"),
                             defaultSelection: Self.defaultSelection(columns))
        }
    }

    /// La última barra con gasto; si no hubo ninguna, la última. Un «S/ 0»
    /// encima de la barra de hoy, a primera hora, no dice nada.
    private static func defaultSelection(_ columns: [SpendBarChart.Column]) -> Int? {
        columns.lastIndex { Money.cents($0.total) > 0 } ?? columns.indices.last
    }

    /// «15 set».
    private func dayMonth(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "es_ES")))
            .replacingOccurrences(of: ".", with: "")
    }

    private func chartBlock(_ chart: ChartData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(chart.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.label)
                    Text(chart.subtitle)
                        .font(.system(size: 12.5))
                        .monospacedDigit()
                        .foregroundStyle(palette.secondaryLabel)
                }

                Spacer(minLength: 8)

                CompactSegment(items: SpendBarChart.Mode.allCases, selection: $chartMode) { $0.rawValue }
            }

            SpendBarChart(columns: chart.columns,
                          selected: Binding(get: { selectedColumn ?? chart.defaultSelection },
                                            set: { selectedColumn = $0 }))
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Stats

    /// Tiras finas de etiqueta + cifra; el detalle se abre al tocarlas.
    ///
    /// Neto sólo con ingresos (sin ellos sería el gasto con signo cambiado) y
    /// Ritmo sólo con presupuesto: una tira vacía es ruido. El presupuesto es
    /// del mes entero, así que con una cuenta elegida Ritmo tampoco sale.
    @ViewBuilder
    private func statsBlock(totals: PeriodTotals, expenses: [Expense]) -> some View {
        let stats = self.stats(totals: totals, expenses: expenses)

        if !stats.isEmpty {
            ShellSectionHeader(title: monthName + " · Estadísticas")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(stats) { stat in
                        Button { openStat = stat } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(stat.title)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(palette.secondaryLabel)
                                Text(stat.stripValue)
                                    .font(.system(size: 19, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(stat.amountColor ?? palette.label)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .frame(minWidth: 68, maxWidth: 170, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(palette.hairline, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, ShellMetrics.sideInset)
                .padding(.bottom, 4)
            }
            .padding(.horizontal, -ShellMetrics.sideInset)
            .padding(.bottom, 30)
        }
    }

    private func stats(totals: PeriodTotals, expenses: [Expense]) -> [StatDetail] {
        var result: [StatDetail] = []

        if let balance = totals.balance {
            let positive = Money.cents(balance) >= 0
            let sign = positive ? "+" : "–"
            result.append(StatDetail(
                kind: .net,
                title: "Neto",
                amount: sign + Money.format(abs(balance)),
                amountColor: positive ? palette.income : palette.expenseText,
                detail: "La diferencia entre tus ingresos y tus gastos de " + monthName.lowercased() + ".",
                tiles: [("Ingresos", Money.formatCompact(totals.income)),
                        ("Gastos", Money.formatCompact(totals.spent))]))
        }

        if filter.selection == nil,
           let pace = BudgetStore.pace(monthlyBudget: monthlyBudget, enabled: budgetEnabled,
                                       for: month, spent: totals.spent) {
            result.append(StatDetail(
                kind: .pace,
                title: "Ritmo",
                amount: "\(pace.usedPercent)%",
                amountColor: pace.status == .over ? palette.expenseText : nil,
                detail: pace.message,
                tiles: [("Gastado", Money.formatCompact(pace.spent)),
                        ("Presupuesto", Money.formatCompact(pace.target))],
                pace: pace))
        }

        if Money.cents(totals.spent) > 0 {
            let pace = BudgetStore.pace(monthlyBudget: monthlyBudget, enabled: budgetEnabled,
                                        for: month, spent: totals.spent)
            let available = filter.selection == nil ? pace?.availablePerDay : nil
            let remainingDays = month.remainingDays
            result.append(StatDetail(
                kind: .perDay,
                title: "Por día",
                amount: Money.format(totals.averagePerDay),
                detail: "Tu gasto promedio diario en lo que va de " + monthName.lowercased() + ".",
                tiles: [("Promedio", Money.formatCompact(totals.averagePerDay)),
                        available.map { ("Disponible/día", Money.formatCompact($0)) }
                            ?? ("Quedan", remainingDays == 1 ? "1 día" : "\(remainingDays) días")]))
        }

        if let biggest = biggestExpense(in: expenses) {
            let cost = Accounting.netCostInPEN(biggest, fallbackRate: rate)
            let day = biggest.date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "es_ES")))
            result.append(StatDetail(
                kind: .biggest,
                title: "Mayor gasto",
                amount: Money.format(cost),
                detail: "Tu gasto más grande de " + monthName.lowercased() + ": "
                    + Accounting.displayName(biggest.merchant) + ", el " + day + ".",
                tiles: [("Comercio", Accounting.displayName(biggest.merchant)),
                        ("Del mes", Money.formatPercent(cost, of: totals.spent))],
                strip: Money.formatCompact(cost)))
        }

        if let top = totals.byMerchant.first, Money.cents(top.total) > 0 {
            let name = Accounting.displayName(top.merchant)
            result.append(StatDetail(
                kind: .topMerchant,
                title: "Comercio top",
                amount: name,
                detail: "Donde más gastaste en " + monthName.lowercased() + ", sumando todas tus compras ahí.",
                tiles: [("Total", Money.formatCompact(top.total)),
                        ("Compras", "\(top.count)")]))
        }

        return result
    }

    /// El gasto que más te costó en el mes mostrado. Lo mismo que cuenta en el
    /// total: sin traslados, anulaciones ni lo que ya te devolvieron.
    private func biggestExpense(in expenses: [Expense]) -> Expense? {
        let range = month.interval
        return expenses
            .filter { $0.countsAsSpending && $0.date >= range.start && $0.date < range.end }
            .max { Accounting.netCostInPEN($0, fallbackRate: rate) < Accounting.netCostInPEN($1, fallbackRate: rate) }
            .flatMap { Money.cents(Accounting.netCostInPEN($0, fallbackRate: rate)) > 0 ? $0 : nil }
    }

    // MARK: - Cuadrícula

    private func grid(totals: PeriodTotals, expenses: [Expense], incomes: [Income]) -> some View {
        let range = month.interval
        let movementCount = expenses.filter { !$0.isTransfer && $0.date >= range.start && $0.date < range.end }.count
            + incomes.filter { !$0.isTransfer && $0.date >= range.start && $0.date < range.end }.count
        let hasPending = totals.unclassifiedMerchantCount > 0 || !anyUnclassified.isEmpty

        return Grid(horizontalSpacing: 14, verticalSpacing: 14) {
            GridRow {
                tile(title: "Historial", action: { onOpen(.movements) }) {
                    bigNumber("\(movementCount)", caption: movementCount == 1 ? "movimiento" : "movimientos")
                }
                tile(title: "Categorías", action: { onOpen(.categories) }) {
                    topCategories(totals)
                }
            }
            GridRow {
                if hasPending {
                    tile(title: "Pendientes", action: { onOpen(.pending) }) {
                        let count = totals.unclassifiedMerchantCount
                        bigNumber("\(count)",
                                  caption: count == 0 ? "de meses anteriores" : "sin categoría",
                                  tint: count > 0 ? palette.expense : nil)
                    }
                } else {
                    tile(title: "Etiquetas", action: { onOpen(.tags) }) {
                        let used = Set(expenses.filter { $0.date >= range.start && $0.date < range.end }
                            .flatMap(\.tags)).count
                        bigNumber("\(used)", caption: used == 1 ? "usada este mes" : "usadas este mes")
                    }
                }
                tile(title: "Amigos", action: { onOpen(.social) }) {
                    friendsSummary
                }
            }
        }
    }

    private func tile<Content: View>(title: String, action: @escaping () -> Void,
                                     @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.label)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.secondaryLabel)
                }
                content()
                Spacer(minLength: 0)
            }
            .padding(15)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(minHeight: 128)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(palette.hairline, lineWidth: 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func bigNumber(_ value: String, caption: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 30, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint ?? palette.label)
            Text(caption)
                .font(.system(size: 13))
                .foregroundStyle(palette.secondaryLabel)
        }
    }

    @ViewBuilder
    private func topCategories(_ totals: PeriodTotals) -> some View {
        let top = totals.byCategory.filter { $0.category != Accounting.unclassified }.prefix(2)

        if top.isEmpty {
            Text(Money.cents(totals.spent) > 0 ? "Todo sin categoría" : "Sin gastos aún")
                .font(.system(size: 13))
                .foregroundStyle(palette.secondaryLabel)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(top)) { category in
                    HStack(spacing: 9) {
                        MovementIcon(icon: CategoryStyle.icon(for: category.category),
                                     color: CategoryStyle.color(for: category.category, accent: accent.color),
                                     size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(category.category)
                                .font(.system(size: 13.5))
                                .foregroundStyle(palette.label)
                                .lineLimit(1)
                            Text(Money.format(category.total))
                                .font(.system(size: 12))
                                .monospacedDigit()
                                .foregroundStyle(palette.secondaryLabel)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    /// El pingüino del perfil y lo que te deben: los gastos por cobrar que
    /// aún no te pagan del todo. Sin nada por cobrar, cuántos amigos tienes.
    private var friendsSummary: some View {
        let open = debtExpenses.filter { Money.cents(Accounting.outstanding(of: $0)) > 0 }
        let owed = Money.sum(open.map { Accounting.outstanding(of: $0) })
        let requests = FriendsManager.shared.incomingRequests.count + PaymentReminders.shared.inbox.count
        let friends = FriendsManager.shared.friends.count

        return HStack(spacing: 10) {
            PenguinAvatar(look: social.penguin, size: 52, background: accent.softFill(scheme))
                .overlay(alignment: .topTrailing) {
                    if requests > 0 {
                        Text(requests > 99 ? "99+" : "\(requests)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(palette.expense, in: Capsule())
                            .offset(x: 3, y: -2)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                if open.isEmpty {
                    Text(friends == 0 ? "Invita" : "\(friends)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.label)
                    Text(friends == 1 ? "amigo" : (friends == 0 ? "a un amigo" : "amigos"))
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondaryLabel)
                } else {
                    Text(Money.formatCompact(owed))
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(palette.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("te deben · " + (open.count == 1 ? "1 cobro" : "\(open.count) cobros"))
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private extension StatDetail {
    /// Lo que dice la tira: la cifra sin céntimos, que en 96 pt no caben.
    var stripValue: String {
        switch kind {
        case .net:
            return amount.replacingOccurrences(of: "S/ ", with: "")
                .components(separatedBy: ".").first ?? amount
        case .pace:
            return amount
        case .perDay:
            return tiles.first?.value ?? amount
        case .biggest, .topMerchant:
            return strip ?? amount
        }
    }
}

/// El dashboard con su mes. Guarda cuántos meses se retrocedió para que
/// `DashboardView` se reconstruya —con consultas del mes nuevo— al cambiarlo.
struct DashboardScreen: View {
    let progress: ScrollProgress
    let onOpen: (AppSection) -> Void
    let onSettings: () -> Void

    @State private var monthOffset = 0

    var body: some View {
        DashboardView(monthOffset: $monthOffset,
                      progress: progress,
                      onOpen: onOpen,
                      onSettings: onSettings)
    }
}
