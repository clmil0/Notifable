import Testing
import Foundation
@testable import Notifable

/// Ritmo. Lo que se comprueba es que las frases digan la verdad: el signo de la
/// comparación, de dónde viene el cambio, y que los días que aún no han llegado
/// no cuenten como "días sin gastar".
struct RhythmTests {

    static let cal = Period.calendar
    static let rate = 3.75

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    static func rhythm(current: [ExpenseSnapshot],
                       previous: [ExpenseSnapshot],
                       period: Period) -> Rhythm {
        Rhythm(period: period,
               current: Accounting.totals(expenses: current, incomes: [], period: period, usdToPen: rate),
               previous: Accounting.totals(expenses: previous, incomes: [], period: period.previous, usdToPen: rate))
    }

    /// Un mes ya cerrado: todos sus días cuentan como transcurridos.
    static var closedMonth: Period {
        Period(granularity: .mes, reference: date(2026, 4, 10))
    }

    @Test("Sin gasto, el titular no habla de promedios")
    func sinGasto() {
        let r = Self.rhythm(current: [], previous: [], period: Self.closedMonth)
        #expect(r.headline == "Aún no has gastado nada en este periodo.")
        #expect(r.supportLine == nil)
        #expect(!r.hasComparison)
    }

    @Test("El titular dice 'más' cuando se gasta más al día que el periodo anterior")
    func comparacionHaciaArriba() {
        let period = Self.closedMonth                       // abril, 30 días
        let march = Period(granularity: .mes, reference: Self.date(2026, 3, 10))  // 31 días

        // Abril: 3000 en el mes -> 100 al día. Marzo: 1550 -> 50 al día.
        let current = (1...30).map { ExpenseSnapshot(amount: 100, date: Self.date(2026, 4, $0), category: "Comida", merchant: "Metro") }
        let previous = (1...31).map { ExpenseSnapshot(amount: 50, date: Self.date(2026, 3, $0), category: "Comida", merchant: "Metro") }

        let r = Rhythm(period: period,
                       current: Accounting.totals(expenses: current, incomes: [], period: period, usdToPen: Self.rate),
                       previous: Accounting.totals(expenses: previous, incomes: [], period: march, usdToPen: Self.rate))

        #expect(Money.equals(r.averagePerDay, 100), "promedio = \(r.averagePerDay)")
        #expect(Money.equals(r.previousAveragePerDay, 50), "anterior = \(r.previousAveragePerDay)")
        #expect(Money.equals(r.dailyDelta, 50))
        #expect(r.headline.contains("más"))
        #expect(!r.headline.contains("menos"))
    }

    @Test("El cambio por categoría se ordena por tamaño y dice de dónde viene")
    func cambioPorCategoria() {
        let period = Self.closedMonth
        let march = Period(granularity: .mes, reference: Self.date(2026, 3, 10))

        let current = [
            ExpenseSnapshot(amount: 500, date: Self.date(2026, 4, 5), category: "Comida", merchant: "Metro"),
            ExpenseSnapshot(amount: 100, date: Self.date(2026, 4, 6), category: "Transporte", merchant: "Uber")
        ]
        let previous = [
            ExpenseSnapshot(amount: 200, date: Self.date(2026, 3, 5), category: "Comida", merchant: "Metro"),
            ExpenseSnapshot(amount: 150, date: Self.date(2026, 3, 6), category: "Transporte", merchant: "Uber")
        ]

        let r = Rhythm(period: period,
                       current: Accounting.totals(expenses: current, incomes: [], period: period, usdToPen: Self.rate),
                       previous: Accounting.totals(expenses: previous, incomes: [], period: march, usdToPen: Self.rate))

        let changes = r.categoryChanges
        #expect(changes.first?.category == "Comida", "el cambio mayor debería ser Comida")
        #expect(Money.equals(changes.first?.delta ?? 0, 300))
        #expect(Money.equals(changes.last?.delta ?? 0, -50), "Transporte bajó 50")
        #expect(Money.equals(r.largestChange, 300))
        #expect(r.supportLine?.contains("Comida") == true)
        #expect(r.supportLine?.contains("aumento") == true)
    }

    @Test("Los días que aún no han llegado no cuentan como días sin gastar")
    func diasSinGastarSoloTranscurridos() {
        // Periodo en curso: el mes actual.
        let period = Period(granularity: .mes, reference: Date())
        let r = Self.rhythm(current: [], previous: [], period: period)

        #expect(r.elapsedDays.count == period.elapsedDays)
        #expect(r.daysWithoutSpending == period.elapsedDays,
                "sin gastos, todos los días transcurridos están sin gastar, y sólo ésos")
        #expect(r.daysWithoutSpending <= period.totalDays)
    }

    @Test("Un año se dibuja en 12 barras, no en 365")
    func agrupacionPorAno() {
        let year = Period(granularity: .anio, reference: Self.date(2025, 6, 15))
        // Un gasto cada día de 2025.
        var current: [ExpenseSnapshot] = []
        for month in 1...12 {
            let days = Period.calendar.range(of: .day, in: .month, for: Self.date(2025, month, 1))!.count
            for day in 1...days {
                current.append(ExpenseSnapshot(amount: 10, date: Self.date(2025, month, day),
                                               category: "Comida", merchant: "Metro"))
            }
        }

        let r = Rhythm(period: year,
                       current: Accounting.totals(expenses: current, incomes: [], period: year, usdToPen: Self.rate),
                       previous: PeriodTotals.empty)

        #expect(r.grouping == .month)
        #expect(r.chartBuckets.count == 12, "salieron \(r.chartBuckets.count) barras")
        // Agrupar no puede perder ni inventar dinero.
        #expect(Money.equals(Money.sum(r.chartBuckets) { $0.total }, r.current.spent))
        #expect(Money.equals(r.averagePerBucket, Money.divide(r.current.spent, by: 12)))
    }

    @Test("Un mes corto se dibuja día a día; un rango largo, por semanas")
    func agrupacionSegunLongitud() {
        let month = Self.closedMonth
        let r = Self.rhythm(current: [], previous: [], period: month)
        #expect(r.grouping == .day)
        #expect(r.chartBuckets.count == 30)

        let longRange = Period(granularity: .rango,
                               customStart: Self.date(2026, 1, 1),
                               customEnd: Self.date(2026, 6, 30))
        let long = Self.rhythm(current: [], previous: [], period: longRange)
        #expect(long.grouping == .week)
        #expect(long.chartBuckets.count < 30, "un rango de seis meses no puede dar 181 barras")
    }

    @Test("El día más caro es un día de la semana con media, no un total")
    func diaMasCaro() {
        let period = Self.closedMonth
        // Todos los gastos en sábados de abril de 2026.
        let saturdays = [4, 11, 18, 25]
        let current = saturdays.map {
            ExpenseSnapshot(amount: 200, date: Self.date(2026, 4, $0), category: "Comida", merchant: "Metro")
        }
        let r = Self.rhythm(current: current, previous: [], period: period)

        #expect(r.busiestWeekday?.name == "Sábado", "salió \(r.busiestWeekday?.name ?? "nil")")
        #expect(Money.equals(r.busiestWeekday?.average ?? 0, 200))
    }
}
