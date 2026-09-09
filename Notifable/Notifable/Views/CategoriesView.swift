import SwiftUI
import SwiftData
import Charts

enum CategoryTab: String, CaseIterable, Identifiable {
    var id: String { rawValue }

    case misCategorias = "Mis Categorías"
    case inbox = "Pendientes"
}

/// Todo el historial vs. sólo el periodo filtrado, en la pestaña Pendientes.
///
/// Antes `InboxProgressCard` contaba sobre todo `expenses` mientras la lista
/// de abajo sólo mostraba el periodo filtrado: el mismo comercio "faltante"
/// aparecía con números distintos según dónde se mirara. La franja de alcance
/// hace explícita la diferencia en vez de escondrla.
enum PendingScope: Equatable { case period, all }

/// Un comercio de Pendientes con sus gastos sin clasificar.
///
/// Antes esto era una tupla con etiquetas. El comprobador de tipos de Swift
/// tarda un tiempo exponencial en resolver tuplas etiquetadas dentro de cadenas
/// `map`/`sorted`, y acababa rindiéndose ("unable to type-check this expression
/// in reasonable time"). Un `struct` con tipos explícitos se resuelve al vuelo.
struct InboxGroup: Identifiable {
    let merchant: String
    let expenses: [Expense]
    let total: Double
    var id: String { merchant }

    /// `expenses` siempre llega ordenado por fecha descendente, así que el
    /// primero es el más reciente — lo que decide el orden de Pendientes.
    var mostRecentDate: Date { expenses.first?.date ?? .distantPast }
}

/// Una fila de "Mis Categorías": el estado de su límite más lo que hace falta
/// para expandirla (sus comercios del periodo). Sustituye a `CategoryRow` +
/// `CategoryLimitStatus` sueltos — antes cada categoría se calculaba dos veces
/// porque la fila de límite y la tarjeta expandible vivían por separado.
struct UnifiedCategoryData: Identifiable {
    let category: String
    let status: CategoryLimitStatus
    let spent: Double
    let merchants: [PeriodTotals.MerchantTotal]
    var id: String { category }
}

struct MerchantWrapper: Identifiable {
    let id: String
}

struct ToastNotification: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let targetTab: CategoryTab
    let targetID: String
    let systemImage: String
    let color: Color
}

struct CategoriesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Environment(\.colorScheme) var colorScheme

    @Binding var scrollToTopTrigger: Bool

    @StateObject private var exchangeRateService = ExchangeRateService.shared

    /// El mismo `Period` que Resumen y Ritmo.
    @AppStorage("period") private var period = Period()

    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue

    var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .purple }
    var themeColor: Color { accent.color }

    /// Paleta con contraste verificado. Sustituye a `Color.primary.opacity(0.05)`,
    /// que en modo claro es #F2F2F2 sobre blanco: 4 % de diferencia de luminancia,
    /// invisible al sol o con el brillo bajo.
    private var palette: Palette { Palette(colorScheme) }

    /// En AppStorage, no en @State: el banner de Resumen necesita poder dejar
    /// la pestaña abierta en Pendientes antes de navegar hasta aquí.
    @AppStorage("categoriesSegment") private var selectedTab: CategoryTab = .misCategorias

    @State private var pendingScope: PendingScope = .period

    /// Pendientes pagina de 20 en 20 — con muchos comercios sin clasificar,
    /// renderizar la lista entera de una es lo que hacía lento el desplegable.
    @State private var visiblePendingCount = 20
    @State private var selectedMerchantToCategorize: MerchantWrapper?
    @State private var selectedMerchantToUncategorize: (merchant: String, category: String)?
    @State private var expandedMerchants: Set<String> = []
    @State private var expandedCategories: Set<String> = []
    @State private var activeToasts: [ToastNotification] = []
    @State private var highlightedID: String?
    @State private var searchText = ""
    @State private var focusedCategory: String?
    @State private var showClassifyFlow = false

    /// Selección mixta de Pendientes: comercios completos y movimientos sueltos
    /// de un comercio que no está seleccionado entero.
    @State private var selectedMerchants: Set<String> = []
    @State private var selectedMovementIDs: Set<Expense.ID> = []
    @State private var showAssignSelection = false

    /// Aplicar una categoría es reversible: en vez de un alert previo, un toast
    /// con "Deshacer" durante unos segundos.
    @State private var pendingUndo: UndoToken?
    /// Aviso posterior a asignar: el límite nunca se advierte **antes**, para no
    /// convertirlo en un obstáculo; se dice después, junto al "Deshacer".
    @State private var limitNote: String?
    @State private var editingCategory: CategoryWrapper?
    
    /// Crear categoría abre el **mismo** `CategorySettingsView` que se usa al
    /// crearla desde el sheet de asignar (nombre, color, límite y lo demás). El
    /// alert de sólo-nombre que había antes creaba categorías a medias: sin
    /// color y sin límite, y había que volver a entrar a configurarlas.
    @State private var creatingCategory = false

    /// No-nil mientras corre una reclasificación en bloque o una edición de
    /// categoría que toca todo el historial — el overlay con el spinner es la
    /// única señal de que el toque sí se registró (`Batching`).
    @State private var bulkOperationLabel: String?

    @StateObject private var budgets = CategoryBudgetStore.shared
    @StateObject private var catalog = CategoryCatalog.shared

    @AppStorage(NotificationManager.categoryLimitEnabledKey) private var limitAlertsEnabled = true
    @Namespace private var animation

    // MARK: - Totales
    //
    // Todo viene de `Accounting.totals`: el mismo criterio y las mismas cifras
    // que Resumen. Antes esta vista sumaba `amount` mientras Resumen sumaba
    // `unpaidAmount`, y cada gasto en USD se convertía por separado antes de
    // sumar (ACCOUNTING.md §2 y §10).

    var totals: PeriodTotals {
        Accounting.totals(expenses: expenses,
                          incomes: [],
                          period: period,
                          usdToPen: exchangeRateService.usdToPenRate)
    }

    func dailySpent(for period: Period) -> [PeriodTotals.DayTotal] {
        Accounting.totals(expenses: expenses,
                          incomes: [],
                          period: period,
                          usdToPen: exchangeRateService.usdToPenRate).dailySpent
    }

    var filteredExpenses: [Expense] {
        period.filter(expenses, by: \.date)
    }

    private var snapshots: [ExpenseSnapshot] { expenses.map(\.accountingSnapshot) }

    /// El límite se mira en el mes en el que estás: si el periodo visible abarca
    /// varios meses manda el más reciente, y filtrar por un día no encoge el
    /// límite del mes, sólo la lista de movimientos.
    private var limitReferenceDate: Date { CategoryLimits.referenceDate(for: period) }

    /// En español siempre, sin importar el idioma del sistema — ver
    /// `Period.spanishMonthName`.
    private var limitMonthLabel: String { Period.spanishMonthName(for: limitReferenceDate) }

    /// Nombra el periodo visible con la misma granularidad que Resumen: si el
    /// filtro es "Día" o "Semana", la pestaña de alcance de Pendientes no
    /// puede seguir diciendo "Este mes" — diría algo que no es lo que se está
    /// mirando. `Period.title` ya resuelve "Hoy"/"Ayer"/el rango de semana;
    /// aquí sólo se prefiere "Esta semana"/"Este mes"/"Este año" cuando el
    /// periodo elegido es, de hecho, el actual.
    private var periodScopeLabel: String {
        let cal = Period.calendar
        let now = Date()
        switch period.granularity {
        case .dia:
            return cal.isDateInToday(period.reference) ? "Hoy" : period.title
        case .semana:
            return cal.isDate(period.reference, equalTo: now, toGranularity: .weekOfYear) ? "Esta semana" : period.title
        case .mes:
            return cal.isDate(period.reference, equalTo: now, toGranularity: .month) ? "Este mes" : period.title
        case .anio:
            return cal.isDate(period.reference, equalTo: now, toGranularity: .year) ? "Este año" : period.title
        case .rango:
            return period.title
        }
    }

    // MARK: - Pendientes (bandeja)

    /// Comercios sin clasificar del periodo filtrado.
    var inboxGroups: [InboxGroup] {
        let totalByMerchant = merchantTotalsByName
        var grouped: [String: [Expense]] = [:]
        for expense in filteredExpenses where expense.category == Accounting.unclassified {
            grouped[expense.merchant, default: []].append(expense)
        }

        var result: [InboxGroup] = []
        result.reserveCapacity(grouped.count)
        for (merchant, items) in grouped {
            result.append(InboxGroup(merchant: merchant,
                                     expenses: items.sorted { $0.date > $1.date },
                                     total: totalByMerchant[merchant]?.total ?? 0))
        }
        return result.sorted { lhs, rhs in
            if lhs.mostRecentDate == rhs.mostRecentDate { return lhs.merchant < rhs.merchant }
            return lhs.mostRecentDate > rhs.mostRecentDate
        }
    }

    /// Comercios pendientes de **todo** el historial, para el badge, el modo
    /// una-por-una, y la franja de alcance.
    var pendingGroups: [InboxGroup] {
        let pending = expenses.filter { $0.category == Accounting.unclassified }
        var grouped: [String: [Expense]] = [:]
        for expense in pending { grouped[expense.merchant, default: []].append(expense) }

        let rate = exchangeRateService.usdToPenRate
        return grouped
            .map { merchant, items in
                let cents = items.reduce(0) { $0 + Accounting.penCents($1.accountingSnapshot, fallbackRate: rate) }
                return InboxGroup(merchant: merchant,
                                  expenses: items.sorted { $0.date > $1.date },
                                  total: Money.value(cents))
            }
            .sorted {
                $0.mostRecentDate == $1.mostRecentDate
                    ? $0.merchant < $1.merchant
                    : $0.mostRecentDate > $1.mostRecentDate
            }
    }

    /// Nombres de los comercios pendientes **dentro** del periodo — para saber
    /// si un comercio de `pendingGroups` queda fuera cuando el alcance es "todo".
    private var periodPendingMerchantNames: Set<String> { Set(inboxGroups.map(\.merchant)) }

    /// Lo que la lista muestra: el periodo filtrado, o todo el historial si el
    /// usuario tocó "Ver todos". Cambiar esto **no** toca el `Period` visible
    /// de Resumen/Categorías — es un alcance local a Pendientes.
    private var visiblePendingGroups: [InboxGroup] {
        let base = pendingScope == .period ? inboxGroups : pendingGroups
        guard !searchText.isEmpty else { return base }
        return base.filter { $0.merchant.localizedCaseInsensitiveContains(searchText) }
    }

    /// Sólo lo visible: el resto se agrega en `loadMorePendingIfNeeded`.
    private var pagedPendingGroups: [InboxGroup] {
        Array(visiblePendingGroups.prefix(visiblePendingCount))
    }

    /// Dispara la siguiente página al acercarse a las últimas tarjetas
    /// renderizadas, antes de que el usuario llegue del todo al final.
    private func loadMorePendingIfNeeded(currentGroup: InboxGroup) {
        guard let index = pagedPendingGroups.firstIndex(where: { $0.merchant == currentGroup.merchant }) else { return }
        if index >= pagedPendingGroups.count - 5, visiblePendingCount < visiblePendingGroups.count {
            visiblePendingCount += 20
        }
    }

    /// Asegura que un comercio esté renderizado antes de hacer scroll hacia
    /// él (toast "enviado a Pendientes"): si cayó fuera de la página actual,
    /// agranda la página lo justo para incluirlo.
    private func revealPendingMerchant(_ merchant: String) {
        guard let index = visiblePendingGroups.firstIndex(where: { $0.merchant == merchant }) else { return }
        if index >= visiblePendingCount {
            visiblePendingCount = index + 20
        }
    }

    /// Comercios pendientes que quedan fuera del periodo filtrado — lo que
    /// anuncia la franja de alcance cuando el alcance es "sólo este periodo".
    private var outOfPeriodGroups: [InboxGroup] {
        let inPeriod = periodPendingMerchantNames
        return pendingGroups.filter { !inPeriod.contains($0.merchant) }
    }

    private var outOfPeriodTotal: Double { Money.sum(outOfPeriodGroups) { $0.total } }

    // MARK: - Progreso de Pendientes (`2d`)
    //
    // Numerador y denominador se leen siempre de la **misma** fuente —el
    // alcance elegido, `pendingScope`— para no repetir el bug que hizo
    // retirar `InboxProgressCard`: contar "clasificados" sobre todo el
    // historial mientras la lista de abajo mostraba sólo el periodo filtrado.

    private var scopedMerchantCount: Int {
        let source = pendingScope == .period ? filteredExpenses : expenses
        return Set(source.map(\.merchant)).count
    }

    private var scopedPendingCount: Int {
        pendingScope == .period ? inboxGroups.count : pendingGroups.count
    }

    private var scopedClassifiedCount: Int { max(0, scopedMerchantCount - scopedPendingCount) }

    private var scopedProgress: Double {
        guard scopedMerchantCount > 0 else { return 0 }
        return Double(scopedClassifiedCount) / Double(scopedMerchantCount)
    }


    private func assignContext(for merchant: String) -> AssignCategoryContext {
        let group = pendingGroups.first { $0.merchant == merchant }
        return AssignCategoryContext.merchant(merchant,
                                              movements: group?.expenses.count ?? 0,
                                              total: group?.total ?? 0)
    }

    func suggestion(for group: InboxGroup) -> CategorySuggestion? {
        SuggestionEngine.suggest(for: group.merchant, rules: MerchantRules.all())
    }

    func frequentCategories(excluding suggestion: CategorySuggestion?) -> [String] {
        SuggestionEngine.frequentCategories(history: expenses, excluding: suggestion?.category)
    }

    /// Comercios cuyo motor propone la misma categoría con confianza alta, y
    /// **sólo si hay 2 o más**: con uno solo ya está la fila de sugerencia
    /// normal, no hace falta un bloque aparte.
    private var suggestionBuckets: [SuggestionBucket] {
        var byCategory: [String: [InboxGroup]] = [:]
        for group in visiblePendingGroups {
            guard let hint = suggestion(for: group), hint.confidence >= 0.7 else { continue }
            byCategory[hint.category, default: []].append(group)
        }
        return byCategory
            .filter { $0.value.count >= 2 }
            .map { SuggestionBucket(category: $0.key, merchants: $0.value) }
            .sorted { lhs, rhs in
                lhs.merchants.count == rhs.merchants.count ? lhs.category < rhs.category : lhs.merchants.count > rhs.merchants.count
            }
    }

    // MARK: - Selección de Pendientes

    private var isAllSelected: Bool {
        !visiblePendingGroups.isEmpty && visiblePendingGroups.allSatisfy { selectedMerchants.contains($0.merchant) }
    }

    private func toggleSelectAll() {
        if isAllSelected {
            for group in visiblePendingGroups { selectedMerchants.remove(group.merchant) }
        } else {
            for group in visiblePendingGroups {
                selectedMerchants.insert(group.merchant)
                for expense in group.expenses { selectedMovementIDs.remove(expense.id) }
            }
        }
    }

    /// Seleccionar el comercio completo absorbe cualquier movimiento suelto que
    /// tuviera marcado: ya viaja cubierto por la selección del comercio.
    private func toggleMerchantSelection(_ merchant: String) {
        if selectedMerchants.contains(merchant) {
            selectedMerchants.remove(merchant)
        } else {
            selectedMerchants.insert(merchant)
            for expense in expenses where expense.merchant == merchant {
                selectedMovementIDs.remove(expense.id)
            }
        }
    }

    private func toggleMovementSelection(_ id: Expense.ID) {
        if selectedMovementIDs.contains(id) {
            selectedMovementIDs.remove(id)
        } else {
            selectedMovementIDs.insert(id)
        }
    }

    private func clearSelection() {
        selectedMerchants.removeAll()
        selectedMovementIDs.removeAll()
    }

    private var selectionExpenseIDs: Set<UUID> {
        var ids = selectedMovementIDs
        for expense in expenses where selectedMerchants.contains(expense.merchant) && expense.category == Accounting.unclassified {
            ids.insert(expense.id)
        }
        return ids
    }

    private var selectionCount: Int { selectedMerchants.count + selectedMovementIDs.count }

    private var selectionTotalAmount: Double {
        let rate = exchangeRateService.usdToPenRate
        let cents = expenses
            .filter { selectionExpenseIDs.contains($0.id) }
            .reduce(0) { $0 + Accounting.penCents($1.accountingSnapshot, fallbackRate: rate) }
        return Money.value(cents)
    }

    private var selectionTitle: String {
        selectionCount == 1 ? "1 seleccionado" : "\(selectionCount) seleccionados"
    }

    private var selectionSheetTitle: String {
        if selectedMovementIDs.isEmpty, selectedMerchants.count == 1, let name = selectedMerchants.first {
            return "Clasificar " + Accounting.displayName(name)
        }
        return "Clasificar \(selectionCount) elementos"
    }

    private var merchantTotalsByName: [String: PeriodTotals.MerchantTotal] {
        var map: [String: PeriodTotals.MerchantTotal] = [:]
        for item in totals.byMerchant { map[item.merchant] = item }
        return map
    }

    @ViewBuilder
    private func merchantCard(for group: InboxGroup) -> some View {
        let hint = suggestion(for: group)
        InboxMerchantCard(
            group: group,
            suggestion: hint,
            frequentCategories: frequentCategories(excluding: hint),
            isSelected: selectedMerchants.contains(group.merchant),
            selectedMovementIDs: selectedMovementIDs,
            isExpanded: expandedMerchants.contains(group.merchant),
            isHighlighted: highlightedID == group.merchant,
            isOutOfPeriod: pendingScope == .all && !periodPendingMerchantNames.contains(group.merchant),
            onToggleSelect: { toggleMerchantSelection(group.merchant) },
            onToggleExpand: { toggleMerchantExpand(group.merchant) },
            onToggleMovement: { toggleMovementSelection($0) },
            onPick: { apply($0, to: group.merchant) },
            onOther: { selectedMerchantToCategorize = MerchantWrapper(id: group.merchant) }
        )
        .id(group.merchant)
    }

    private func toggleMerchantExpand(_ merchant: String) {
        withAnimation(.spring) {
            if expandedMerchants.contains(merchant) {
                expandedMerchants.remove(merchant)
            } else {
                expandedMerchants.removeAll()      // sólo uno expandido a la vez
                expandedMerchants.insert(merchant)
            }
        }
    }

    // MARK: - Asignar (una pieza, un lote, o la selección completa)

    /// Guarda la regla, reclasifica lo pasado y ofrece deshacer.
    ///
    /// Con `createRule: false` sólo mueve los movimientos pendientes de ese
    /// comercio: es lo que pide `6a` cuando el usuario apaga el interruptor.
    func apply(_ category: String, to merchant: String, createRule: Bool = true) {
        let token: UndoToken
        if createRule {
            token = MerchantRules.apply(category, to: merchant, in: expenses)
        } else {
            let ids = Set(expenses.filter { $0.merchant == merchant && $0.category == Accounting.unclassified }.map(\.id))
            let previous = MerchantRules.applyToMovements(ids, category: category, in: expenses)
            token = UndoToken(summary: Accounting.displayName(merchant) + " → " + category,
                              category: category,
                              previousCategories: previous,
                              previousRules: [:])
        }
        try? modelContext.save()
        limitNote = assignmentNote(for: category)
        refreshLimitNotices()
        expandedMerchants.remove(merchant)
        presentUndo(token)
    }

    /// "Aceptar todas" (`2d`): resuelve todos los lotes fuertes del motor de
    /// una sola vez, cada uno con su propia categoría, en un solo toast con
    /// deshacer. Antes cada lote tenía su propio "Aceptar N" — `presentUndo`
    /// sólo guarda un token a la vez, así que aceptar dos lotes por separado
    /// hacía que deshacer el segundo dejara el primero aplicado sin aviso.
    /// Fusionando los diccionarios de "antes" en un único `UndoToken` antes de
    /// presentarlo, deshacer revierte los dos lotes juntos.
    ///
    /// `async` + `Batching`: con decenas de comercios en varios lotes, aplicar
    /// todo de un tirón congelaba la pantalla sin ningún aviso.
    func applyAllSuggestionBuckets() async {
        let buckets = suggestionBuckets
        guard !buckets.isEmpty else { return }

        var previousCategories: [UUID: String] = [:]
        var previousRules: [String: String?] = [:]
        let entries = buckets.flatMap { bucket in bucket.merchants.map { (bucket.category, $0.merchant) } }

        await Batching.run(entries, chunkSize: 20) { category, merchant in
            let (previous, rule) = MerchantRules.applyRule(category, to: merchant, in: expenses)
            previousCategories.merge(previous) { current, _ in current }
            previousRules[merchant] = rule
        }
        try? modelContext.save()

        let merchantCount = entries.count
        let summary = merchantCount == 1 ? "1 comercio clasificado" : "\(merchantCount) comercios clasificados"

        refreshLimitNotices()
        presentUndo(UndoToken(summary: summary,
                              category: buckets.first?.category ?? "",
                              previousCategories: previousCategories,
                              previousRules: previousRules))
    }

    /// Aplica la categoría a la selección mixta de Pendientes: los comercios
    /// completos crean/actualizan su regla; los movimientos sueltos —los que no
    /// pertenecen a un comercio también seleccionado— se reclasifican sin regla,
    /// para que el próximo movimiento del mismo comercio vuelva a Pendientes.
    ///
    /// `async` + `Batching`: "Seleccionar todos" en Pendientes puede juntar
    /// cientos de comercios distintos; sin ceder el hilo entre ellos, la
    /// pantalla se congelaba justo cuando el usuario acababa de tocar "Asignar".
    func applySelection(category: String) async {
        var previousCategories: [UUID: String] = [:]
        var previousRules: [String: String?] = [:]

        await Batching.run(Array(selectedMerchants), chunkSize: 20) { merchant in
            let (previous, rule) = MerchantRules.applyRule(category, to: merchant, in: expenses)
            previousCategories.merge(previous) { current, _ in current }
            previousRules[merchant] = rule
        }

        let coveredIDs = Set(expenses.filter { selectedMerchants.contains($0.merchant) }.map(\.id))
        let looseIDs = selectedMovementIDs.subtracting(coveredIDs)
        let previousLoose = MerchantRules.applyToMovements(looseIDs, category: category, in: expenses)
        previousCategories.merge(previousLoose) { current, _ in current }

        try? modelContext.save()

        let count = selectedMerchants.count + looseIDs.count
        let summary: String
        if count == 1, let onlyMerchant = selectedMerchants.first {
            summary = Accounting.displayName(onlyMerchant) + " → " + category
        } else {
            summary = "\(count) elementos → " + category
        }

        limitNote = assignmentNote(for: category)
        refreshLimitNotices()
        clearSelection()
        presentUndo(UndoToken(summary: summary,
                              category: category,
                              previousCategories: previousCategories,
                              previousRules: previousRules))
    }

    private func presentUndo(_ token: UndoToken) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            pendingUndo = token
        }

        // El toast se retira solo a los 4 s, salvo que ya lo hayan deshecho.
        let id = token.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation(.easeInOut) {
                if pendingUndo?.id == id {
                    pendingUndo = nil
                    limitNote = nil
                }
            }
        }
    }

    /// El color de la lista cuenta la historia con la app abierta; el aviso es
    /// para cuando no lo está. `NotificationManager` se encarga de no repetirlo
    /// dentro del mismo ciclo.
    private func refreshLimitNotices() {
        NotificationManager.shared.updateCategoryLimitNotices(unifiedRows.map(\.status), enabled: limitAlertsEnabled)
    }

    private func undoLastApply() {
        guard let token = pendingUndo else { return }
        withAnimation(.spring) {
            MerchantRules.undo(token, in: expenses)
            try? modelContext.save()
            pendingUndo = nil
            limitNote = nil
        }
    }

    /// Lo que dice el toast después de asignar cuando la categoría queda pasada
    /// de su límite. Antes de asignar no se advierte nada: el límite avisa, no
    /// estorba.
    private func assignmentNote(for category: String) -> String? {
        let status = limitStatus(for: category)
        guard status.hasLimit else { return nil }
        if status.isOver {
            return category + " queda " + Money.formatCompact(status.overBy) + " arriba de su límite."
        }
        if status.level == .cerca {
            return "A " + category + " le quedan " + Money.formatCompact(status.remaining) + " de su límite."
        }
        return nil
    }

    private func limitStatus(for category: String) -> CategoryLimitStatus {
        CategoryLimits.status(category: category,
                              budget: budgets.budget(for: category),
                              expenses: snapshots,
                              on: limitReferenceDate,
                              usdToPen: exchangeRateService.usdToPenRate)
    }

    /// El toast de deshacer. Sin alert previo: aplicar es reversible.
    private var undoToast: some View {
        Group {
            if let token = pendingUndo {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(palette.positive)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(token.summary)
                            .font(.subheadline)
                            .foregroundStyle(palette.label)
                            .lineLimit(1)
                        if let limitNote {
                            Text(limitNote)
                                .font(.caption)
                                .foregroundStyle(palette.secondaryLabel)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                    Button("Deshacer") { undoLastApply() }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(themeColor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(palette.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(palette.hairline, lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    /// Aparece si hay cualquier selección — comercios o movimientos sueltos.
    private var selectionBar: some View {
        HStack(spacing: 10) {
            Button { clearSelection() } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.secondaryLabel)
                    .frame(width: 28, height: 28)
                    .background(palette.track)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(selectionTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.label)
                Text(Money.format(selectionTotalAmount))
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
            }

            Spacer(minLength: 0)

            Button { showAssignSelection = true } label: {
                Text("Asignar a…")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(themeColor)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(palette.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(palette.hairline, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
        .padding(.horizontal, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    var body: some View {
        ScrollViewReader { proxy in
            TrackableScrollView(scrollToTopTrigger: $scrollToTopTrigger) {
                VStack(spacing: 24) {
                    // 1. Periodo: una sola fila, compartida con las otras pestañas.
                    PeriodHeader(period: $period, dailySpent: dailySpent(for:))
                        .id("TOP")

                    // 2. Segmented Picker (Mis Categorías vs Pendientes)
                    segmentedControl

                    // 3. Lista de Categorías o Pendientes
                    if selectedTab == .misCategorias {
                        misCategoriasListView
                    } else {
                        pendingView
                    }
                }
                .padding(.bottom, 100)
            }
            .overlay(alignment: .bottomTrailing) {
                // Toast Notifications flotantes (Apilados)
                VStack(alignment: .trailing, spacing: 10) {
                    ForEach(activeToasts) { toast in
                        Button(action: {
                            let targetTab = toast.targetTab
                            let targetID = toast.targetID

                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedTab = targetTab
                                activeToasts.removeAll { $0.id == toast.id }

                                // Si vamos a Mis Categorías, expandir la categoría destino
                                if targetTab == .misCategorias {
                                    expandedCategories.insert(targetID)
                                }
                            }

                            // Esperar a que cambie la pestaña y hacer scroll
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                if targetTab == .inbox { revealPendingMerchant(targetID) }
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    proxy.scrollTo(targetID, anchor: .top)
                                }
                                withAnimation(.spring) {
                                    highlightedID = targetID
                                }

                                // Quitar highlight después de unos segundos
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                    withAnimation(.easeOut) {
                                        if highlightedID == targetID {
                                            highlightedID = nil
                                        }
                                    }
                                }
                            }
                        }) {
                            HStack {
                                Image(systemName: toast.systemImage)
                                    .foregroundStyle(toast.color)
                                Text(toast.message)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(colorScheme == .light ? .black : .white)
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundStyle(.gray)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(palette.surfaceElevated)
                                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                            )
                        }
                        .buttonStyle(.plain)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, 110)
                .allowsHitTesting(!activeToasts.isEmpty)
            }
            /// "Aislar en el gráfico" pone el foco y hace scroll hacia arriba,
            /// aunque el usuario esté al fondo de la lista.
            .onChange(of: focusedCategory) { _, newValue in
                guard newValue != nil else { return }
                withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo("TOP", anchor: .top) }
            }
        }
        .onAppear { refreshLimitNotices() }
        .onChange(of: scrollToTopTrigger) { _, _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = .misCategorias
                expandedCategories.removeAll()
                expandedMerchants.removeAll()
                clearSelection()
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab != .inbox { clearSelection() }
        }
        .onChange(of: pendingScope) { _, _ in visiblePendingCount = 20 }
        .onChange(of: searchText) { _, _ in visiblePendingCount = 20 }
        .overlay(alignment: .bottom) {
            Group {
                if pendingUndo != nil {
                    undoToast
                } else if selectionCount > 0 {
                    selectionBar
                }
            }
            .padding(.bottom, 110)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: pendingUndo)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selectionCount)
        }
        .sheet(isPresented: $showClassifyFlow) {
            ClassifyFlowView(
                groups: pendingScope == .period ? inboxGroups : pendingGroups,
                suggestion: { suggestion(for: $0) },
                frequentCategories: { frequentCategories(excluding: $0) },
                onPick: { group, category in apply(category, to: group.merchant) },
                onOther: { group in
                    showClassifyFlow = false
                    selectedMerchantToCategorize = MerchantWrapper(id: group.merchant)
                }
            )
        }
        .sheet(item: $selectedMerchantToCategorize) { wrapper in
            // El mismo componente que el detalle del gasto y el modal de alta:
            // duplicarlo desincronizaría la sugerencia y el saldo del límite.
            AssignCategorySheet(context: assignContext(for: wrapper.id),
                                history: expenses) { category, createRule in
                apply(category, to: wrapper.id, createRule: createRule)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showAssignSelection) {
            // El mismo modal que "Otra +" en una fila suelta: cuadrícula de
            // categorías + crear una nueva, en vez de la lista aparte que
            // tenía la selección múltiple hasta ahora.
            AssignCategorySheet(context: .selection(title: selectionSheetTitle, amount: selectionTotalAmount),
                                history: expenses) { category, _ in
                let count = selectionCount
                bulkOperationLabel = count == 1 ? "Clasificando…" : "Clasificando \(count) elementos…"
                Task {
                    await applySelection(category: category)
                    bulkOperationLabel = nil
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
        .sheet(item: $editingCategory) { wrapper in
            NavigationStack {
                CategorySettingsView(category: wrapper.id, history: expenses)
            }
        }
        .alert("¿Desclasificar Gastos?", isPresented: Binding(
            get: { selectedMerchantToUncategorize != nil },
            set: { if !$0 { selectedMerchantToUncategorize = nil } }
        )) {
            Button("Cancelar", role: .cancel) {
                selectedMerchantToUncategorize = nil
            }
            Button("Desclasificar", role: .destructive) {
                if let target = selectedMerchantToUncategorize {
                    uncategorize(merchant: target.merchant, from: target.category)
                    selectedMerchantToUncategorize = nil
                }
            }
        } message: {
            if let target = selectedMerchantToUncategorize {
                Text("¿Estás seguro de que deseas enviar los gastos de \(target.merchant) a Sin Clasificar?")
            }
        }
        .overlay {
            if let label = bulkOperationLabel {
                bulkProcessingOverlay(label)
            }
        }
    }

    /// El único aviso de que un lote largo (reclasificar una selección, o
    /// tocar todo el historial de una categoría) sigue corriendo: sin esto no
    /// hay ninguna tarea de red que envolver en un spinner, así que sin
    /// ceder el hilo entre lotes (`Batching`) tampoco habría dónde dibujarlo.
    private func bulkProcessingOverlay(_ label: String) -> some View {
        ZStack {
            Color.black.opacity(0.15).ignoresSafeArea()
            VStack(spacing: 10) {
                ProgressView()
                Text(label)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.label)
            }
            .padding(20)
            .background(palette.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
        }
        .transition(.opacity)
    }

    // MARK: - Segmented control

    private var segmentedControl: some View {
        HStack(spacing: 0) {
            ForEach([CategoryTab.misCategorias, CategoryTab.inbox], id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(tab.rawValue)
                        if tab == .inbox, inboxGroups.count > 0 {
                            Text("\(inboxGroups.count)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(selectedTab == tab ? accent.secondaryColor : .white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(selectedTab == tab ? Color.white : Color.white.opacity(0.18))
                                .clipShape(Capsule())
                        }
                    }
                    .font(.subheadline)
                    .fontWeight(selectedTab == tab ? .semibold : .regular)
                    .foregroundStyle(selectedTab == tab ? .white : (colorScheme == .dark ? .white : .black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        ZStack {
                            if selectedTab == tab {
                                Capsule()
                                    .fill(themeColor.opacity(0.8))
                                    .shadow(color: themeColor.opacity(0.3), radius: 8, x: 0, y: 4)
                                    .matchedGeometryEffect(id: "TAB", in: animation)
                            }
                        }
                    )
                }
            }
        }
        .background(palette.surface)
        .clipShape(Capsule())
        .padding(.horizontal)
    }

    // MARK: - Mis Categorías

    /// La barra de reparto de gasto reemplaza la dona: el orden es el mismo que
    /// el de la lista de abajo y el color es el único código que aprender.
    private var distributionSegments: [DistributionSegment] {
        totals.byCategory
            .filter { Money.cents($0.total) > 0 }
            .sorted { Money.cents($0.total) > Money.cents($1.total) }
            .map { DistributionSegment(category: $0.category,
                                       amount: $0.total,
                                       color: CategoryStyle.color(for: $0.category, accent: themeColor)) }
    }

    private var merchantsByCategory: [String: [PeriodTotals.MerchantTotal]] {
        var namesByCategory: [String: Set<String>] = [:]
        for expense in filteredExpenses where expense.category != Accounting.unclassified {
            namesByCategory[expense.category, default: []].insert(expense.merchant)
        }
        let totalByMerchant = merchantTotalsByName
        var result: [String: [PeriodTotals.MerchantTotal]] = [:]
        for (category, names) in namesByCategory {
            var merchants: [PeriodTotals.MerchantTotal] = []
            merchants.reserveCapacity(names.count)
            for name in names {
                if let merchant = totalByMerchant[name] { merchants.append(merchant) }
            }
            merchants.sort { lhs, rhs in
                let l = Money.cents(lhs.total)
                let r = Money.cents(rhs.total)
                return l == r ? lhs.merchant < rhs.merchant : l > r
            }
            result[category] = merchants
        }
        return result
    }

    /// Una sola fila por categoría: sustituye a la fila de límite y a la
    /// tarjeta de categoría expandible que antes vivían por separado y pintaban
    /// lo mismo dos veces.
    ///
    /// Orden: límites pasados primero, luego por fracción de gasto descendente,
    /// luego categorías con límite sin pasar, y al final las sin límite
    /// (ordenadas entre sí por gasto del periodo).
    private var unifiedRows: [UnifiedCategoryData] {
        let names = CategoryStyle.selectable(history: expenses)
        let statuses = budgets.statuses(for: names,
                                        expenses: snapshots,
                                        on: limitReferenceDate,
                                        usdToPen: exchangeRateService.usdToPenRate)
        let statusByName = Dictionary(uniqueKeysWithValues: statuses.map { ($0.category, $0) })
        let spentByCategory = Dictionary(uniqueKeysWithValues: totals.byCategory.map { ($0.category, $0.total) })
        let merchants = merchantsByCategory

        let rows = names.map { name in
            UnifiedCategoryData(category: name,
                                status: statusByName[name] ?? CategoryLimitStatus(category: name, limit: 0, spent: 0, alertThreshold: nil),
                                spent: spentByCategory[name] ?? 0,
                                merchants: merchants[name] ?? [])
        }

        return rows.sorted { lhs, rhs in
            if lhs.status.hasLimit != rhs.status.hasLimit { return lhs.status.hasLimit }
            if lhs.status.hasLimit {
                if lhs.status.isOver != rhs.status.isOver { return lhs.status.isOver }
                if lhs.status.fraction == rhs.status.fraction { return lhs.category < rhs.category }
                return lhs.status.fraction > rhs.status.fraction
            }
            if Money.cents(lhs.spent) == Money.cents(rhs.spent) { return lhs.category < rhs.category }
            return Money.cents(lhs.spent) > Money.cents(rhs.spent)
        }
    }

    private var visibleUnifiedRows: [UnifiedCategoryData] {
        guard let focusedCategory else { return unifiedRows }
        return unifiedRows.filter { $0.category == focusedCategory }
    }

    private var overLimitStatuses: [CategoryLimitStatus] {
        unifiedRows.filter { $0.status.hasLimit && $0.status.isOver }.map(\.status)
    }

    private func toggleCategoryExpand(_ category: String) {
        withAnimation(.spring) {
            if expandedCategories.contains(category) {
                expandedCategories.remove(category)
            } else {
                expandedCategories.insert(category)
            }
        }
    }

    private var misCategoriasListView: some View {
        VStack(spacing: 12) {
            if !distributionSegments.isEmpty {
                SpendingDistributionCard(monthLabel: limitMonthLabel,
                                         total: totals.spent,
                                         segments: distributionSegments,
                                         focusedCategory: focusedCategory) { category in
                    withAnimation(.spring) {
                        focusedCategory = (focusedCategory == category ? nil : category)
                    }
                } onClearFocus: {
                    withAnimation(.spring) { focusedCategory = nil }
                }
            }

            if !overLimitStatuses.isEmpty {
                OverLimitAlert(statuses: overLimitStatuses) { category in
                    editingCategory = CategoryWrapper(id: category)
                }
            }

            if unifiedRows.isEmpty {
                ContentUnavailableView("No hay gastos", systemImage: "tray.fill", description: Text("Los gastos clasificados aparecerán aquí."))
            } else {
                VStack(spacing: 10) {
                    ForEach(visibleUnifiedRows) { row in
                        UnifiedCategoryRow(category: row.category,
                                           status: row.status,
                                           spent: row.spent,
                                           merchants: row.merchants,
                                           color: CategoryStyle.color(for: row.category, accent: themeColor),
                                           isExpanded: expandedCategories.contains(row.category),
                                           onToggleExpand: { toggleCategoryExpand(row.category) },
                                           onRemoveMerchant: { merchant in
                                               selectedMerchantToUncategorize = (merchant: merchant, category: row.category)
                                           },
                                           onEditLimit: { editingCategory = CategoryWrapper(id: row.category) },
                                           onIsolate: {
                                               withAnimation(.spring) { focusedCategory = row.category }
                                           },
                                           onDeleteCategory: {
                                               bulkOperationLabel = "Eliminando categoría…"
                                               Task {
                                                   await CategoryEditor.delete(row.category, in: expenses)
                                                   try? modelContext.save()
                                                   bulkOperationLabel = nil
                                               }
                                           })
                        .id(row.category)
                    }
                }
            }
            
            if focusedCategory == nil {
                NewCategoryRow { creatingCategory = true }
                    .padding(.top, 2)
            }
        }
        .sheet(isPresented: $creatingCategory) {
            NavigationStack {
                CategorySettingsView(category: "", isNew: true, history: expenses)
                    // El modal compartido sólo trae "Listo" —dentro de un sheet
                    // no hay botón de atrás que haga de salida—, así que la
                    // cancelación se añade aquí en vez de tocar la pieza común.
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancelar") { creatingCategory = false }
                        }
                    }
            }
        }
    }

    // MARK: - Pendientes

    /// Cuánto llevas clasificado en el alcance elegido, con las pestañas para
    /// cambiar de alcance ahí mismo (`2d`). Sustituye a `scopeBanner`, que
    /// sólo aparecía para avisar del alcance y no decía nada del progreso.
    private var pendingTaskCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(taskHeadline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.label)
                Spacer(minLength: 0)
                Text("\(Int((scopedProgress * 100).rounded()))%")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(themeColor)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.track)
                    Capsule()
                        .fill(themeColor)
                        .frame(width: geo.size.width * CGFloat(scopedProgress))
                }
            }
            .frame(height: 8)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: scopedProgress)

            HStack(spacing: 8) {
                scopeChip(title: periodScopeLabel, isSelected: pendingScope == .period) { pendingScope = .period }
                scopeChip(title: "Todo", isSelected: pendingScope == .all) { pendingScope = .all }
            }

            if let note = scopeNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
            }
        }
        .surfaceCard(radius: 20)
        .padding(.horizontal, 16)
    }

    private var taskHeadline: String {
        "\(scopedClassifiedCount) de \(scopedMerchantCount) operaciones clasificadas"
    }

    /// Sólo dice algo cuando hay algo que decir: operaciones pendientes fuera
    /// del periodo (alcance "este mes"), o el recordatorio de que se está
    /// viendo todo el historial (alcance "todo").
    private var scopeNote: String? {
        let label = periodScopeLabel.prefix(1).lowercased() + periodScopeLabel.dropFirst()
        if pendingScope == .all {
            return "Viendo todo el historial, no sólo " + label + "."
        }
        guard !outOfPeriodGroups.isEmpty else { return nil }
        return "\(outOfPeriodGroups.count) operaciones pendientes de clasificar fuera de " + label + " · " + Money.format(outOfPeriodTotal)
    }

    private func scopeChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring) { action() }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : palette.label)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? themeColor : palette.track)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var selectAllRow: some View {
        HStack {
            Text(pendingScope == .period ? "PENDIENTES EN " + limitMonthLabel.uppercased() : "TODOS LOS PENDIENTES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.secondaryLabel)
            Spacer()
            if !visiblePendingGroups.isEmpty {
                Button(isAllSelected ? "Quitar selección" : "Seleccionar todos") {
                    withAnimation { toggleSelectAll() }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(themeColor)
            }
        }
        .padding(.horizontal, 18)
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Buscar operación pendiente...", text: $searchText)
                .disableAutocorrection(true)

            if !searchText.isEmpty {
                Button {
                    withAnimation { searchText = "" }
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
    }

    private var pendingView: some View {
        Group {
            if pendingGroups.isEmpty {
                ContentUnavailableView("Pendientes vacío", systemImage: "checkmark.circle.fill", description: Text("Todos tus gastos están clasificados."))
            } else {
                VStack(spacing: 12) {
                    pendingTaskCard

                    searchField

                    if !suggestionBuckets.isEmpty {
                        EngineSuggestionRow(merchantCount: suggestionBuckets.reduce(0) { $0 + $1.merchants.count }) {
                            bulkOperationLabel = "Clasificando…"
                            Task {
                                await applyAllSuggestionBuckets()
                                bulkOperationLabel = nil
                            }
                        }
                    }

                    selectAllRow

                    if visiblePendingGroups.isEmpty {
                        ContentUnavailableView("No se encontraron resultados", systemImage: "magnifyingglass", description: Text("Prueba con otro término de búsqueda."))
                    } else {
                        ForEach(pagedPendingGroups) { group in
                            merchantCard(for: group)
                                .onAppear { loadMorePendingIfNeeded(currentGroup: group) }
                        }
                    }

                    // Relleno mínimo para que los últimos elementos sean scrolleables.
                    if visiblePendingGroups.count < 6 {
                        Color.clear
                            .frame(height: CGFloat(6 - visiblePendingGroups.count) * 85)
                    }
                }
            }
        }
    }

    // MARK: - Desclasificar

    private func uncategorize(merchant: String, from category: String) {
        let expensesToUpdate = expenses.filter { $0.category == category && $0.merchant == merchant }
        for expense in expensesToUpdate {
            expense.category = Accounting.unclassified
        }
        // Sin borrar la regla, el siguiente correo del comercio volvería a
        // clasificarse solo y el usuario no entendería por qué.
        MerchantRules.remove(merchant)
        try? modelContext.save()

        showToast(message: "Gastos de \(merchant) enviados a Pendientes", tab: .inbox, id: merchant, icon: "tray.fill", color: .orange)
    }

    private func showToast(message: String, tab: CategoryTab, id: String, icon: String, color: Color) {
        let newToast = ToastNotification(message: message, targetTab: tab, targetID: id, systemImage: icon, color: color)

        withAnimation(.spring) {
            activeToasts.append(newToast)
        }

        // Auto-hide toast after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation(.easeInOut) {
                activeToasts.removeAll { $0.id == newToast.id }
            }
        }
    }
}

// El antiguo `AssignCategoryView` —un `List` alfabético dentro de un `Form`—
// lo sustituye `AssignCategorySheet` (`6a`), que además enseña el saldo del
// límite y la sugerencia del motor. La antigua dona y la tarjeta de categoría
// expandible por separado las sustituye la barra de reparto + la fila
// unificada de `UnifiedCategoryRow`.

#Preview {
    CategoriesView(scrollToTopTrigger: .constant(false))
        .modelContainer(for: [Expense.self, Income.self], inMemory: true)
}
