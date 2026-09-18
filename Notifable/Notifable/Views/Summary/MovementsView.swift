import SwiftUI
import SwiftData

/// Resumen › Movimientos (`2a`): la lista completa, desacoplada de Hoy.
///
/// Aquí vive **el único buscador de la app**. Antes había campo de búsqueda en
/// el inicio y otro en Pendientes, cada uno buscando sobre un conjunto
/// distinto; el mismo texto daba dos resultados y ninguno de los dos era «todo
/// lo que tengo».
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

    @State private var searchText = ""
    @State private var kind: Kind = .gastos
    @State private var visibleCount = pageSize
    @State private var selectedExpense: Expense?
    @State private var selectedIncome: Income?
    @State private var expenseToCategorize: Expense?
    @State private var showsPendingConfirmation = false
    @FocusState private var searchFocused: Bool

    /// Sólo gastos o ingresos. Lo sin categoría ya no se filtra aquí: vive
    /// en Análisis › Pendientes, que es donde se clasifica.
    enum Kind: Hashable { case gastos, ingresos }

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
    private var items: [TransactionItem] {
        let source: [TransactionItem]
        if kind == .ingresos {
            source = incomes.map { TransactionItem.income($0) }
        } else {
            source = expenses.map { TransactionItem.expense($0) }
        }

        guard !searchText.isEmpty else { return source }

        return source.filter { item in
            switch item {
            case .expense(let e):
                return e.merchant.localizedCaseInsensitiveContains(searchText)
                    || e.category.localizedCaseInsensitiveContains(searchText)
            case .income(let i):
                return i.source.localizedCaseInsensitiveContains(searchText)
                    || (i.title ?? "").localizedCaseInsensitiveContains(searchText)
                    || (i.notes ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
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
        let items = self.items
        let visible = Array(items.prefix(visibleCount))
        let buckets = groups(from: visible)
        let pending = self.pendingOccurrences

        TrackableScrollView(scrollToTopTrigger: $scrollToTopTrigger) {
            VStack(spacing: 0) {
                ShellTitle(title: "Movimientos")

                searchField
                    .padding(.bottom, 10)

                ShellSegment(items: [Kind.gastos, .ingresos], selection: $kind) {
                    $0 == .gastos ? "Gastos" : "Ingresos"
                }
                .padding(.bottom, 18)

                if !pending.isEmpty, kind == .gastos {
                    pendingConfirmation(pending)
                        .padding(.bottom, 20)
                }

                if buckets.isEmpty {
                    emptyState
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

            TextField("Buscar por comercio…", text: $searchText)
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
                                    onAssignCategory: { expenseToCategorize = expense },
                                    onEdit: { selectedExpense = expense })
                    case .income(let income):
                        IncomeRow(income: income, onTap: { selectedIncome = income })
                    }

                    if index < bucket.items.count - 1 { MovementSeparator() }
                }
            }
        }
    }

    private func dayTotal(_ bucket: DayBucket) -> String {
        if kind == .ingresos {
            let total = Money.sum(bucket.items.compactMap { item -> Double? in
                guard case .income(let i) = item else { return nil }
                return Accounting.amountInPEN(i, fallbackRate: rate)
            })
            return "+" + Money.format(total)
        }
        let total = Money.sum(bucket.items.compactMap { item -> Double? in
            guard case .expense(let e) = item else { return nil }
            return Accounting.amountInPEN(e, fallbackRate: rate)
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
                            message: "Prueba con el nombre del comercio o el de la categoría.")
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
