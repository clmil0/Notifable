import SwiftUI
import SwiftData

/// Análisis › Categorías (`2d`), la sub-vista por defecto de la pestaña.
///
/// Gráfico y lista **fusionados**. Antes vivían en pantallas distintas: el
/// donut arriba de la pestaña Ritmo y la lista dentro de Categorías, así que
/// para saber qué porción era cuál había que cambiar de pestaña y recordar el
/// color. Ahora la leyenda hace de resumen y la lista, de detalle.
///
/// Y con ellas el **límite**: `Presupuestos` era una sub-vista aparte que
/// repetía la misma lista de categorías con otra forma, así que para saber
/// "cuánto llevo en Comida y cuánto me queda" había que mirar en dos sitios y
/// recordar una de las dos cifras. Ahora la categoría que tiene límite lleva
/// su barra debajo de la fila; la proyección y la edición siguen estando a un
/// toque, en el detalle de la categoría.
struct CategoriesOverviewView: View {
    @Binding var scrollToTopTrigger: Bool
    let progress: ScrollProgress

    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var modelContext
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @StateObject private var rates = ExchangeRateService.shared
    @StateObject private var catalog = CategoryCatalog.shared
    @StateObject private var budgets = CategoryBudgetStore.shared

    @State private var selectedCategory: CategoryRef?
    @State private var creatingCategory = false

    private var palette: Palette { Palette(scheme) }
    private var accent: AppThemeColor { .current }
    private var rate: Double { rates.usdToPenRate }
    private var month: Period { Period(granularity: .mes, reference: Date()) }

    private var totals: PeriodTotals {
        Accounting.totals(expenses: expenses, incomes: incomes, period: month, usdToPen: rate)
    }

    private func slices(_ totals: PeriodTotals) -> [CategoryDonut.Slice] {
        totals.byCategory.map { category in
            CategoryDonut.Slice(category: category.category,
                                total: category.total,
                                color: CategoryStyle.color(for: category.category, accent: accent.color))
        }
    }

    var body: some View {
        let totals = self.totals
        let slices = self.slices(totals)
        let rows = self.rows(totals)

        TrackableScrollView(scrollToTopTrigger: $scrollToTopTrigger) {
            VStack(spacing: 18) {
                if rows.isEmpty {
                    ShellEmptyState(icon: "square.grid.2x2",
                                    title: "Sin gastos este mes",
                                    message: "Cuando registres el primero verás aquí en qué se va tu dinero.")
                } else {
                    chartCard(totals: totals, slices: slices)
                    categoryList(rows: rows, spent: totals.spent)
                    newCategoryRow
                    topMerchants(totals: totals)
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
        .sheet(item: $selectedCategory) { ref in
            CategoryDetailView(category: ref.name)
        }
        .sheet(isPresented: $creatingCategory) {
            CategorySettingsView(category: "", isNew: true, history: expenses)
        }
    }

    // MARK: - Gráfico

    /// Suelto sobre el fondo, sin tarjeta (`2d`): el donut encabeza la
    /// pantalla y la tarjeta queda para la lista, que es lo que se toca.
    private func chartCard(totals: PeriodTotals, slices: [CategoryDonut.Slice]) -> some View {
        HStack(spacing: 18) {
            CategoryDonut(slices: slices)

            DonutLegend(slices: slices, total: totals.spent)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
        .padding(.top, 16)
    }

    // MARK: - Filas

    /// Una fila por categoría con gasto este mes **más** las que sólo tienen
    /// límite: un límite que no se ha tocado en todo el mes es justo el que hay
    /// que ver, y si dependiera del gasto sería invisible hasta gastarlo.
    private func rows(_ totals: PeriodTotals) -> [Row] {
        let snapshots = expenses.map(\.accountingSnapshot)
        let today = Date()

        func status(_ name: String) -> CategoryLimitStatus {
            CategoryLimits.status(category: name,
                                  budget: budgets.budget(for: name),
                                  expenses: snapshots,
                                  on: today,
                                  usdToPen: rate)
        }

        var rows = totals.byCategory.map {
            Row(category: $0.category, total: $0.total, status: status($0.category))
        }

        // Al final y en orden alfabético: la lista la manda el gasto, y estas
        // no tienen ninguno con el que competir por su sitio.
        let spent = Set(rows.map(\.category))
        let idle = budgets.budgets.values
            .filter { $0.hasLimit && !spent.contains($0.category) && $0.category != Accounting.unclassified }
            .map { Row(category: $0.category, total: 0, status: status($0.category)) }
            .sorted { $0.category < $1.category }

        rows.append(contentsOf: idle)
        return rows
    }

    // MARK: - Lista

    private func categoryList(rows: [Row], spent: Double) -> some View {
        MovementCard {
            monthTotalRow(spent: spent)
            MovementSeparator()

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                Button {
                    selectedCategory = CategoryRef(name: row.category)
                } label: {
                    categoryRow(row, of: spent)
                }
                .buttonStyle(.plain)

                if index < rows.count - 1 { MovementSeparator() }
            }
        }
    }

    /// Encabeza la lista con el total del mes. Antes vivía dentro del donut,
    /// pero con el anillo más grueso ya no cabía legible.
    private func monthTotalRow(spent: Double) -> some View {
        HStack {
            Text(Period.spanishMonthName(for: Date()))
                .font(.system(size: 16.5, weight: .bold))
                .foregroundStyle(palette.label)

            Spacer(minLength: 8)

            Text(Money.format(spent))
                .font(.system(size: 16.5, weight: .bold))
                .foregroundStyle(palette.label)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func categoryRow(_ row: Row, of total: Double) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                MovementIcon(icon: CategoryStyle.icon(for: row.category),
                             color: CategoryStyle.color(for: row.category, accent: accent.color))

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.category)
                        .font(.system(size: 16.5, weight: .semibold))
                        .foregroundStyle(palette.label)
                        .lineLimit(1)

                    Text(subtitle(of: row, total: total))
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.secondaryLabel)
                }

                Spacer(minLength: 8)

                Text(Money.format(row.total))
                    .font(.system(size: 16.5, weight: .semibold))
                    .foregroundStyle(palette.label)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, row.status.hasLimit ? 9 : 12)

            if row.status.hasLimit { limitStrip(row.status) }
        }
        .contentShape(Rectangle())
    }

    /// La barra sólo aparece si hay límite. Su marca vertical es el ritmo —qué
    /// fracción del ciclo va transcurrida—, así que "voy por la mitad" se lee
    /// sin hacer ninguna cuenta: relleno por delante de la marca es ir rápido.
    private func limitStrip(_ status: CategoryLimitStatus) -> some View {
        let tint = status.level.color(palette)

        return VStack(alignment: .leading, spacing: 5) {
            LimitBar(fraction: status.fraction,
                     paceFraction: status.elapsedFraction,
                     color: tint,
                     height: 5)

            HStack(spacing: 6) {
                Text(status.longLabel)
                    .font(.system(size: 11.5))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)

                Text(status.daysLeftLabel)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.secondaryLabel)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    /// "18% · 4 movimientos", y en la categoría que sólo tiene límite, el
    /// hecho de que no se haya gastado nada — un "0% · 0 movimientos" obliga a
    /// leer dos cifras para enterarse de lo mismo.
    private func subtitle(of row: Row, total: Double) -> String {
        guard Money.cents(row.total) > 0 else { return "Sin gastos este mes" }
        return Money.formatPercent(row.total, of: total) + " · " + movementCount(of: row.category)
    }

    private func movementCount(of category: String) -> String {
        let range = month.interval
        let count = expenses.filter {
            $0.category == category && $0.date >= range.start && $0.date < range.end
        }.count
        return count == 1 ? "1 movimiento" : "\(count) movimientos"
    }

    /// Crear categoría vive **al final de la lista**, no en un modo de edición
    /// aparte: es una fila más, con la misma forma que las que crea.
    private var newCategoryRow: some View {
        Button {
            creatingCategory = true
        } label: {
            MovementCard {
                HStack(spacing: 12) {
                    MovementIcon(icon: "plus", color: accent.color)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nueva categoría")
                            .font(.system(size: 16.5, weight: .semibold))
                            .foregroundStyle(palette.label)
                        Text("Nombre, color y límite")
                            .font(.system(size: 12.5))
                            .foregroundStyle(palette.secondaryLabel)
                    }

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Top comercios

    @ViewBuilder
    private func topMerchants(totals: PeriodTotals) -> some View {
        let top = Array(totals.byMerchant.prefix(5))

        if !top.isEmpty {
            VStack(spacing: 8) {
                ShellSectionHeader(title: "Top comercios",
                                   trailing: Period.spanishMonthName(for: Date()))

                MovementCard {
                    ForEach(Array(top.enumerated()), id: \.element.id) { index, merchant in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(palette.secondaryLabel)
                                .frame(width: 20)

                            Text(Accounting.displayName(merchant.merchant))
                                .font(.system(size: 15.5, weight: .semibold))
                                .foregroundStyle(palette.label)
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            Text(Money.format(merchant.total))
                                .font(.system(size: 15.5, weight: .semibold))
                                .foregroundStyle(palette.label)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)

                        if index < top.count - 1 { MovementSeparator() }
                    }
                }
            }
        }
    }
}

extension CategoriesOverviewView {
    /// Lo que pinta una fila: el gasto del mes y el estado de su límite, ya
    /// resueltos, para que el cuerpo de la vista no calcule nada.
    struct Row: Identifiable {
        let category: String
        let total: Double
        let status: CategoryLimitStatus
        var id: String { category }
    }
}

/// Una categoría como `item:` de una hoja. `String` no es `Identifiable`, y
/// conformarlo de forma retroactiva afectaría a todo el módulo.
struct CategoryRef: Identifiable, Hashable {
    let name: String
    var id: String { name }
}
