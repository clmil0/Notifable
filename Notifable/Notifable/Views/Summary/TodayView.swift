import SwiftUI
import SwiftData

/// Resumen › Hoy: la pantalla de entrada del rediseño (`1b`).
///
/// Responde una sola pregunta —«¿cuánto llevo?»— y por eso no tiene filtros,
/// ni gráficos, ni top de comercios. Tres niveles de información y una lista:
/// el monto del mes, el chip del mes con su delta, la línea de ingresos, y los
/// días agrupados de más reciente a más antiguo.
///
/// El pasado **se navega**: el scroll va revelando días anteriores. No hay
/// selector de fecha en ningún sitio de esta pestaña; el periodo vive sólo en
/// Análisis › Historial.
struct TodayView: View {
    @Binding var scrollToTopTrigger: Bool
    let progress: ScrollProgress
    /// Meses hacia atrás desde el actual. Vive en `TodayScreen` y no aquí:
    /// cambiarlo tiene que volver a construir las consultas, y eso sólo pasa
    /// si el `init` se vuelve a llamar con otro valor.
    @Binding var monthOffset: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme

    /// **Sólo el mes en curso y el anterior.**
    ///
    /// Antes estas dos consultas no llevaban predicado: se traían el historial
    /// entero —con años de correo leído, decenas de miles de objetos y su
    /// relación `payments` resuelta uno a uno— para dibujar el mes actual. Eso
    /// era lo que hacía que la pantalla de entrada de la app fuera la más
    /// lenta de todas.
    ///
    /// El mes anterior entra porque el chip necesita compararse con él; nada
    /// más allá se carga aquí. Para mirar atrás están Movimientos (la lista
    /// completa) e Historial (el periodo).
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @StateObject private var rates = ExchangeRateService.shared

    init(scrollToTopTrigger: Binding<Bool>, progress: ScrollProgress, monthOffset: Binding<Int>) {
        self._scrollToTopTrigger = scrollToTopTrigger
        self.progress = progress
        self._monthOffset = monthOffset

        let shown = Self.month(offset: monthOffset.wrappedValue)
        self.month = shown
        let start = shown.previous.interval.start
        let end = shown.interval.end

        _expenses = Query(filter: #Predicate<Expense> { $0.date >= start && $0.date < end },
                          sort: \Expense.date, order: .reverse)
        _incomes = Query(filter: #Predicate<Income> { $0.date >= start && $0.date < end },
                         sort: \Income.date, order: .reverse)
    }

    @State private var showsBalanceInstead = false
    @State private var social = SocialProfileStore.shared
    @State private var selectedExpense: Expense?
    @State private var selectedIncome: Income?
    @State private var expenseToCategorize: Expense?

    private var palette: Palette { Palette(scheme) }
    private var accent: AppThemeColor { .current }
    private var rate: Double { rates.usdToPenRate }

    // MARK: - Datos

    /// El mes mostrado: el de hoy, o uno anterior si se retrocedió con la
    /// flecha del chip.
    private let month: Period

    private var isCurrentMonth: Bool { monthOffset == 0 }

    static func month(offset: Int) -> Period {
        var period = Period(granularity: .mes, reference: Date())
        for _ in 0..<max(0, offset) { period = period.previous }
        return period
    }

    private var totals: PeriodTotals {
        Accounting.totals(expenses: expenses, incomes: incomes, period: month, usdToPen: rate)
    }

    private var previousTotals: PeriodTotals {
        Accounting.totals(expenses: expenses, incomes: incomes, period: month.previous, usdToPen: rate)
    }

    /// Los días **del mes en curso** con movimiento, del más reciente al más
    /// antiguo. Un mes son 31 días como mucho, así que no hay paginación que
    /// hacer: la lista entera cabe y montarla cuesta un recorrido.
    private func dayGroups() -> [DayGroup] {
        let calendar = Calendar.current
        let range = month.interval
        var buckets: [Date: [TransactionItem]] = [:]

        for expense in expenses where expense.date >= range.start && expense.date < range.end {
            buckets[calendar.startOfDay(for: expense.date), default: []].append(.expense(expense))
        }
        for income in incomes where income.date >= range.start && income.date < range.end {
            buckets[calendar.startOfDay(for: income.date), default: []].append(.income(income))
        }

        return buckets.keys.sorted(by: >).map { day in
            let items = (buckets[day] ?? []).sorted { $0.date > $1.date }
            let spent = Money.sum(items.compactMap { item -> Double? in
                guard case .expense(let e) = item else { return nil }
                return Accounting.amountInPEN(e, fallbackRate: rate)
            })
            return DayGroup(day: day, items: items, spent: spent)
        }
    }

    // MARK: - Cuerpo

    var body: some View {
        // Todo lo caro, una sola vez por dibujado. `previousTotals` se leía
        // desde dentro del chip, así que recorría el periodo otra vez en cada
        // pasada del cuerpo.
        let groups = dayGroups()
        let totals = self.totals
        let previousSpent = previousTotals.spent

        TrackableScrollView(scrollToTopTrigger: $scrollToTopTrigger) {
            VStack(spacing: 0) {
                hero(totals: totals, previousSpent: previousSpent)

                Rectangle()
                    .fill(palette.separator)
                    .frame(height: 0.5)
                    .padding(.bottom, 14)

                if groups.isEmpty {
                    emptyMonth
                } else {
                    // El mes sigue con su monto; sólo el bloque del día queda
                    // vacío (`1c`). Sin esto, la lista arrancaba en «Ayer» y
                    // parecía que hoy no existía.
                    if isCurrentMonth,
                       !groups.contains(where: { Calendar.current.isDateInToday($0.day) }) {
                        emptyToday
                            .padding(.bottom, 18)
                    }

                    ForEach(groups) { group in
                        daySection(group)
                            .padding(.bottom, 18)
                    }

                    monthFooter
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, ShellMetrics.contentTopInset)
            .padding(.bottom, ShellMetrics.contentBottomInset)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            progress.update(offset)
        }
        .sheet(item: $selectedExpense) { ExpenseDetailsView(expense: $0) }
        .sheet(item: $selectedIncome) { IncomeDetailsView(income: $0) }
        .sheet(item: $expenseToCategorize) { expense in
            // El historial completo, no `expenses`: una regla de comercio debe
            // alcanzar también a lo que quedó fuera de los días montados.
            let history = (try? modelContext.fetch(FetchDescriptor<Expense>())) ?? expenses
            AssignCategorySheet(context: .expense(expense), history: history) { newCategory, createRule in
                expense.category = newCategory
                ExpenseEditStore.record(expense, category: newCategory)
                if createRule { MerchantRules.set(newCategory, for: expense.merchant) }
                try? modelContext.save()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
    }

    // MARK: - Titular

    /// El monto grande, el chip del mes y la línea de ingresos.
    ///
    /// Tocar el monto alterna entre gasto del mes y balance (ingresos −
    /// gastos): son las dos lecturas que compiten por ese sitio, y en vez de
    /// poner las dos —lo que obligaba a encoger ambas— se turnan.
    @ViewBuilder
    private func hero(totals: PeriodTotals, previousSpent: Double) -> some View {
        let spent = totals.spent
        let balance = totals.balance
        let showsBalance = showsBalanceInstead && balance != nil
        let amount = showsBalance ? (balance ?? 0) : spent
        let isEmptyMonth = Money.isZero(spent) && Money.isZero(totals.income)

        VStack(spacing: 10) {
            Button {
                guard balance != nil else { return }
                withAnimation(.easeInOut(duration: 0.24)) { showsBalanceInstead.toggle() }
            } label: {
                // 52, no 68: con decimales y separador de miles el monto
                // llega a doce caracteres, y a 68 pt ocupaba el ancho entero
                // de la pantalla y empujaba la lista fuera del primer vistazo.
                // Sigue siendo la pieza más grande de la pantalla, que es lo
                // que tiene que ser, sin comerse el resto.
                Text(heroText(amount, showsBalance: showsBalance))
                    .font(.system(size: 52, weight: .bold, design: .default))
                    .tracking(-2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    // Mes vacío: el monto se mantiene en S/ 0 y en gris. La
                    // jerarquía no cambia entre estados; sólo el peso visual.
                    .foregroundStyle(isEmptyMonth ? palette.tertiaryLabel : palette.label)
                    .contentTransition(.numericText())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showsBalance ? "Balance del mes" : "Gasto del mes")
            .accessibilityHint(balance == nil ? "" : "Toca para alternar entre gasto y balance")

            monthChip(totals: totals, previous: previousSpent)

            if let balance, !Money.isZero(totals.income) {
                let sign = Money.cents(balance) < 0 ? "–" : ""
                Text("Ingresos " + Money.format(totals.income)
                     + " · Queda " + sign + Money.format(abs(balance)))
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondaryLabel)
            }

            if !isCurrentMonth {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { monthOffset = 0 }
                } label: {
                    Text("Volver a hoy")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(accent.onSurface(scheme))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    /// «Setiembre»; con el año si el mes mostrado es de otro año.
    private var monthTitle: String {
        let name = Period.spanishMonthName(for: month.reference)
        let calendar = Calendar.current
        guard calendar.component(.year, from: month.reference) != calendar.component(.year, from: Date())
        else { return name }
        return name + " " + String(calendar.component(.year, from: month.reference))
    }

    private func heroText(_ amount: Double, showsBalance: Bool) -> String {
        let formatted = Money.format(abs(amount))
        if showsBalance {
            return (Money.cents(amount) < 0 ? "–" : "") + formatted
        }
        return Money.isZero(amount) ? formatted : "–" + formatted
    }

    /// Mes en curso y cuánto más (o menos) llevas gastado que el mes pasado.
    ///
    /// Sin mes anterior con datos no hay comparación posible, y el chip se
    /// queda sólo con el nombre del mes en vez de inventar un "↑ 100 %".
    @ViewBuilder
    private func monthChip(totals: PeriodTotals, previous: Double) -> some View {
        let delta = Money.subtract(totals.spent, previous)
        let hasComparison = !Money.isZero(previous)
        let isUp = Money.cents(delta) > 0

        HStack(spacing: 8) {
            // El pasado se navega hacia atrás desde aquí; para volver está
            // «Volver a hoy», debajo, igual que en Historial.
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { monthOffset += 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accent.onSurface(scheme))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, -6)
            .accessibilityLabel("Mes anterior")

            Text(monthTitle)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(palette.label)

            if hasComparison, !Money.isZero(delta) {
                Rectangle()
                    .fill(palette.hairline)
                    .frame(width: 1, height: 12)

                HStack(spacing: 3) {
                    Image(systemName: isUp ? "arrow.up" : "arrow.down")
                        .font(.system(size: 11, weight: .bold))
                    Text(Money.format(abs(delta)))
                        .font(.system(size: 13.5, weight: .semibold))
                }
                .foregroundStyle(isUp ? palette.negative : palette.positive)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(palette.surface, in: Capsule())
        .overlay(Capsule().stroke(palette.hairline, lineWidth: 0.5))
    }

    // MARK: - Días

    @ViewBuilder
    private func daySection(_ group: DayGroup) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.dayLabel(for: group.day))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.label)

                Spacer()

                Text("–" + Money.format(group.spent))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.secondaryLabel)
            }
            .padding(.horizontal, 6)

            MovementCard {
                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                    switch item {
                    case .expense(let expense):
                        MovementRow(expense: expense,
                                    onTap: { selectedExpense = expense },
                                    onAssignCategory: { expenseToCategorize = expense },
                                    onEdit: { selectedExpense = expense })
                    case .income(let income):
                        IncomeRow(income: income, onTap: { selectedIncome = income })
                    }

                    if index < group.items.count - 1 {
                        MovementSeparator()
                    }
                }
            }
        }
    }

    // MARK: - Vacíos

    /// La lista se acaba donde se acaba el mes. Sin este pie, el final del
    /// scroll parecería que faltan movimientos por cargar.
    private var monthFooter: some View {
        Text("Hasta aquí " + Period.spanishMonthName(for: month.reference).lowercased()
             + ". Lo anterior está en Movimientos e Historial.")
            .font(.system(size: 12))
            .foregroundStyle(palette.tertiaryLabel)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .padding(.bottom, 8)
    }

    private var emptyToday: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Hoy")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.label)

                Spacer()

                Text(Money.formatCompact(0))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.tertiaryLabel)
            }
            .padding(.horizontal, 6)

            VStack(spacing: 12) {
                // El pingüino del perfil: el mismo que ven tus amigos.
                PenguinView(look: social.penguin)
                    .frame(width: 88, height: 88)

                Text("Nada gastado hoy")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.label)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .padding(.bottom, 20)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 0.5)
            )
        }
    }

    private var emptyMonth: some View {
        VStack(spacing: 12) {
            // Hueco del pingüino: la ilustración entra aquí cuando el diseño
            // cierre su pose. El espacio se reserva desde ya para que la
            // pantalla no cambie de composición al añadirla.
            Color.clear.frame(width: 96, height: 96)

            Text(isCurrentMonth ? "Todavía no hay movimientos" : "Sin movimientos en " + monthTitle.lowercased())
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.label)

            Text(isCurrentMonth ? "Conecta tu correo o registra un gasto con el +"
                                : "Usa la flecha para ir más atrás o vuelve a hoy.")
                .font(.system(size: 13.5))
                .foregroundStyle(palette.secondaryLabel)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Helpers

    /// «Hoy», «Ayer», y para el resto el día de la semana con su fecha.
    static func dayLabel(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Hoy" }
        if calendar.isDateInYesterday(day) { return "Ayer" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_PE")
        formatter.dateFormat = calendar.isDate(day, equalTo: Date(), toGranularity: .year)
            ? "EEEE d 'de' MMMM"
            : "EEEE d 'de' MMMM, yyyy"
        return formatter.string(from: day).capitalizedFirst
    }

    struct DayGroup: Identifiable {
        let day: Date
        let items: [TransactionItem]
        let spent: Double
        var id: Date { day }
    }
}

/// Resumen › Hoy con su mes. Guarda cuántos meses se retrocedió para que
/// `TodayView` se reconstruya —con consultas del mes nuevo— al cambiarlo.
struct TodayScreen: View {
    @Binding var scrollToTopTrigger: Bool
    let progress: ScrollProgress

    @State private var monthOffset = 0

    var body: some View {
        TodayView(scrollToTopTrigger: $scrollToTopTrigger,
                  progress: progress,
                  monthOffset: $monthOffset)
    }
}
