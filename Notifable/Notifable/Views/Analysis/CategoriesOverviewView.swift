import SwiftUI
import SwiftData

/// Análisis › Categorías (`2d`), la sub-vista por defecto de la pestaña.
///
/// Gráfico y lista **fusionados**. Antes vivían en pantallas distintas: el
/// donut arriba de la pestaña Ritmo y la lista dentro de Categorías, así que
/// para saber qué porción era cuál había que cambiar de pestaña y recordar el
/// color. Ahora la leyenda hace de resumen y la lista, de detalle.
struct CategoriesOverviewView: View {
    @Binding var scrollToTopTrigger: Bool
    let progress: ScrollProgress

    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var modelContext
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @StateObject private var rates = ExchangeRateService.shared
    @StateObject private var catalog = CategoryCatalog.shared

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

        TrackableScrollView(scrollToTopTrigger: $scrollToTopTrigger) {
            VStack(spacing: 18) {
                if totals.byCategory.isEmpty {
                    ShellEmptyState(icon: "square.grid.2x2",
                                    title: "Sin gastos este mes",
                                    message: "Cuando registres el primero verás aquí en qué se va tu dinero.")
                } else {
                    chartCard(totals: totals, slices: slices)
                    categoryList(totals: totals)
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
            CategoryDonut(slices: slices,
                          centerTitle: Period.spanishMonthName(for: Date()),
                          centerValue: Money.format(totals.spent))

            DonutLegend(slices: slices, total: totals.spent)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
        .padding(.top, 16)
    }

    // MARK: - Lista

    private func categoryList(totals: PeriodTotals) -> some View {
        MovementCard {
            ForEach(Array(totals.byCategory.enumerated()), id: \.element.id) { index, category in
                Button {
                    selectedCategory = CategoryRef(name: category.category)
                } label: {
                    categoryRow(category, of: totals.spent)
                }
                .buttonStyle(.plain)

                if index < totals.byCategory.count - 1 { MovementSeparator() }
            }
        }
    }

    private func categoryRow(_ category: PeriodTotals.CategoryTotal, of total: Double) -> some View {
        HStack(spacing: 12) {
            MovementIcon(icon: CategoryStyle.icon(for: category.category),
                         color: CategoryStyle.color(for: category.category, accent: accent.color))

            VStack(alignment: .leading, spacing: 2) {
                Text(category.category)
                    .font(.system(size: 16.5, weight: .semibold))
                    .foregroundStyle(palette.label)
                    .lineLimit(1)

                Text(Money.formatPercent(category.total, of: total) + " · "
                     + movementCount(of: category.category))
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.secondaryLabel)
            }

            Spacer(minLength: 8)

            Text(Money.format(category.total))
                .font(.system(size: 16.5, weight: .semibold))
                .foregroundStyle(palette.label)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
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

/// Una categoría como `item:` de una hoja. `String` no es `Identifiable`, y
/// conformarlo de forma retroactiva afectaría a todo el módulo.
struct CategoryRef: Identifiable, Hashable {
    let name: String
    var id: String { name }
}
