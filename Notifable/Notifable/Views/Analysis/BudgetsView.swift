import SwiftUI
import SwiftData

/// Análisis › Presupuestos (`2e`).
///
/// Antes los límites vivían escondidos dentro de la lista de categorías, como
/// una barra fina bajo cada fila. Sacarlos a su propia sub-vista les da sitio
/// para lo único que hace útil a un límite: la **proyección**. «S/ 888 de 900»
/// no dice si vas a pasarte; «a este ritmo terminas el mes en S/ 1,268», sí.
struct BudgetsView: View {
    @Binding var scrollToTopTrigger: Bool
    let progress: ScrollProgress

    @Environment(\.colorScheme) private var scheme
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @StateObject private var rates = ExchangeRateService.shared
    @StateObject private var budgets = CategoryBudgetStore.shared

    @AppStorage(NotificationManager.categoryLimitEnabledKey) private var limitAlertsEnabled = true

    @State private var editingCategory: CategoryRef?

    private var palette: Palette { Palette(scheme) }
    private var accent: AppThemeColor { .current }
    private var rate: Double { rates.usdToPenRate }
    private var month: Period { Period(granularity: .mes, reference: Date()) }

    private var snapshots: [ExpenseSnapshot] { expenses.map(\.accountingSnapshot) }

    private var totals: PeriodTotals {
        Accounting.totals(expenses: expenses, incomes: incomes, period: month, usdToPen: rate)
    }

    /// Categorías con gasto este mes o con límite puesto. Las que no tienen ni
    /// una cosa ni la otra no pintan nada aquí.
    private var rows: [Row] {
        var names = Set(totals.byCategory.map(\.category))
        names.formUnion(budgets.budgets.filter(\.value.hasLimit).keys)
        names.remove(Accounting.unclassified)

        return names.map { name in
            Row(category: name,
                status: CategoryLimits.status(category: name,
                                              budget: budgets.budget(for: name),
                                              expenses: snapshots,
                                              on: Date(),
                                              usdToPen: rate),
                spentThisMonth: totals.byCategory.first { $0.category == name }?.total ?? 0)
        }
        // Con límite primero y por porcentaje consumido: lo que está a punto
        // de romperse va arriba, que es para lo que se abre esta pantalla.
        .sorted { lhs, rhs in
            if lhs.status.hasLimit != rhs.status.hasLimit { return lhs.status.hasLimit }
            if lhs.status.hasLimit { return lhs.status.fraction > rhs.status.fraction }
            return Money.cents(lhs.spentThisMonth) > Money.cents(rhs.spentThisMonth)
        }
    }

    var body: some View {
        let rows = self.rows
        let withLimit = rows.filter(\.status.hasLimit)
        let elapsed = Int((month.elapsedFraction * 100).rounded())

        TrackableScrollView(scrollToTopTrigger: $scrollToTopTrigger) {
            VStack(spacing: 12) {
                ShellTitle(title: "Presupuestos",
                           subtitle: withLimit.isEmpty
                               ? "Ninguna categoría tiene límite todavía"
                               : "\(withLimit.count) categorías con límite · \(elapsed)% del mes transcurrido")

                if rows.isEmpty {
                    ShellEmptyState(icon: "target",
                                    title: "Nada que presupuestar",
                                    message: "Cuando tengas gastos clasificados podrás ponerles un límite.")
                } else {
                    ForEach(rows) { row in
                        Button {
                            editingCategory = CategoryRef(name: row.category)
                        } label: {
                            row.status.hasLimit ? AnyView(limitCard(row)) : AnyView(noLimitCard(row))
                        }
                        .buttonStyle(.plain)
                    }

                    alertsRow
                        .padding(.top, 6)
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
        .sheet(item: $editingCategory) { ref in
            CategoryLimitEditorView(
                category: ref.name,
                color: CategoryStyle.color(for: ref.name, accent: accent.color),
                budget: budgets.record(for: ref.name)
                    ?? CategoryBudget(category: ref.name, amount: 0),
                history: expenses
            ) { updated in
                budgets.save(updated)
            }
        }
    }

    // MARK: - Tarjetas

    private func limitCard(_ row: Row) -> some View {
        let status = row.status
        let projection = projection(of: status)

        return ShellCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    MovementIcon(icon: CategoryStyle.icon(for: row.category),
                                 color: CategoryStyle.color(for: row.category, accent: accent.color),
                                 size: 38)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.category)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(palette.label)
                        Text(Money.format(status.spent) + " de " + Money.formatCompact(status.limit))
                            .font(.system(size: 12.5))
                            .foregroundStyle(palette.secondaryLabel)
                    }

                    Spacer(minLength: 6)

                    Text("\(Int((status.fraction * 100).rounded()))%")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(tint(for: status))
                }

                PaceBar(fraction: status.fraction,
                        expected: status.elapsedFraction,
                        status: level(of: status))

                if status.isOver {
                    ShellNote(icon: "exclamationmark.triangle",
                              text: "Pasaste el límite por " + Money.format(status.overBy),
                              tint: palette.negative)
                } else if let projection {
                    ShellNote(icon: "chart.line.uptrend.xyaxis",
                              text: "A este ritmo terminas el mes en " + Money.format(projection),
                              tint: Money.cents(projection) > Money.cents(status.limit)
                                  ? palette.warning : palette.secondaryLabel)
                }
            }
        }
    }

    private func noLimitCard(_ row: Row) -> some View {
        ShellCard {
            HStack(spacing: 12) {
                MovementIcon(icon: CategoryStyle.icon(for: row.category),
                             color: CategoryStyle.color(for: row.category, accent: accent.color),
                             size: 38)

                VStack(alignment: .leading, spacing: 1) {
                    Text(row.category)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.label)
                    // Sin «este mes»: el subtítulo de la pantalla ya dijo de
                    // qué mes habla, y con el nombre largo de una categoría
                    // esas dos palabras partían la fila en dos líneas.
                    Text("Sin límite · " + Money.format(row.spentThisMonth))
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.secondaryLabel)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Text("Poner límite")
                    .font(.system(size: 12.5, weight: .semibold))
                    .fixedSize()
                    .foregroundStyle(accent.onSurface(scheme))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(accent.color.opacity(0.14), in: Capsule())
            }
        }
    }

    private var alertsRow: some View {
        ShellCard {
            HStack(spacing: 12) {
                Image(systemName: "bell")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(accent.onSurface(scheme))
                    .frame(width: 38, height: 38)
                    .background(accent.color.opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Avisarme al 80%")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.label)
                    Text("Notificación por categoría")
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.secondaryLabel)
                }

                Spacer()

                Toggle("", isOn: $limitAlertsEnabled)
                    .labelsHidden()
                    .tint(accent.color)
            }
        }
    }

    // MARK: - Cálculo

    /// Cierre estimado del ciclo si se mantiene el ritmo. `nil` al principio
    /// del ciclo, donde dividir por una fracción casi cero da cifras absurdas.
    private func projection(of status: CategoryLimitStatus) -> Double? {
        let elapsed = status.elapsedFraction
        guard elapsed > 0.08, Money.cents(status.spent) > 0 else { return nil }
        return Money.multiply(status.spent, by: 1 / elapsed)
    }

    private func level(of status: CategoryLimitStatus) -> Pace.Status {
        if status.isOver { return .over }
        if status.fraction > status.elapsedFraction { return .warning }
        return .ok
    }

    private func tint(for status: CategoryLimitStatus) -> Color {
        switch level(of: status) {
        case .ok:      return palette.label
        case .warning: return palette.warning
        case .over:    return palette.negative
        }
    }

    struct Row: Identifiable {
        let category: String
        let status: CategoryLimitStatus
        let spentThisMonth: Double
        var id: String { category }
    }
}
