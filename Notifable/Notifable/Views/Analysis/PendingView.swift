import SwiftUI
import SwiftData

/// Pendientes (`2c`): los comercios que la app no supo clasificar.
///
/// Su tarjeta en el dashboard **sólo existe mientras quedan pendientes**
/// (`3d`); al llegar a cero, Etiquetas ocupa su sitio: un destino permanente
/// que casi siempre dice «nada pendiente» es ruido.
///
/// La sugerencia va **dentro del grupo**, no como banner aparte. Antes vivía
/// arriba, en una tarjeta propia, y había que acordarse de a qué comercio se
/// refería mientras se miraba la lista.
///
/// Cada comercio se despliega con la flecha de la derecha y muestra sus
/// movimientos, que se eligen uno a uno: no todo lo de un comercio va siempre
/// a la misma categoría. La selección es por movimiento; tocar el comercio
/// elige (o suelta) todos los suyos.
struct PendingView: View {
    @Binding var scrollToTopTrigger: Bool
    let progress: ScrollProgress

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @StateObject private var rates = ExchangeRateService.shared

    @State private var scope: Scope = .month
    /// Movimientos elegidos.
    @State private var selected: Set<UUID> = []
    @State private var expanded: Set<String> = []
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
        // Un traslado entre tus cuentas no se clasifica: no es gasto.
        let all = expenses.filter { $0.category == Accounting.unclassified && $0.countsAsSpending }
        guard scope == .month else { return all }
        let range = month.interval
        return all.filter { $0.date >= range.start && $0.date < range.end }
    }

    private var groups: [Group] {
        let calendar = Period.calendar
        var grouped: [String: [Expense]] = [:]
        for expense in unclassified {
            let startOfMonth = calendar.dateInterval(of: .month, for: expense.date)?.start ?? expense.date
            let key = expense.merchant + "|" + "\(startOfMonth.timeIntervalSince1970)"
            grouped[key, default: []].append(expense)
        }

        return grouped.map { key, items in
            let components = key.components(separatedBy: "|")
            let merchant = components[0]
            let timeInterval = components.count > 1 ? TimeInterval(components[1]) ?? 0 : 0
            let monthStart = Date(timeIntervalSince1970: timeInterval)
            
            return Group(merchant: merchant,
                         monthStart: monthStart,
                         expenses: items.sorted { $0.date > $1.date },
                         total: Money.sum(items) { Accounting.netCostInPEN($0, fallbackRate: rate) })
        }
        .sorted {
            $0.monthStart == $1.monthStart 
                ? ($0.mostRecent == $1.mostRecent ? $0.merchant < $1.merchant : $0.mostRecent > $1.mostRecent)
                : $0.monthStart > $1.monthStart
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
        let hasAnyPending = expenses.contains { $0.category == Accounting.unclassified && $0.countsAsSpending }

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
                    // Movimientos en los dos: son las mismas cifras que la
                    // tarjeta del dashboard («N de este mes · M de meses
                    // anteriores»), y el historial es su suma.
                    let allPending = expenses.filter { $0.category == Accounting.unclassified && $0.countsAsSpending }
                    let range = month.interval
                    let monthCount = allPending.filter { $0.date >= range.start && $0.date < range.end }.count
                    ShellSegment(items: [Scope.month, .all], selection: $scope, tint: accent.color) {
                        $0 == .month ? "Este mes (\(monthCount))" : "Todo el historial (\(allPending.count))"
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
                            ForEach(Array(visible.enumerated()), id: \.element.id) { index, group in
                                let isFirstOfMonth = index == 0 || visible[index - 1].monthStart != group.monthStart
                                if isFirstOfMonth {
                                    let monthName = Period.spanishMonthName(for: group.monthStart)
                                    let year = Period.calendar.component(.year, from: group.monthStart)
                                    ShellSectionHeader(title: "\(monthName) \(year)")
                                        .padding(.top, index == 0 ? 0 : 16)
                                        .padding(.horizontal, 4)
                                }
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
            .padding(.horizontal, ShellMetrics.sideInset)
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
                $0.category == Accounting.unclassified && $0.countsAsSpending
                    && $0.date >= range.start && $0.date < range.end
            }
            if !monthHasPending { scope = .all }
        }
        .sheet(isPresented: $showsBulk) {
            BulkClassifyView(onlyThisMonth: scope == .month)
        }
        .sheet(item: $assigning) { target in
            AssignCategorySheet(context: target.context, history: expenses) { category, flag in
                apply(category, to: target.ids, flag: flag)
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
        let allIDs = Set(groups.flatMap { $0.expenses.map(\.id) })
        let allSelected = !allIDs.isEmpty && allIDs.isSubset(of: selected)

        HStack {
            Text(selected.isEmpty ? "Toca un comercio o despliégalo con la flecha"
                                  : selected.count == 1 ? "1 movimiento elegido"
                                  : "\(selected.count) movimientos elegidos")
                .font(.system(size: 12.5))
                .foregroundStyle(palette.secondaryLabel)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selected = allSelected ? [] : allIDs
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
            assigning = AssignTarget(ids: selected, groups: groups)
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
        let ids = Set(group.expenses.map(\.id))
        let picked = ids.intersection(selected).count
        let state: Check = picked == 0 ? .off : picked == ids.count ? .on : .partial
        let isExpanded = expanded.contains(group.merchant)
        let hint = suggestion(for: group)

        return ShellCard(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if state == .on { selected.subtract(ids) } else { selected.formUnion(ids) }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            checkmark(state, size: 24)

                            if let sample = group.expenses.first {
                                let look = sourceLook(sample)
                                MovementIcon(icon: look.icon, color: look.color, size: 36)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(Accounting.displayName(group.merchant))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(palette.label)
                                    .lineLimit(1)

                                Text(countLabel(group, picked: picked))
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(palette.secondaryLabel)
                            }

                            Spacer(minLength: 8)

                            Text(Money.format(group.total))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(palette.label)
                        }
                        .padding(.leading, 14)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            if isExpanded { expanded.remove(group.merchant) }
                            else { expanded.insert(group.merchant) }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(accent.onSurface(scheme))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .frame(width: 30, height: 30)
                            .background(accent.color.opacity(0.10), in: Circle())
                            .padding(.leading, 10)
                            .padding(.trailing, 12)
                            .frame(maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isExpanded ? "Ocultar movimientos" : "Ver movimientos")
                }
                .fixedSize(horizontal: false, vertical: true)

                if isExpanded {
                    VStack(spacing: 0) {
                        ForEach(group.expenses) { expense in
                            Rectangle().fill(palette.hairline).frame(height: 0.5)
                                .padding(.leading, 50)
                            movementRow(expense)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // La sugerencia sólo aparece en el grupo elegido: en todos a
                // la vez sería una pantalla de botones verdes compitiendo.
                if picked > 0, let hint, hint.confidence >= 0.45 {
                    suggestionRow(group: group, hint: hint)
                        .padding(.top, isExpanded ? 12 : 0)
                }
            }
        }
    }

    private func movementRow(_ expense: Expense) -> some View {
        let isOn = selected.contains(expense.id)

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isOn { selected.remove(expense.id) } else { selected.insert(expense.id) }
            }
        } label: {
            HStack(spacing: 12) {
                checkmark(isOn ? .on : .off, size: 20)
                    .frame(width: 24)

                Text(expense.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute().locale(Locale(identifier: "es_ES")))
                        .capitalized(with: Locale(identifier: "es_ES")))
                    .font(.system(size: 14))
                    .foregroundStyle(palette.label)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(Money.format(expense.amount, currency: expense.currency))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.secondaryLabel)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(isOn ? accent.color.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private enum Check { case off, partial, on }

    private func checkmark(_ state: Check, size: CGFloat) -> some View {
        let filled = state != .off
        return ZStack {
            Circle()
                .strokeBorder(filled ? accent.color : palette.hairline, lineWidth: filled ? 0 : 1.5)
                .background(Circle().fill(filled ? accent.color : Color.clear))
                .frame(width: size, height: size)

            if filled {
                Image(systemName: state == .on ? "checkmark" : "minus")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(Color.white)
            }
        }
    }

    private func countLabel(_ group: Group, picked: Int) -> String {
        let count = group.expenses.count
        let base = count == 1 ? "1 movimiento" : "\(count) movimientos"
        let source = group.expenses.first.flatMap(MovementStyle.source(for:))
        guard picked > 0, picked < count else { return source.map { $0 + " · " + base } ?? base }
        return "\(picked) de \(count) elegidos"
    }

    /// De dónde salió el dinero, que es lo único que distingue a un yapeo de
    /// un plin o de una compra con tarjeta: todavía no tienen categoría, así
    /// que el ícono de categoría sería el mismo cajón para todos.
    private func sourceLook(_ expense: Expense) -> (icon: String, color: Color) {
        let icon = MovementStyle.icon(for: expense)
        if icon == CategoryStyle.icon(for: Accounting.unclassified) {
            let hasCard = !(expense.cardLastDigits ?? "").isEmpty
            return (hasCard ? "creditcard.fill" : "questionmark", palette.secondaryLabel)
        }
        return (icon, MovementStyle.color(for: expense, accent: accent.color, scheme: scheme))
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
                apply(hint.category, to: pickedIDs(in: group), flag: false)
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
                assigning = AssignTarget(ids: pickedIDs(in: group), groups: groups)
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

    private func pickedIDs(in group: Group) -> Set<UUID> {
        Set(group.expenses.map(\.id)).intersection(selected)
    }

    /// Un comercio elegido entero deja su regla, y `flag` («Asignar también
    /// los anteriores», apagado por defecto) arrastra además su historial
    /// fuera del alcance visible. Si sólo se eligieron algunos de sus
    /// movimientos, se clasifican esos y nada más; ahí `flag` es «No volver a
    /// preguntar» y decide si queda la regla.
    private func apply(_ category: String, to ids: Set<UUID>, flag: Bool) {
        for group in groups {
            let picked = group.expenses.filter { ids.contains($0.id) }
            guard !picked.isEmpty else { continue }
            let whole = picked.count == group.expenses.count

            if whole || flag { MerchantRules.set(category, for: group.merchant) }

            let targets = whole && flag
                ? expenses.filter { $0.merchant == group.merchant && $0.category == Accounting.unclassified }
                : picked

            for expense in targets {
                expense.category = category
                ExpenseEditStore.record(expense, category: category)
            }
        }
        try? modelContext.save()

        withAnimation(.easeInOut(duration: 0.25)) {
            selected.subtract(ids)
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
        let monthStart: Date
        let expenses: [Expense]
        let total: Double
        var id: String { merchant + "-" + monthStart.description }
        var mostRecent: Date { expenses.first?.date ?? .distantPast }
    }

    /// Lo que la hoja de asignar necesita saber: los movimientos elegidos,
    /// de uno o varios comercios.
    struct AssignTarget: Identifiable {
        let ids: Set<UUID>
        let groups: [Group]
        let id = UUID()

        var context: AssignCategoryContext {
            let touched = groups.compactMap { group -> (Group, [Expense])? in
                let picked = group.expenses.filter { ids.contains($0.id) }
                return picked.isEmpty ? nil : (group, picked)
            }
            let movements = touched.reduce(0) { $0 + $1.1.count }
            let total = Money.sum(touched.flatMap(\.1)) { Accounting.netCostInPEN($0, fallbackRate: ExchangeRateService.shared.usdToPenRate) }

            if touched.count == 1, case let (group, picked)? = touched.first {
                if picked.count == group.expenses.count {
                    return .merchant(group.merchant, movements: movements, total: total)
                }
                // Parte de un comercio: sin historial que arrastrar; el
                // interruptor ofrece la regla para lo que llegue.
                return AssignCategoryContext(
                    merchant: group.merchant,
                    title: Accounting.displayName(group.merchant),
                    subtitle: "\(movements) de \(group.expenses.count) movimientos · " + Money.format(total),
                    amount: nil,
                    ruleScope: .forward
                )
            }
            return AssignCategoryContext(
                merchant: nil,
                title: touched.count == 1 ? "1 comercio" : "\(touched.count) comercios",
                subtitle: "\(movements) movimientos · " + Money.format(total),
                amount: total,
                ruleScope: .past
            )
        }
    }
}
