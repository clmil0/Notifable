import Foundation

/// Lo único que sale de la base de datos hacia el App Group.
///
/// La app lo escribe (`WidgetSnapshotWriter`) y los widgets sólo lo leen: nunca
/// abren SwiftData. Por eso aquí no hay movimientos sueltos, notas, `emailID`
/// ni datos de amigos — sólo resúmenes ya calculados con `Accounting`.
///
/// **Montos en céntimos de sol (`Int`)**, ya convertidos con el tipo de cambio
/// de cada movimiento: el JSON queda estable y el widget no necesita `Money`.
///
/// **Por qué el gasto va día por día y no sólo el total:** el widget tiene que
/// seguir diciendo la verdad a medianoche sin que la app se abra. Con el
/// arreglo del mes recalcula "hoy", el ritmo y el disponible por día para
/// cualquier fecha (`WidgetDerived`).
struct WidgetSnapshot: Codable, Equatable {

    /// Súbelo si cambias el formato de forma incompatible: un widget con el
    /// formato viejo prefiere mostrar el estado vacío antes que decodificar mal.
    static let currentSchema = 1

    var schemaVersion: Int = WidgetSnapshot.currentSchema
    var generatedAt: Date
    /// Con el bloqueo de la app encendido los widgets muestran porcentajes,
    /// no montos. Ver `WidgetSnapshotBuilder.hideAmounts`.
    var hideAmounts: Bool
    var theme: Theme

    var month: MonthSummary
    /// `nil` si no hay presupuesto mensual: los widgets no inventan una meta.
    var budget: BudgetSummary?
    /// Máximo 4, de mayor a menor. `otherCents` es el resto del mes.
    var topCategories: [CategorySlice]
    var otherCents: Int
    /// Límites de categoría con monto, los más cerca de pasarse primero. Máx. 6.
    var limits: [LimitSummary]
    var attention: AttentionSummary
    /// Gastos rápidos, en el orden del modal. Máx. 4.
    var quickActions: [QuickAction]
    /// Para elegir la categoría al configurar un widget, sin abrir la base.
    var categoryNames: [String]

    struct Theme: Codable, Equatable {
        var accentHex: String
        var accentDarkHex: String
        var incomeHex: String
    }

    struct MonthSummary: Codable, Equatable {
        /// Inicio del mes `[start, end)`, igual que `Period.interval`.
        var start: Date
        var end: Date
        var spentCents: Int
        /// `nil` si el usuario no registra ingresos — igual que `PeriodTotals.balance`.
        var incomeCents: Int?
        /// Índice 0 = día 1. Suma exactamente `spentCents`.
        var dailySpentCents: [Int]
        /// El mes anterior completo, día por día, para "vs. mes pasado" al mismo día.
        var previousDailySpentCents: [Int]
        var expenseCount: Int
        var hasMixedCurrencies: Bool
    }

    struct BudgetSummary: Codable, Equatable {
        var targetCents: Int
    }

    struct CategorySlice: Codable, Equatable, Identifiable {
        var name: String
        var totalCents: Int
        var symbol: String
        var colorHex: String
        var id: String { name }
    }

    struct LimitSummary: Codable, Equatable, Identifiable {
        var category: String
        var symbol: String
        var colorHex: String
        var limitCents: Int
        var spentCents: Int
        var cycleStart: Date
        /// Fin exclusivo del ciclo vigente.
        var cycleEnd: Date
        var alertThreshold: Double?
        var id: String { category }
    }

    struct AttentionSummary: Codable, Equatable {
        /// Comercios sin clasificar en el mes (lo mismo que el banner de Resumen).
        var unclassifiedCount: Int
        /// Todo lo que te deben, de cualquier mes.
        var debtOutstandingCents: Int
        var debtCount: Int
        /// Recurrentes vencidos esperando confirmación.
        var pendingRecurringCount: Int
        var nextRecurring: UpcomingItem?
    }

    struct UpcomingItem: Codable, Equatable {
        var label: String
        var amountCents: Int
        var date: Date
    }

    struct QuickAction: Codable, Equatable, Identifiable {
        var id: UUID
        var label: String
        var amountCents: Int
        /// SF Symbol, o "yape"/"plin" para los logos (igual que `QuickExpense.iconName`).
        var icon: String
    }
}

// MARK: - Valores derivados para una fecha

/// Lo que un widget pinta en una fecha concreta, calculado sólo a partir del
/// resumen. Es la misma aritmética que `Pace` y `CategoryLimits`, pero con la
/// fecha inyectada: el timeline genera entradas para medianoche y cada una
/// tiene que cuadrar sin volver a la app.
struct WidgetDerived: Equatable {

    enum Status: Equatable { case ok, warning, over }

    /// `false` si la fecha ya no cae en el mes del resumen (cambió el mes y la
    /// app no se ha abierto): todo se muestra en cero.
    let isCurrentMonth: Bool
    let spentCents: Int
    let todayCents: Int
    let incomeCents: Int?
    let elapsedDays: Int
    let totalDays: Int
    let expectedFraction: Double

    let targetCents: Int?
    let usedFraction: Double?
    let remainingCents: Int?
    let availablePerDayCents: Int?
    let projectionCents: Int?
    let status: Status?

    /// Mes pasado hasta el mismo día. `nil` si no hubo gasto con qué comparar.
    let previousToDateCents: Int?
    /// +0.12 = 12 % más que el mes pasado al mismo día.
    let changeVsPrevious: Double?

    /// Gasto acumulado día por día hasta hoy, para la curva.
    let cumulativeCents: [Int]

    var balanceCents: Int? { incomeCents.map { $0 - spentCents } }

    init(_ snapshot: WidgetSnapshot, at date: Date, calendar: Calendar = WidgetDerived.calendar) {
        let month = snapshot.month
        let daily = month.dailySpentCents
        let totalDays = max(1, daily.count)
        self.totalDays = totalDays

        let inMonth = date >= month.start && date < month.end
        isCurrentMonth = inMonth

        guard inMonth else {
            // Fuera del mes: antes de empezar o ya en el siguiente. Sin la app
            // abierta no hay datos del mes nuevo, así que cero y sin juicio.
            spentCents = 0
            todayCents = 0
            incomeCents = snapshot.month.incomeCents == nil ? nil : 0
            elapsedDays = 0
            expectedFraction = 0
            targetCents = snapshot.budget?.targetCents
            usedFraction = snapshot.budget == nil ? nil : 0
            remainingCents = snapshot.budget?.targetCents
            availablePerDayCents = nil
            projectionCents = nil
            status = snapshot.budget == nil ? nil : .ok
            previousToDateCents = nil
            changeVsPrevious = nil
            cumulativeCents = []
            return
        }

        let dayIndex = min(totalDays - 1,
                           max(0, calendar.dateComponents([.day],
                                                          from: calendar.startOfDay(for: month.start),
                                                          to: calendar.startOfDay(for: date)).day ?? 0))
        let elapsed = dayIndex + 1
        elapsedDays = elapsed
        let fraction = Double(elapsed) / Double(totalDays)
        expectedFraction = fraction

        // El total del mes incluye lo que ya esté fechado más adelante (un
        // recurrente confirmado por adelantado), igual que `Accounting.totals`.
        let spent = month.spentCents
        spentCents = spent
        todayCents = daily.indices.contains(dayIndex) ? daily[dayIndex] : 0
        incomeCents = month.incomeCents

        var running = 0
        cumulativeCents = daily.prefix(elapsed).map { running += $0; return running }

        if let target = snapshot.budget?.targetCents, target > 0 {
            targetCents = target
            usedFraction = Double(spent) / Double(target)
            let remaining = max(0, target - spent)
            remainingCents = remaining
            let daysLeft = totalDays - elapsed
            // Igual que `Pace.availablePerDay`: el último día no hay "por día".
            availablePerDayCents = daysLeft > 0 ? Int((Double(remaining) / Double(daysLeft)).rounded()) : nil
            projectionCents = Int((Double(spent) / fraction).rounded())
            let expected = Int((Double(target) * fraction).rounded())
            if spent > target {
                status = .over
            } else if spent > expected {
                status = .warning
            } else {
                status = .ok
            }
        } else {
            targetCents = nil
            usedFraction = nil
            remainingCents = nil
            availablePerDayCents = nil
            projectionCents = nil
            status = nil
        }

        let previous = month.previousDailySpentCents
        let prevToDate = previous.prefix(min(elapsed, previous.count)).reduce(0, +)
        if prevToDate > 0 {
            previousToDateCents = prevToDate
            changeVsPrevious = Double(spent - prevToDate) / Double(prevToDate)
        } else {
            previousToDateCents = nil
            changeVsPrevious = nil
        }
    }

    /// Mismo calendario que `Period.calendar` (lunes primero, es_PE). Se
    /// duplica aquí porque el widget no compila `Period`.
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.locale = Locale(identifier: "es_PE")
        c.timeZone = .current
        return c
    }()
}

extension WidgetSnapshot.LimitSummary {

    var fraction: Double { limitCents > 0 ? Double(spentCents) / Double(limitCents) : 0 }
    var remainingCents: Int { limitCents - spentCents }
    var isOver: Bool { spentCents > limitCents }

    /// "cerca" con el mismo umbral que `CategoryLimitStatus.level`.
    var isNear: Bool {
        guard let threshold = alertThreshold, !isOver else { return false }
        return fraction >= threshold
    }

    /// Días hasta el corte, igual que `CategoryLimits.daysLeft`.
    func daysLeft(at date: Date, calendar: Calendar = WidgetDerived.calendar) -> Int {
        let start = calendar.startOfDay(for: min(max(date, cycleStart), cycleEnd))
        let end = calendar.startOfDay(for: cycleEnd)
        return max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
    }

    /// El ciclo guardado ya terminó: el widget no sabe cuánto va del nuevo.
    func isStale(at date: Date) -> Bool { date >= cycleEnd }
}

// MARK: - Estado vacío y ejemplo

extension WidgetSnapshot {

    /// Para la galería de widgets y las vistas previas. Cifras redondas y
    /// verosímiles; nada sale de datos reales.
    static func sample(now: Date = Date(), calendar: Calendar = WidgetDerived.calendar) -> WidgetSnapshot {
        let month = calendar.dateInterval(of: .month, for: now)
            ?? DateInterval(start: now, duration: 30 * 86_400)
        let days = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let pattern = [4_200, 1_850, 6_400, 0, 3_100, 12_800, 2_500]
        let daily = (0..<days).map { pattern[$0 % pattern.count] }
        let today = calendar.component(.day, from: now)
        let upToToday = daily.enumerated().map { $0.offset < today ? $0.element : 0 }
        let spent = upToToday.reduce(0, +)
        let blue = "2E5BFF"

        return WidgetSnapshot(
            generatedAt: now,
            hideAmounts: false,
            theme: Theme(accentHex: blue, accentDarkHex: blue, incomeHex: "248A3D"),
            month: MonthSummary(start: month.start, end: month.end,
                                spentCents: spent,
                                incomeCents: 300_000,
                                dailySpentCents: upToToday,
                                previousDailySpentCents: daily.map { Int(Double($0) * 0.9) },
                                expenseCount: 42,
                                hasMixedCurrencies: false),
            budget: BudgetSummary(targetCents: 200_000),
            topCategories: [
                CategorySlice(name: "Comida", totalCents: Int(Double(spent) * 0.38), symbol: "fork.knife", colorHex: "FF9500"),
                CategorySlice(name: "Transporte", totalCents: Int(Double(spent) * 0.22), symbol: "car.fill", colorHex: "007AFF"),
                CategorySlice(name: "Supermercado", totalCents: Int(Double(spent) * 0.18), symbol: "cart.fill", colorHex: "30B0C7"),
                CategorySlice(name: "Entretenimiento", totalCents: Int(Double(spent) * 0.1), symbol: "play.tv.fill", colorHex: blue)
            ],
            otherCents: spent - Int(Double(spent) * 0.88),
            limits: [
                LimitSummary(category: "Comida", symbol: "fork.knife", colorHex: "FF9500",
                             limitCents: 60_000, spentCents: Int(Double(spent) * 0.38),
                             cycleStart: month.start, cycleEnd: month.end, alertThreshold: 0.8)
            ],
            attention: AttentionSummary(unclassifiedCount: 3,
                                        debtOutstandingCents: 8_500,
                                        debtCount: 2,
                                        pendingRecurringCount: 1,
                                        nextRecurring: UpcomingItem(label: "Netflix", amountCents: 3_490,
                                                                    date: calendar.date(byAdding: .day, value: 3, to: now) ?? now)),
            quickActions: [
                QuickAction(id: UUID(), label: "Pasaje", amountCents: 250, icon: "bus.fill"),
                QuickAction(id: UUID(), label: "Café", amountCents: 900, icon: "cup.and.saucer.fill"),
                QuickAction(id: UUID(), label: "Almuerzo", amountCents: 1_500, icon: "fork.knife")
            ],
            categoryNames: ["Comida", "Transporte", "Supermercado", "Entretenimiento", "Otros"]
        )
    }
}
