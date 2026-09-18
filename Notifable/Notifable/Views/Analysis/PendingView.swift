import SwiftUI
import SwiftData

/// Análisis › Pendientes (`2c`): los comercios que la app no supo clasificar.
///
/// El ícono de esta sub-vista **sólo existe en la píldora mientras quedan
/// pendientes** (`3d`). Al llegar a cero desaparece: un destino permanente que
/// casi siempre dice «nada pendiente» es ruido con badge.
///
/// La sugerencia va **dentro del grupo**, no como banner aparte. Antes vivía
/// arriba, en una tarjeta propia, y había que acordarse de a qué comercio se
/// refería mientras se miraba la lista.
struct PendingView: View {
    @Binding var scrollToTopTrigger: Bool
    let progress: ScrollProgress

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @StateObject private var rates = ExchangeRateService.shared

    @State private var scope: Scope = .month
    @State private var selected: Set<String> = []
    @State private var visibleCount = pageSize
    @State private var didPickInitialScope = false
    @State private var assigning: AssignTarget?
    @State private var showsBulk = false

    enum Scope: Hashable { case month, all }

    /// De 20 en 20 y con botón, igual que Movimientos: la carga automática al
    /// llegar al final hacía crecer la lista bajo el dedo mientras se
    /// clasificaba.
    private static let pageSize = 20

    private var palette: Palette { Palette(scheme) }
    private var accent: AppThemeColor { .current }
    private var rate: Double { rates.usdToPenRate }
    private var month: Period { Period(granularity: .mes, reference: Date()) }

    // MARK: - Datos

    private var unclassified: [Expense] {
        let all = expenses.filter { $0.category == Accounting.unclassified }
        guard scope == .month else { return all }
        let range = month.interval
        return all.filter { $0.date >= range.start && $0.date < range.end }
    }

    private var groups: [Group] {
        var grouped: [String: [Expense]] = [:]
        for expense in unclassified { grouped[expense.merchant, default: []].append(expense) }

        return grouped.map { merchant, items in
            Group(merchant: merchant,
                  expenses: items.sorted { $0.date > $1.date },
                  total: Money.sum(items) { Accounting.amountInPEN($0, fallbackRate: rate) })
        }
        .sorted {
            $0.mostRecent == $1.mostRecent ? $0.merchant < $1.merchant : $0.mostRecent > $1.mostRecent
        }
    }

    /// Porcentaje de comercios ya clasificados en el alcance visible. Es la
    /// cifra que hace que valga la pena vaciar la bandeja.
    private func progressFraction(groupCount: Int) -> Double {
        let range = month.interval
        let scopeExpenses = scope == .month
            ? expenses.filter { $0.date >= range.start && $0.date < range.end }
            : expenses
        let merchants = Set(scopeExpenses.map(\.merchant))
        guard !merchants.isEmpty else { return 1 }
        return Double(merchants.count - groupCount) / Double(merchants.count)
    }

    private func suggestion(for group: Group) -> CategorySuggestion? {
        SuggestionEngine.suggest(for: group.merchant, rules: MerchantRules.all())
    }

    var body: some View {
        let groups = self.groups
        let visible = Array(groups.prefix(visibleCount))
        let total = Money.sum(groups) { $0.total }
        let movementCount = groups.reduce(0) { $0 + $1.expenses.count }
        let hasAnyPending = expenses.contains { $0.category == Accounting.unclassified }

        TrackableScrollView(scrollToTopTrigger: $scrollToTopTrigger) {
            VStack(spacing: 0) {
                ShellTitle(title: "Pendientes",
                           subtitle: groups.isEmpty ? nil
                               : "\(movementCount) movimientos en \(groups.count) comercios · "
                                 + Money.format(total))

                if !hasAnyPending {
                    ShellEmptyState(icon: "checkmark.circle",
                                    title: "Pendientes vacío",
                                    message: "Todos tus gastos están clasificados.")
                } else {
                    // El segmento se queda aunque el mes esté al día: la
                    // pestaña existe por lo pendiente de meses anteriores, y
                    // sin él no habría forma de llegar a verlo.
                    ShellSegment(items: [Scope.month, .all], selection: $scope) {
                        $0 == .month ? "Este mes" : "Todo el historial"
                    }
                    .padding(.bottom, 14)

                    if groups.isEmpty {
                        ShellEmptyState(icon: "checkmark.circle",
                                        title: "Este mes está al día",
                                        message: "Lo que falta clasificar es de meses anteriores. Míralo en «Todo el historial».")
                    } else {
                        progressCard(groupCount: groups.count)
                            .padding(.bottom, 12)

                        bulkButton
                            .padding(.bottom, 12)

                        selectionBar(groups: groups)
                            .padding(.bottom, 10)

                        VStack(spacing: 10) {
                            ForEach(visible) { group in
                                groupCard(group)
                            }
                        }
                        .padding(.bottom, 10)

                        if visibleCount < groups.count {
                            loadMoreButton(remaining: groups.count - visibleCount)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, ShellMetrics.contentTopInset)
            .padding(.bottom, selected.isEmpty ? ShellMetrics.contentBottomInset
                                               : ShellMetrics.contentBottomInset + 60)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            progress.update(offset)
        }
        .overlay(alignment: .bottom) {
            if !selected.isEmpty {
                assignBar
                    .padding(.bottom, ShellMetrics.contentBottomInset - 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: scope) { _, _ in
            selected.removeAll()
            visibleCount = Self.pageSize
        }
        .onAppear {
            // Si el mes ya está al día, se abre directamente en lo que queda.
            guard !didPickInitialScope else { return }
            didPickInitialScope = true
            let range = month.interval
            let monthHasPending = expenses.contains {
                $0.category == Accounting.unclassified && $0.date >= range.start && $0.date < range.end
            }
            if !monthHasPending { scope = .all }
        }
        .sheet(isPresented: $showsBulk) {
            BulkClassifyView(onlyThisMonth: scope == .month)
        }
        .sheet(item: $assigning) { target in
            AssignCategorySheet(context: target.context, history: expenses) { category, alsoPast in
                apply(category, to: target.merchants, includingPast: alsoPast)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
    }

    // MARK: - Progreso

    private func progressCard(groupCount: Int) -> some View {
        let fraction = progressFraction(groupCount: groupCount)

        return ShellCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Clasificado")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.label)
                    Spacer()
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accent.onSurface(scheme))
                }

                PaceBar(fraction: fraction, expected: nil, status: .ok, height: 6)
            }
        }
    }

    // MARK: - En bloque

    /// La entrada a la clasificación masiva (`5j`): todos los comercios con
    /// su destino sugerido, aceptados de una vez.
    private var bulkButton: some View {
        Button { showsBulk = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                Text("Clasificar en bloque")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(accent.onSurface(scheme))
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(accent.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selección

    @ViewBuilder
    private func selectionBar(groups: [Group]) -> some View {
        let allSelected = selected.count == groups.count

        HStack {
            Text(selected.isEmpty ? "Toca un comercio para elegirlo"
                                  : "\(selected.count) seleccionados")
                .font(.system(size: 12.5))
                .foregroundStyle(palette.secondaryLabel)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selected = allSelected ? [] : Set(groups.map(\.merchant))
                }
            } label: {
                Text(allSelected ? "Quitar selección" : "Seleccionar todo")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(accent.onSurface(scheme))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
    }

    private var assignBar: some View {
        Button {
            assigning = AssignTarget(merchants: Array(selected), groups: groups)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "tag")
                    .font(.system(size: 15, weight: .semibold))
                Text("Asignar categoría a \(selected.count)")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 22)
            .frame(height: 48)
            .background(accent.color, in: Capsule())
            .shadow(color: accent.color.opacity(0.3), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grupo

    private func groupCard(_ group: Group) -> some View {
        let isSelected = selected.contains(group.merchant)
        let hint = suggestion(for: group)

        return ShellCard(padding: 0) {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if isSelected { selected.remove(group.merchant) }
                        else { selected.insert(group.merchant) }
                    }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .strokeBorder(isSelected ? accent.color : palette.hairline, lineWidth: isSelected ? 0 : 1.5)
                                .background(Circle().fill(isSelected ? accent.color : Color.clear))
                                .frame(width: 24, height: 24)

                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color.white)
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(Accounting.displayName(group.merchant))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(palette.label)
                                .lineLimit(1)

                            Text(group.expenses.count == 1 ? "1 movimiento"
                                                           : "\(group.expenses.count) movimientos")
                                .font(.system(size: 12.5))
                                .foregroundStyle(palette.secondaryLabel)
                        }

                        Spacer(minLength: 8)

                        Text(Money.format(group.total))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(palette.label)
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // La sugerencia sólo aparece en el grupo elegido: en todos a
                // la vez sería una pantalla de botones verdes compitiendo.
                if isSelected, let hint, hint.confidence >= 0.45 {
                    suggestionRow(group: group, hint: hint)
                }
            }
        }
    }

    private func suggestionRow(group: Group, hint: CategorySuggestion) -> some View {
        HStack(spacing: 8) {
            Text("¿Es")
                .font(.system(size: 13))
                .foregroundStyle(palette.secondaryLabel)

            HStack(spacing: 5) {
                Image(systemName: CategoryStyle.icon(for: hint.category))
                    .font(.system(size: 11, weight: .semibold))
                Text(hint.category)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(CategoryStyle.color(for: hint.category, accent: accent.color))

            Text("?")
                .font(.system(size: 13))
                .foregroundStyle(palette.secondaryLabel)

            Spacer(minLength: 6)

            Button {
                apply(hint.category, to: [group.merchant], includingPast: true)
            } label: {
                Text("Sí")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 18)
                    .frame(height: 30)
                    .background(palette.positive, in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                assigning = AssignTarget(merchants: [group.merchant], groups: groups)
            } label: {
                Text("Otra")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.secondaryLabel)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(palette.neutralSurface, in: Capsule())
                    .overlay(Capsule().stroke(palette.hairline, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    // MARK: - Aplicar

    /// Desde Pendientes el usuario está ordenando el comercio entero, así que
    /// lo normal es arrastrar también su historial — al revés que desde una
    /// fila suelta, donde tocar el pasado sería una sorpresa.
    private func apply(_ category: String, to merchants: [String], includingPast: Bool) {
        for merchant in merchants {
            MerchantRules.set(category, for: merchant)

            let targets = includingPast
                ? expenses.filter { $0.merchant == merchant && $0.category == Accounting.unclassified }
                : unclassified.filter { $0.merchant == merchant }

            for expense in targets {
                expense.category = category
                ExpenseEditStore.record(expense, category: category)
            }
        }
        try? modelContext.save()

        withAnimation(.easeInOut(duration: 0.25)) {
            for merchant in merchants { selected.remove(merchant) }
        }
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

    // MARK: - Tipos

    struct Group: Identifiable {
        let merchant: String
        let expenses: [Expense]
        let total: Double
        var id: String { merchant }
        var mostRecent: Date { expenses.first?.date ?? .distantPast }
    }

    /// Lo que la hoja de asignar necesita saber: uno o varios comercios.
    struct AssignTarget: Identifiable {
        let merchants: [String]
        let groups: [Group]
        var id: String { merchants.joined(separator: "|") }

        var context: AssignCategoryContext {
            let selected = groups.filter { merchants.contains($0.merchant) }
            let movements = selected.reduce(0) { $0 + $1.expenses.count }
            let total = Money.sum(selected) { $0.total }

            if merchants.count == 1, let only = selected.first {
                return .merchant(only.merchant, movements: movements, total: total)
            }
            return AssignCategoryContext(
                merchant: nil,
                title: "\(merchants.count) comercios",
                subtitle: "\(movements) movimientos · " + Money.format(total),
                amount: total,
                ruleScope: .past
            )
        }
    }
}
