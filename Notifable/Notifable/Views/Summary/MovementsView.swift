import SwiftUI
import SwiftData

/// Resumen › Movimientos (`2a`): la lista completa, desacoplada de Hoy.
///
/// Aquí vive **el único buscador de la app**. Antes había campo de búsqueda en
/// el inicio y otro en Pendientes, cada uno buscando sobre un conjunto
/// distinto; el mismo texto daba dos resultados y ninguno de los dos era «todo
/// lo que tengo».
///
/// Arriba, el carrusel de **tus cuentas** (`1b`): filtra la lista por la tarjeta
/// o billetera de la que salió —o a la que llegó— cada movimiento. «Editar»
/// abre «Tus cuentas» (`1c`), donde se marca qué es tuyo; lo que va de una
/// cuenta tuya a otra sale de la lista y de los totales, y se ve aparte en
/// TRASLADOS (`TransferDetector`).
///
/// «Por confirmar» va arriba del todo porque afecta a las cifras del mes: son
/// gastos recurrentes que la app ya detectó pero que no cuentan hasta que los
/// aceptas, y dejarlos al final sería esconder por qué un total no cuadra.
struct MovementsView: View {
    @Binding var scrollToTopTrigger: Bool
    let progress: ScrollProgress

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \Income.date, order: .reverse) private var incomes: [Income]
    @Query private var recurringRules: [RecurringExpense]
    @StateObject private var rates = ExchangeRateService.shared
    @StateObject private var accountBook = AccountBook.shared

    @State private var searchText = ""
    @State private var kind: Kind = .gastos
    @State private var visibleCount = pageSize
    @State private var selectedExpense: Expense?
    @State private var selectedIncome: Income?
    @State private var expenseToCategorize: Expense?
    @State private var showsPendingConfirmation = false
    /// La cuenta del carrusel; `nil` es «Todas».
    @State private var selectedAccount: String?
    @State private var showsAccounts = false
    @FocusState private var searchFocused: Bool

    /// Gastos, ingresos y —sólo si hay— lo que está por cobrar. Lo sin
    /// categoría ya no se filtra aquí: vive en Análisis › Pendientes, que es
    /// donde se clasifica.
    enum Kind: Hashable { case gastos, ingresos, porCobrar }

    /// Gastos marcados por cobrar a los que aún les falta algo.
    private var debts: [Expense] {
        expenses.filter { $0.isDebt && !$0.isTransfer && Money.cents(Accounting.outstanding(of: $0)) > 0 }
    }

    /// Se cargan de 20 en 20, y con botón: la carga automática al llegar al
    /// final deja la lista creciendo bajo el dedo mientras se clasifica, y se
    /// pierde el sitio en el que se iba.
    private static let pageSize = 20

    private var palette: Palette { Palette(scheme) }
    private var accent: AppThemeColor { .current }
    private var rate: Double { rates.usdToPenRate }

    // MARK: - Datos

    /// Todo lo programado que llegó a su fecha: lo que espera confirmación y
    /// lo que el banco ya cobró. Sin nada, el bloque no se dibuja (`3d`).
    private var pendingOccurrences: [PendingOccurrence] {
        RecurringEngine.pending(rules: recurringRules, expenses: expenses)
    }

    /// - Note: **sin `sorted`**. Las dos consultas ya llegan ordenadas por
    ///   fecha descendente y `filter` conserva el orden, así que ordenar aquí
    ///   era volver a ordenar el historial entero en cada pasada del cuerpo —y
    ///   el cuerpo lo leía dos veces, una para la lista y otra para saber si
    ///   quedaban páginas.
    ///
    /// Los traslados no están: tienen su propia sección arriba.
    private var source: [TransactionItem] {
        switch kind {
        case .ingresos:  return incomes.filter { !$0.isTransfer }.map { TransactionItem.income($0) }
        case .porCobrar: return debts.map { TransactionItem.expense($0) }
        case .gastos:    return expenses.filter { !$0.isTransfer }.map { TransactionItem.expense($0) }
        }
    }

    private func items(from source: [TransactionItem], catalog: AccountCatalog) -> [TransactionItem] {
        var result = source
        if let selectedAccount {
            result = result.filter { accountKeys(of: $0, catalog: catalog).contains(selectedAccount) }
        }
        guard !searchText.isEmpty else { return result }
        return result.filter { $0.matches(searchText) }
    }

    // MARK: - Cuentas

    /// Las cuentas que toca un movimiento: la de origen (ya unida a su
    /// tarjeta, ver `AccountCatalog.canonical`) y, si va a una persona, la
    /// del destinatario.
    private func accountKeys(of item: TransactionItem, catalog: AccountCatalog) -> [String] {
        switch item {
        case .expense(let e):
            return (catalog.resolve(e.originKey, at: e.date).map { [$0] } ?? []) + (e.payeeKey.map { [$0] } ?? [])
        case .income(let i):
            return (catalog.resolve(i.originKey, at: i.date).map { [$0] } ?? []) + (i.senderKey.map { [$0] } ?? [])
        }
    }

    private func badge(_ key: String?, at date: Date = .distantPast, catalog: AccountCatalog) -> AccountBadge? {
        guard let key = catalog.resolve(key, at: date), let account = catalog.accounts[key] else { return nil }
        return AccountBadge(name: accountBook.preferences.name(for: account),
                            institution: account.institution ?? account.via)
    }

    /// Los traslados a mostrar: los del mes, o todos los que coincidan si se
    /// está buscando. Un gasto y su ingreso gemelo (mismo monto, minutos de
    /// diferencia) son una sola fila «BBVA → Yape».
    private func transferEntries(catalog: AccountCatalog) -> [TransferEntry] {
        let month = Period(granularity: .mes, reference: Date()).interval
        func inScope(_ item: TransactionItem) -> Bool {
            searchText.isEmpty
                ? item.date >= month.start && item.date < month.end
                : item.matches(searchText)
        }
        let outgoing = expenses.filter { $0.isTransfer && inScope(.expense($0)) }
        let incoming = incomes.filter { $0.isTransfer && inScope(.income($0)) }

        let pairs = TransferDetector.pairs(
            outgoing: outgoing.map { .init(id: $0.id, cents: Money.cents($0.amount), currency: $0.currency, date: $0.date) },
            incoming: incoming.map { .init(id: $0.id, cents: Money.cents($0.amount), currency: $0.currency, date: $0.date) })
        let incomesByID = Dictionary(uniqueKeysWithValues: incoming.map { ($0.id, $0) })
        let paired = Set(pairs.values)

        var entries: [TransferEntry] = outgoing.map { expense in
            let from = badge(expense.originKey, at: expense.date, catalog: catalog)
                ?? AccountBadge(name: "Tu cuenta", institution: nil)
            let twin = pairs[expense.id].flatMap { incomesByID[$0] }
            // El destino, de más a menos preciso: la cuenta donde entró el
            // ingreso gemelo, la billetera que dijo el correo, el nombre
            // que le diste al destinatario.
            let wallet = expense.destinationWallet.flatMap(Institution.init(name:))
            let payee = badge(expense.payeeKey, catalog: catalog)
            let cash = AccountResolver.originKey(.efectivo)
            // Un retiro va siempre a tu efectivo.
            let to = expense.isCashWithdrawal
                ? (badge(cash, catalog: catalog) ?? AccountBadge(name: "Efectivo", institution: .efectivo))
                : badge(twin?.originKey, at: twin?.date ?? expense.date, catalog: catalog)
                    ?? payee.map { AccountBadge(name: $0.name, institution: wallet ?? $0.institution) }
                    ?? AccountBadge(name: wallet?.name ?? "Tu cuenta", institution: wallet)
            var keys: Set<String> = []
            if let origin = catalog.resolve(expense.originKey, at: expense.date) { keys.insert(origin) }
            if expense.isCashWithdrawal { keys.insert(cash) }
            if let payee = expense.payeeKey { keys.insert(payee) }
            if let twin, let twinOrigin = catalog.resolve(twin.originKey, at: twin.date) { keys.insert(twinOrigin) }
            return TransferEntry(id: expense.id, from: from, to: to, amount: expense.amount,
                                 currency: expense.currency, date: expense.date,
                                 expense: expense, income: twin, keys: keys)
        }

        for income in incoming where !paired.contains(income.id) {
            let from = badge(income.senderKey, catalog: catalog)
                ?? AccountBadge(name: income.senderName ?? "Tu cuenta", institution: nil)
            let to = badge(income.originKey, at: income.date, catalog: catalog)
                ?? AccountBadge(name: income.source, institution: Institution(name: income.source))
            var keys: Set<String> = []
            if let origin = catalog.resolve(income.originKey, at: income.date) { keys.insert(origin) }
            if let sender = income.senderKey { keys.insert(sender) }
            entries.append(TransferEntry(id: income.id, from: from, to: to, amount: income.amount,
                                         currency: income.currency, date: income.date,
                                         expense: nil, income: income, keys: keys))
        }

        if let selectedAccount {
            entries = entries.filter { $0.keys.contains(selectedAccount) }
        }
        return entries.sorted { $0.date > $1.date }
    }

    /// Movimientos de la lista actual por cuenta, para las tarjetas del
    /// carrusel.
    private func counts(in source: [TransactionItem], catalog: AccountCatalog) -> [String: Int] {
        var counts: [String: Int] = [:]
        for item in source {
            for key in Set(accountKeys(of: item, catalog: catalog)) { counts[key, default: 0] += 1 }
        }
        return counts
    }

    /// Agrupados por día, igual que Hoy: la lista no cambia de gramática al
    /// cambiar de sub-vista.
    private func groups(from items: [TransactionItem]) -> [DayBucket] {
        let calendar = Calendar.current
        var buckets: [Date: [TransactionItem]] = [:]
        for item in items {
            buckets[calendar.startOfDay(for: item.date), default: []].append(item)
        }
        return buckets.keys.sorted(by: >).map { day in
            DayBucket(day: day, items: buckets[day] ?? [])
        }
    }

    var body: some View {
        let catalog = AccountCatalog(expenses: expenses, incomes: incomes)
        let carousel = accountBook.preferences.carousel(from: catalog)
        let source = self.source
        let items = self.items(from: source, catalog: catalog)
        let visible = Array(items.prefix(visibleCount))
        let buckets = groups(from: visible)
        let pending = self.pendingOccurrences
        let hasDebts = !debts.isEmpty
        let transfers = kind == .porCobrar ? [] : transferEntries(catalog: catalog)

        TrackableScrollView(scrollToTopTrigger: $scrollToTopTrigger) {
            VStack(spacing: 0) {
                ShellTitle(title: "Movimientos")

                // Con alguna cuenta detectada, aunque ninguna esté marcada
                // como tuya: «Editar» es la puerta para marcarlas.
                if !catalog.accounts.isEmpty {
                    AccountCarousel(accounts: carousel,
                                    name: { accountBook.preferences.name(for: $0) },
                                    counts: counts(in: source, catalog: catalog),
                                    total: source.count,
                                    selection: $selectedAccount,
                                    onEdit: { showsAccounts = true })
                        .padding(.horizontal, -16)
                        .padding(.bottom, 14)
                        // Una cuenta que dejó de ser tuya ya no está en el
                        // carrusel: el filtro vuelve a «Todas».
                        .onChange(of: carousel.map(\.key)) { _, keys in
                            if let selectedAccount, !keys.contains(selectedAccount) { self.selectedAccount = nil }
                        }
                        .sheet(isPresented: $showsAccounts) {
                            AccountsSheet(catalog: catalog, preferences: accountBook.preferences)
                                .presentationDragIndicator(.visible)
                                .presentationCornerRadius(28)
                        }
                }

                searchField
                    .padding(.bottom, 10)

                // La tercera opción sólo existe mientras haya algo por
                // cobrar: un filtro que siempre dice «nada» es ruido.
                ShellSegment(items: hasDebts ? [Kind.gastos, .ingresos, .porCobrar]
                                             : [Kind.gastos, .ingresos],
                             selection: $kind) { kind in
                    switch kind {
                    case .gastos:    return "Gastos"
                    case .ingresos:  return "Ingresos"
                    case .porCobrar: return "Por cobrar"
                    }
                }
                .padding(.bottom, 18)

                // Lo programado no tiene cuenta todavía: sólo en «Todas».
                if !pending.isEmpty, kind == .gastos, selectedAccount == nil {
                    pendingConfirmation(pending)
                        .padding(.bottom, 20)
                }

                if !transfers.isEmpty {
                    transfersSection(transfers)
                        .padding(.bottom, 20)
                }

                if buckets.isEmpty {
                    if transfers.isEmpty { emptyState }
                } else {
                    ForEach(buckets) { bucket in
                        dayBlock(bucket)
                            .padding(.bottom, 18)
                    }

                    if visibleCount < items.count {
                        loadMoreButton(remaining: items.count - visibleCount)
                    }
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
        .onChange(of: searchText) { _, _ in visibleCount = Self.pageSize }
        .onChange(of: kind) { _, _ in visibleCount = Self.pageSize }
        .onChange(of: selectedAccount) { _, _ in visibleCount = Self.pageSize }
        // Al cobrar el último pendiente la pestaña desaparece: sin esto la
        // lista se quedaba vacía y sin forma de salir.
        .onChange(of: debts.isEmpty) { _, empty in
            if empty, kind == .porCobrar { kind = .gastos }
        }
        // Ir a un movimiento desde una hoja: se cierra lo que haya encima
        // y Hoy lo resalta.
        .onReceive(NotificationCenter.default.publisher(for: ActivityFocus.notification)) { _ in
            selectedExpense = nil
            selectedIncome = nil
        }
        .sheet(item: $selectedExpense) { ExpenseDetailsView(expense: $0) }
        .sheet(isPresented: $showsPendingConfirmation) { PendingConfirmationView() }
        .sheet(item: $selectedIncome) { IncomeDetailsView(income: $0) }
        .sheet(item: $expenseToCategorize) { expense in
            AssignCategorySheet(context: .expense(expense), history: expenses) { newCategory, createRule in
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

    // MARK: - Buscador

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(palette.secondaryLabel)

            TextField(MovementSearch.placeholder, text: $searchText)
                .font(.system(size: 15))
                .foregroundStyle(palette.label)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(palette.tertiaryLabel)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(palette.surface, in: Capsule())
        .overlay(Capsule().stroke(palette.hairline, lineWidth: 0.5))
    }

    // MARK: - Por confirmar

    @ViewBuilder
    private func pendingConfirmation(_ pending: [PendingOccurrence]) -> some View {
        let awaiting = pending.filter(\.isAwaiting)
        let bankCount = pending.count - awaiting.count
        let count = awaiting.reduce(0) { $0 + $1.dates.count }
        let total = Money.sum(awaiting) { $0.totalAmount }

        VStack(spacing: 8) {
            // La cabecera abre la pantalla completa (`5i`): ahí están
            // «Cambiar», las fechas acumuladas y los que ya cobró el banco.
            Button { showsPendingConfirmation = true } label: {
                HStack(alignment: .firstTextBaseline) {
                    ShellSectionHeader(title: "Por confirmar",
                                       trailing: "\(count) · " + Money.format(total))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.tertiaryLabel)
                        .padding(.bottom, 8)
                }
            }
            .buttonStyle(.plain)

            if !awaiting.isEmpty {
                MovementCard {
                    ForEach(Array(awaiting.enumerated()), id: \.element.id) { index, occurrence in
                        pendingRow(occurrence)
                        if index < awaiting.count - 1 { MovementSeparator() }
                    }
                }
            }

            // Los que el banco ya cobró no se aceptan con un check: aceptarlos
            // duplicaría el gasto. Se deciden en la pantalla completa.
            if bankCount > 0 {
                Button { showsPendingConfirmation = true } label: {
                    Label(bankCount == 1 ? "1 ya lo cobró el banco · revisar"
                                         : "\(bankCount) ya los cobró el banco · revisar",
                          systemImage: "envelope")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(palette.warning.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Text("No cuentan en tu mes hasta que los aceptes.")
                .font(.system(size: 12))
                .foregroundStyle(palette.secondaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.top, 2)
        }
    }

    private func pendingRow(_ occurrence: PendingOccurrence) -> some View {
        HStack(spacing: 12) {
            MovementIcon(icon: CategoryStyle.icon(for: occurrence.category),
                         color: CategoryStyle.color(for: occurrence.category, accent: accent.color))

            VStack(alignment: .leading, spacing: 2) {
                Text(Accounting.displayName(occurrence.merchant))
                    .font(.system(size: 16.5, weight: .semibold))
                    .foregroundStyle(palette.label)
                    .lineLimit(1)

                Text(recurrenceLabel(occurrence))
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.secondaryLabel)
            }

            Spacer(minLength: 8)

            Text("–" + Money.format(occurrence.totalAmount, currency: occurrence.currency))
                .font(.system(size: 16.5, weight: .semibold))
                .foregroundStyle(palette.label)

            Button {
                confirm(occurrence)
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 30, height: 30)
                    .background(accent.color, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Aceptar " + Accounting.displayName(occurrence.merchant))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func recurrenceLabel(_ occurrence: PendingOccurrence) -> String {
        guard let first = occurrence.dates.first else { return "Recurrente" }
        let day = Calendar.current.component(.day, from: first)
        return occurrence.dates.count > 1
            ? "Recurrente · \(occurrence.dates.count) cobros"
            : "Recurrente · día \(day)"
    }

    private func confirm(_ occurrence: PendingOccurrence) {
        guard let rule = recurringRules.first(where: { $0.id == occurrence.ruleID }) else { return }
        RecurringEngine.confirm(occurrence, rule: rule, in: modelContext)
        try? modelContext.save()
    }

    // MARK: - Traslados

    private func transfersSection(_ entries: [TransferEntry]) -> some View {
        VStack(spacing: 8) {
            ShellSectionHeader(title: "Traslados",
                               trailing: searchText.isEmpty ? "\(entries.count) este mes" : "\(entries.count)")

            MovementCard {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    TransferRowView(entry: entry) {
                        if let expense = entry.expense { selectedExpense = expense }
                        else if let income = entry.income { selectedIncome = income }
                    }
                    if index < entries.count - 1 { MovementSeparator() }
                }
            }

            Text(kind == .ingresos ? "Entre tus cuentas. No cuentan como ingreso del mes."
                                   : "Entre tus cuentas. No cuentan como gasto del mes.")
                .font(.system(size: 12))
                .foregroundStyle(palette.secondaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.top, 2)
        }
    }

    // MARK: - Lista

    private func dayBlock(_ bucket: DayBucket) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(TodayView.dayLabel(for: bucket.day))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.label)

                Spacer()

                Text(dayTotal(bucket))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.secondaryLabel)
            }
            .padding(.horizontal, 6)

            MovementCard {
                ForEach(Array(bucket.items.enumerated()), id: \.element.id) { index, item in
                    switch item {
                    case .expense(let expense):
                        MovementRow(expense: expense,
                                    onTap: { selectedExpense = expense },
                                    onAssignCategory: { expenseToCategorize = expense })
                    case .income(let income):
                        IncomeRow(income: income, onTap: { selectedIncome = income })
                    }

                    if index < bucket.items.count - 1 { MovementSeparator() }
                }
            }
        }
    }

    private func dayTotal(_ bucket: DayBucket) -> String {
        if kind == .porCobrar {
            let total = Money.sum(bucket.items.compactMap { item -> Double? in
                guard case .expense(let e) = item else { return nil }
                return Accounting.outstanding(of: e)
            })
            return "falta " + Money.format(total)
        }
        if kind == .ingresos {
            let total = Money.sum(bucket.items.compactMap { item -> Double? in
                guard case .income(let i) = item else { return nil }
                return Accounting.amountInPEN(i, fallbackRate: rate)
            })
            return "+" + Money.format(total)
        }
        let total = Money.sum(bucket.items.compactMap { item -> Double? in
            guard case .expense(let e) = item else { return nil }
            return Accounting.netCostInPEN(e, fallbackRate: rate)
        })
        return "–" + Money.format(total)
    }

    private func loadMoreButton(remaining: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                visibleCount += Self.pageSize
            }
        } label: {
            HStack(spacing: 6) {
                Text("Cargar más")
                    .font(.system(size: 14, weight: .semibold))
                Text("(\(remaining))")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondaryLabel)
            }
            .foregroundStyle(accent.onSurface(scheme))
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(palette.surface, in: Capsule())
            .overlay(Capsule().stroke(palette.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var emptyState: some View {
        if !searchText.isEmpty {
            ShellEmptyState(icon: "magnifyingglass",
                            title: "Sin resultados para «" + searchText + "»",
                            message: MovementSearch.emptyMessage(for: searchText))
        } else if selectedAccount != nil {
            ShellEmptyState(icon: "tray",
                            title: "Nada en esta cuenta",
                            message: "No hay movimientos de esta cuenta en esta lista.")
        } else {
            ShellEmptyState(icon: "tray",
                            title: "Nada por aquí",
                            message: "Cuando llegue un movimiento aparecerá en esta lista.")
        }
    }

    struct DayBucket: Identifiable {
        let day: Date
        let items: [TransactionItem]
        var id: Date { day }
    }
}
