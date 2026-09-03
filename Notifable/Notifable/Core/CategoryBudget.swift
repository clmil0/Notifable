import Foundation
import SwiftUI

/// Límite tentativo de gasto por categoría.
///
/// "Tentativo" es una decisión de diseño, no una limitación técnica: el límite
/// **nunca bloquea** una asignación ni un alta de gasto. Sólo cambia el color de
/// la categoría, alimenta el aviso y el saldo que se muestra al asignar.
///
/// Es **programable** en dos ejes:
/// 1. `cycle` — cada categoría se reinicia en su propio ciclo (semana, quincena,
///    mes, año), independiente del periodo visible del Resumen.
/// 2. `overrides` — meses con otro límite (diciembre S/ 1 100), opcionalmente
///    repetidos cada año. Fuera de esos meses vuelve solo a `amount`.
struct CategoryBudget: Codable, Equatable, Identifiable {

    /// El nombre de la categoría es la clave en todo el proyecto (`Expense.category`).
    var id: String { category }
    var category: String

    /// Monto base del ciclo, normalizado a céntimos por `Money`.
    var amount: Double

    var cycle: Cycle = .mes

    /// Día de corte del ciclo mensual / quincenal. 1…28 (28 = día de pago típico).
    /// Se limita a 28 para que exista en todos los meses.
    var anchorDay: Int = 1

    /// Fracción a la que se avisa. `nil` = sin aviso previo, sólo al pasarse.
    var alertThreshold: Double? = 0.8

    /// Lo no gastado suma al ciclo siguiente. Se acumula un ciclo, no infinitos.
    var rollsOver: Bool = false

    /// Apagado para gastos reembolsables: el gasto se sigue viendo en la
    /// categoría pero no cuenta contra `BudgetStore.monthlyBudget`.
    var countsInGlobalBudget: Bool = true

    /// Excepciones programadas por mes.
    var overrides: [Override] = []

    enum Cycle: String, Codable, CaseIterable {
        case semana, quincena, mes, anio

        var label: String {
            switch self {
            case .semana:   return "Semana"
            case .quincena: return "Quincena"
            case .mes:      return "Mes"
            case .anio:     return "Año"
            }
        }

        /// Cómo se lee en la cabecera de la tarjeta: "LÍMITE TENTATIVO · MENSUAL".
        var headerLabel: String {
            switch self {
            case .semana:   return "SEMANAL"
            case .quincena: return "QUINCENAL"
            case .mes:      return "MENSUAL"
            case .anio:     return "ANUAL"
            }
        }

        /// Sufijo del monto: "S/ 600 al mes".
        var amountSuffix: String {
            switch self {
            case .semana:   return "a la semana"
            case .quincena: return "por quincena"
            case .mes:      return "al mes"
            case .anio:     return "al año"
            }
        }

        /// Sólo el ciclo mensual y el quincenal tienen día de corte.
        var usesAnchorDay: Bool { self == .mes || self == .quincena }
    }

    struct Override: Codable, Equatable, Identifiable {
        var id = UUID()
        /// 1…12. Con `year == nil` se repite cada año.
        var month: Int
        var year: Int?
        var amount: Double
        var repeatsYearly: Bool { year == nil }
    }

    /// Límite vigente en la fecha dada, aplicando las excepciones.
    func amount(on date: Date) -> Double {
        let cal = Period.calendar
        let month = cal.component(.month, from: date)
        let year = cal.component(.year, from: date)
        let match = overrides.first { $0.month == month && ($0.year == nil || $0.year == year) }
        return Money.normalized(match?.amount ?? amount)
    }

    var hasLimit: Bool { Money.cents(amount) > 0 }

    /// Día de corte usable: fuera de 1…28 el ciclo no existiría en febrero.
    var safeAnchorDay: Int { min(28, max(1, anchorDay)) }

    // MARK: - Ciclo

    /// Intervalo semiabierto `[start, end)` del ciclo que contiene a `date`.
    ///
    /// Es lo que separa el límite del periodo visible del Resumen: filtrar por
    /// un día no encoge el límite del mes, sólo la lista de movimientos.
    func interval(containing date: Date) -> DateInterval {
        let cal = Period.calendar
        switch cycle {
        case .semana:
            return cal.dateInterval(of: .weekOfYear, for: date)
                ?? DateInterval(start: cal.startOfDay(for: date), duration: 7 * 86_400)
        case .anio:
            return cal.dateInterval(of: .year, for: date)
                ?? DateInterval(start: cal.startOfDay(for: date), duration: 365 * 86_400)
        case .mes:
            let start = monthlyStart(onOrBefore: date)
            let end = cal.date(byAdding: .month, value: 1, to: start) ?? start
            return DateInterval(start: start, end: end)
        case .quincena:
            let start = monthlyStart(onOrBefore: date)
            let mid = cal.date(byAdding: .day, value: 15, to: start) ?? start
            let nextMonth = cal.date(byAdding: .month, value: 1, to: start) ?? start
            if date >= mid {
                return DateInterval(start: mid, end: nextMonth)
            }
            return DateInterval(start: start, end: mid)
        }
    }

    /// El ciclo `offset` posiciones atrás (o adelante) del que contiene a `date`.
    func interval(offsetBy offset: Int, from date: Date) -> DateInterval {
        var current = interval(containing: date)
        guard offset != 0 else { return current }
        let cal = Period.calendar
        let step = offset < 0 ? -1 : 1
        for _ in 0..<abs(offset) {
            let pivot: Date
            if step < 0 {
                pivot = cal.date(byAdding: .second, value: -1, to: current.start) ?? current.start
            } else {
                pivot = current.end
            }
            current = interval(containing: pivot)
        }
        return current
    }

    /// Inicio del ciclo mensual: el día de corte más reciente que ya pasó.
    private func monthlyStart(onOrBefore date: Date) -> Date {
        let cal = Period.calendar
        var comps = cal.dateComponents([.year, .month], from: date)
        comps.day = safeAnchorDay
        let candidate = cal.startOfDay(for: cal.date(from: comps) ?? date)
        if candidate > date {
            return cal.date(byAdding: .month, value: -1, to: candidate) ?? candidate
        }
        return candidate
    }
}

// MARK: - Estado de un límite en su ciclo

/// Lo que la UI necesita para pintar una categoría. Todo el juicio vive aquí,
/// nunca en la vista.
struct CategoryLimitStatus {

    let category: String
    /// Límite vigente (ya con excepción del mes aplicada) + sobrante traspasado.
    let limit: Double
    let spent: Double
    /// Sobrante del ciclo anterior si `rollsOver`. Se muestra aparte para que el
    /// usuario entienda por qué su límite de este mes no es el que configuró.
    let carriedOver: Double
    /// Días que faltan para el corte del ciclo.
    let daysLeft: Int
    /// Fracción del ciclo ya transcurrida: la marca de ritmo de la barra,
    /// la misma pieza que `BudgetHeroCard`.
    let elapsedFraction: Double
    /// Umbral de aviso configurado, para no tener que pasar el `CategoryBudget`
    /// junto al estado en cada vista.
    let alertThreshold: Double?
    /// Inicio del ciclo vigente. Lo usa el aviso para no repetirse dentro del
    /// mismo ciclo.
    let cycleStart: Date

    init(category: String,
         limit: Double,
         spent: Double,
         carriedOver: Double = 0,
         daysLeft: Int = 0,
         elapsedFraction: Double = 0,
         alertThreshold: Double? = 0.8,
         cycleStart: Date = .distantPast) {
        self.category = category
        self.limit = limit
        self.spent = spent
        self.carriedOver = carriedOver
        self.daysLeft = daysLeft
        self.elapsedFraction = elapsedFraction
        self.alertThreshold = alertThreshold
        self.cycleStart = cycleStart
    }

    var hasLimit: Bool { Money.cents(limit) > 0 }
    var remaining: Double { Money.subtract(limit, spent) }
    var fraction: Double { limit > 0 ? min(spent / limit, 1) : 0 }
    var isOver: Bool { Money.cents(spent) > Money.cents(limit) }
    var overBy: Double { isOver ? Money.subtract(spent, limit) : 0 }

    enum Level { case sinLimite, ok, cerca, pasado }

    var level: Level { level(threshold: alertThreshold) }

    func level(threshold: Double?) -> Level {
        guard limit > 0 else { return .sinLimite }
        if isOver { return .pasado }
        if let t = threshold, t > 0, spent / limit >= t { return .cerca }
        return .ok
    }

    /// Texto de la celda al asignar un gasto (`6a`) y de la lista (`6d`).
    /// Deliberadamente corto: cabe en una celda de 1/3 de ancho, así que va sin
    /// decimales (`formatCompact`).
    var shortLabel: String {
        guard limit > 0 else { return "Sin límite" }
        if isOver { return Money.formatCompact(overBy) + " pasado" }
        return Money.formatCompact(remaining) + " libres"
    }

    /// Texto de la fila de `6d` y del pie de la tarjeta de `6b`.
    var longLabel: String {
        guard limit > 0 else { return "Sin límite" }
        if isOver {
            return Money.formatCompact(spent) + " de " + Money.formatCompact(limit)
                + " · " + Money.formatCompact(overBy) + " arriba"
        }
        return Money.formatCompact(spent) + " de " + Money.formatCompact(limit)
            + " · quedan " + Money.formatCompact(remaining)
    }

    var daysLeftLabel: String {
        if daysLeft <= 0 { return "último día" }
        return daysLeft == 1 ? "1 día" : "\(daysLeft) días"
    }
}

extension CategoryLimitStatus.Level {

    /// Un solo sitio decide el color del nivel; las vistas sólo lo piden.
    func color(_ palette: Palette) -> Color {
        switch self {
        case .sinLimite: return palette.secondaryLabel
        case .ok:        return palette.positive
        case .cerca:     return palette.warning
        case .pasado:    return palette.negative
        }
    }
}

// MARK: - Cálculo

/// El puente entre los gastos y `CategoryLimitStatus`. Fuera del store para
/// poder probarse sobre snapshots, sin `ModelContainer` ni `UserDefaults`.
enum CategoryLimits {

    /// Fecha con la que se resuelve el ciclo desde una pantalla filtrada.
    ///
    /// Decisión: el límite se mira **en el mes en el que estás**. Si el periodo
    /// visible es un rango de varios meses, manda el más reciente; si es un solo
    /// día, el límite sigue siendo el de su mes entero. Por eso se toma el
    /// último instante visible y no `period.reference`, que en un rango apunta
    /// a otro sitio.
    static func referenceDate(for period: Period) -> Date {
        let interval = period.interval
        let last = interval.end.addingTimeInterval(-1)
        return max(interval.start, last)
    }

    /// Gasto de la categoría dentro del intervalo, en soles y con el tipo de
    /// cambio de cada movimiento (`Accounting.penCents`).
    static func spent(category: String,
                      in interval: DateInterval,
                      expenses: [ExpenseSnapshot],
                      usdToPen: Double) -> Double {
        var cents = 0
        for expense in expenses where expense.category == category {
            guard expense.date >= interval.start, expense.date < interval.end else { continue }
            cents += Accounting.penCents(expense, fallbackRate: usdToPen)
        }
        return Money.value(cents)
    }

    /// Estado del límite de una categoría en el ciclo que contiene a `date`.
    /// Sin `CategoryBudget` devuelve el estado "sin límite", que la UI también
    /// necesita para pintar la celda y ofrecer "Poner límite".
    static func status(category: String,
                       budget: CategoryBudget?,
                       expenses: [ExpenseSnapshot],
                       on date: Date,
                       usdToPen: Double) -> CategoryLimitStatus {

        guard let budget, budget.hasLimit else {
            return CategoryLimitStatus(category: category, limit: 0, spent: 0, alertThreshold: nil)
        }

        let interval = budget.interval(containing: date)
        let base = budget.amount(on: interval.start)
        let carried = budget.rollsOver ? carryOver(budget: budget, expenses: expenses, on: date, usdToPen: usdToPen) : 0

        return CategoryLimitStatus(
            category: category,
            limit: Money.add(base, carried),
            spent: spent(category: category, in: interval, expenses: expenses, usdToPen: usdToPen),
            carriedOver: carried,
            daysLeft: daysLeft(in: interval, from: date),
            elapsedFraction: elapsedFraction(of: interval, at: date),
            alertThreshold: budget.alertThreshold,
            cycleStart: interval.start
        )
    }

    /// Sobrante del ciclo anterior. Se acumula **un** ciclo: el sobrante del
    /// anterior al anterior ya caducó.
    static func carryOver(budget: CategoryBudget,
                          expenses: [ExpenseSnapshot],
                          on date: Date,
                          usdToPen: Double) -> Double {
        let previous = budget.interval(offsetBy: -1, from: date)
        let limit = budget.amount(on: previous.start)
        let used = spent(category: budget.category, in: previous, expenses: expenses, usdToPen: usdToPen)
        return Money.clampedToZero(Money.subtract(limit, used))
    }

    /// Promedio real de los últimos ciclos **cerrados**. Es la referencia que
    /// `6c` propone: un límite por debajo del promedio se incumple siempre.
    /// `nil` si no hay ni un ciclo cerrado con gasto registrado.
    static func average(budget: CategoryBudget,
                        expenses: [ExpenseSnapshot],
                        on date: Date,
                        cycles: Int = 3,
                        usdToPen: Double) -> Double? {
        guard cycles > 0 else { return nil }
        var totals: [Double] = []
        for offset in 1...cycles {
            let interval = budget.interval(offsetBy: -offset, from: date)
            totals.append(spent(category: budget.category, in: interval, expenses: expenses, usdToPen: usdToPen))
        }
        guard totals.contains(where: { Money.cents($0) > 0 }) else { return nil }
        return Money.divide(Money.sum(totals), by: totals.count)
    }

    /// Gasto de los últimos `cycles` ciclos cerrados más el actual, en orden
    /// cronológico. Es el histórico de barras de `6c`.
    static func history(budget: CategoryBudget,
                        expenses: [ExpenseSnapshot],
                        on date: Date,
                        closedCycles: Int = 3,
                        usdToPen: Double) -> [(interval: DateInterval, total: Double)] {
        var result: [(interval: DateInterval, total: Double)] = []
        var offset = -closedCycles
        while offset <= 0 {
            let interval = budget.interval(offsetBy: offset, from: date)
            result.append((interval, spent(category: budget.category,
                                           in: interval,
                                           expenses: expenses,
                                           usdToPen: usdToPen)))
            offset += 1
        }
        return result
    }

    /// Valor que propone el botón "Usar 680": el promedio redondeado **al alza**
    /// a la decena. Redondear a la baja devolvería un límite que ya se incumple.
    static func suggestedLimit(from average: Double) -> Double {
        let units = Double(Money.cents(average)) / 100.0
        guard units.isFinite, units > 0 else { return 0 }
        return (units / 10).rounded(.up) * 10
    }

    static func daysLeft(in interval: DateInterval, from date: Date) -> Int {
        let cal = Period.calendar
        let start = cal.startOfDay(for: min(max(date, interval.start), interval.end))
        let end = cal.startOfDay(for: interval.end)
        return max(0, cal.dateComponents([.day], from: start, to: end).day ?? 0)
    }

    static func elapsedFraction(of interval: DateInterval, at date: Date) -> Double {
        let total = interval.end.timeIntervalSince(interval.start)
        guard total > 0 else { return 0 }
        let elapsed = date.timeIntervalSince(interval.start)
        return min(1, max(0, elapsed / total))
    }
}

// MARK: - Store

/// Persistencia y cálculo. Un solo objeto para toda la app, igual que `BudgetStore`.
///
/// Se guarda como JSON en `UserDefaults` porque son pocos registros (una fila por
/// categoría) y así no hace falta migrar SwiftData. La clase es
/// `ObservableObject` de verdad —publica sus cambios— porque `@AppStorage`
/// dentro de una clase no dispara `objectWillChange` (ver la nota de
/// `BudgetStore`).
final class CategoryBudgetStore: ObservableObject {

    static let shared = CategoryBudgetStore()

    static let key = "categoryBudgets"

    @Published private(set) var budgets: [String: CategoryBudget] = [:]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        budgets = Self.decode(defaults.data(forKey: Self.key) ?? Data())
    }

    /// Todas las filas guardadas, tengan o no monto. `budget(for:)` filtra las
    /// que no tienen límite; ésta sirve para leer `countsInGlobalBudget` de una
    /// categoría cuyo límite se borró.
    func record(for category: String) -> CategoryBudget? { budgets[category] }

    func budget(for category: String) -> CategoryBudget? {
        guard let b = budgets[category], b.hasLimit else { return nil }
        return b
    }

    func save(_ budget: CategoryBudget) {
        budgets[budget.category] = budget
        persist()
    }

    func remove(_ category: String) {
        budgets[category] = nil
        persist()
    }

    /// Al renombrar una categoría el límite viaja con ella: la clave de todo el
    /// proyecto es el nombre.
    func rename(_ category: String, to newName: String) {
        guard var moved = budgets[category], category != newName else { return }
        moved.category = newName
        budgets[category] = nil
        budgets[newName] = moved
        persist()
    }

    /// Al fusionar dos categorías (`6b`) los límites se suman, no se pierde uno.
    func merge(_ source: String, into target: String) {
        guard let from = budgets[source] else { return }
        if var to = budgets[target] {
            to.amount = Money.add(to.amount, from.amount)
            budgets[target] = to
        } else {
            var moved = from
            moved.category = target
            budgets[target] = moved
        }
        budgets[source] = nil
        persist()
    }

    /// Suma de límites vigentes en el mes de `date`. Es lo que `6d` compara
    /// contra `BudgetStore.monthlyBudget` para mostrar "sin asignar".
    ///
    /// Se normaliza a mensual: un límite semanal reparte su año entre 12 meses,
    /// porque el presupuesto general contra el que se compara es mensual.
    func assignedTotal(on date: Date) -> Double {
        var total = 0.0
        for budget in budgets.values where budget.hasLimit && budget.countsInGlobalBudget {
            total = Money.add(total, Self.monthlyEquivalent(of: budget, on: date))
        }
        return total
    }

    static func monthlyEquivalent(of budget: CategoryBudget, on date: Date) -> Double {
        let amount = budget.amount(on: date)
        switch budget.cycle {
        case .mes:      return amount
        case .quincena: return Money.multiply(amount, by: 2)
        case .semana:   return Money.multiply(amount, by: 52.0 / 12.0)
        case .anio:     return Money.divide(amount, by: 12)
        }
    }

    /// Categorías con límite, en el orden de `6d`: pasadas primero, luego por
    /// fracción descendente. Las que no tienen límite las añade la vista al final.
    func statuses(for categories: [String],
                  expenses: [ExpenseSnapshot],
                  on date: Date,
                  usdToPen: Double) -> [CategoryLimitStatus] {
        categories.map {
            CategoryLimits.status(category: $0,
                                  budget: budget(for: $0),
                                  expenses: expenses,
                                  on: date,
                                  usdToPen: usdToPen)
        }
    }

    private func persist() {
        let encoded = (try? JSONEncoder().encode(Array(budgets.values))) ?? Data()
        defaults.set(encoded, forKey: Self.key)
    }

    private static func decode(_ data: Data) -> [String: CategoryBudget] {
        guard let list = try? JSONDecoder().decode([CategoryBudget].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: list.map { ($0.category, $0) })
    }
}
