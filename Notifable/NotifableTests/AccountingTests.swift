import Testing
import Foundation
@testable import Notifable

/// Checklist de verificación de ACCOUNTING.md.
///
/// Las igualdades se comprueban con `Money.equals` (céntimos enteros), nunca con
/// `==` sobre `Double`: comparar dinero en punto flotante es exactamente el bug
/// que estas pruebas existen para impedir.
struct AccountingChecklistTests {

    // MARK: - Datos

    static let rate = 3.7512

    /// Conjunto reproducible con lo que rompía antes: montos de 3 decimales,
    /// mezcla de monedas, tipos de cambio propios, deudas con abonos —algunos en
    /// otra moneda— y movimientos exactamente a las 00:00:00.
    static func dataset() -> (expenses: [ExpenseSnapshot], incomes: [IncomeSnapshot]) {
        var generator = SplitMix64(seed: 20260902)
        let cal = Period.calendar
        let categories = ["Comida", "Transporte", "Entretenimiento", "Supermercado", "Otros", Accounting.unclassified]
        let merchants = ["Metro", "Uber", "Netflix", "PLIN - Ana", "YAPE - Luis", "Wong", "Rappi"]
        let origin = cal.date(from: DateComponents(year: 2025, month: 12, day: 1))!

        var expenses: [ExpenseSnapshot] = []
        var incomes: [IncomeSnapshot] = []

        for _ in 0..<900 {
            let date = cal.date(byAdding: .hour,
                                value: generator.int(in: 0..<(300 * 24)),
                                to: origin)!
            let currency = generator.double() < 0.22 ? "USD" : "PEN"
            let amount = generator.double() < 0.12
                ? (generator.double() * 50).rounded(toPlaces: 3)      // 3 decimales sucios
                : (generator.double() * 900 + 0.01).rounded(toPlaces: 2)
            let fx: Double? = (currency == "USD" && generator.double() < 0.8)
                ? (3.4 + generator.double() * 0.55).rounded(toPlaces: 4)
                : nil
            let isDebt = generator.double() < 0.15

            var paidSame = 0.0
            var foreign = false
            if isDebt && generator.double() < 0.7 {
                for _ in 0..<generator.int(in: 1..<4) {
                    let payment = (generator.double() * max(1, amount)).rounded(toPlaces: 2)
                    if generator.double() < 0.75 {
                        paidSame = Money.add(paidSame, payment)
                    } else {
                        foreign = true
                    }
                }
            }

            expenses.append(ExpenseSnapshot(
                amount: amount,
                currency: currency,
                date: date,
                category: categories[generator.int(in: 0..<categories.count)],
                merchant: merchants[generator.int(in: 0..<merchants.count)],
                isDebt: isDebt,
                fxRateAtCapture: fx,
                paymentsInOwnCurrency: paidSame,
                hasForeignPayments: foreign
            ))
        }

        for _ in 0..<220 {
            let date = cal.date(byAdding: .hour, value: generator.int(in: 0..<(300 * 24)), to: origin)!
            let currency = generator.double() < 0.2 ? "USD" : "PEN"
            incomes.append(IncomeSnapshot(
                amount: (generator.double() * 3000 + 5).rounded(toPlaces: 2),
                currency: currency,
                date: date,
                isDebtPayment: generator.double() < 0.35,
                fxRateAtCapture: currency == "USD" ? 3.6 : nil
            ))
        }

        // Fronteras exactas: 00:00:00 del día 1 de mes, de año y de semana.
        for components in [DateComponents(year: 2026, month: 9, day: 1),
                           DateComponents(year: 2026, month: 1, day: 1),
                           DateComponents(year: 2026, month: 8, day: 31),
                           DateComponents(year: 2026, month: 9, day: 7)] {
            let date = cal.date(from: components)!
            expenses.append(ExpenseSnapshot(amount: 123.45, currency: "PEN", date: date,
                                            category: "Comida", merchant: "Metro"))
            incomes.append(IncomeSnapshot(amount: 50, currency: "PEN", date: date))
        }

        return (expenses, incomes)
    }

    static func month(_ year: Int, _ month: Int) -> Period {
        Period(granularity: .mes, reference: Period.calendar.date(from: DateComponents(year: year, month: month, day: 10))!)
    }

    // MARK: - 1

    @Test("1. spent == suma de categorías == suma de comercios == suma de días")
    func desglosesCuadran() {
        let (expenses, incomes) = Self.dataset()
        let cal = Period.calendar
        let periods: [Period] = [
            Self.month(2026, 9),
            Period(granularity: .semana, reference: cal.date(from: DateComponents(year: 2026, month: 9, day: 10))!),
            Period(granularity: .anio, reference: cal.date(from: DateComponents(year: 2026, month: 5, day: 1))!),
            Period(granularity: .dia, reference: cal.date(from: DateComponents(year: 2026, month: 9, day: 1))!),
            Period(granularity: .rango,
                   customStart: cal.date(from: DateComponents(year: 2026, month: 3, day: 3))!,
                   customEnd: cal.date(from: DateComponents(year: 2026, month: 5, day: 20))!)
        ]

        for period in periods {
            let totals = Accounting.totals(expenses: expenses, incomes: incomes, period: period, usdToPen: Self.rate)
            #expect(Money.equals(totals.spent, Money.sum(totals.byCategory) { $0.total }),
                    "categorías ≠ total en \(period.granularity.rawValue)")
            #expect(Money.equals(totals.spent, Money.sum(totals.byMerchant) { $0.total }),
                    "comercios ≠ total en \(period.granularity.rawValue)")
            #expect(Money.equals(totals.spent, Money.sum(totals.dailySpent) { $0.total }),
                    "días ≠ total en \(period.granularity.rawValue)")
        }
    }

    // MARK: - 2

    @Test("2. un periodo == la suma de sus subperiodos")
    func periodosSonAditivos() {
        let (expenses, incomes) = Self.dataset()
        let cal = Period.calendar

        let year = Period(granularity: .anio, reference: cal.date(from: DateComponents(year: 2026, month: 6, day: 1))!)
        let yearTotal = Accounting.totals(expenses: expenses, incomes: incomes, period: year, usdToPen: Self.rate).spent
        let monthsTotal = Money.sum((1...12).map { month in
            Accounting.totals(expenses: expenses, incomes: incomes,
                              period: Self.month(2026, month), usdToPen: Self.rate).spent
        })
        #expect(Money.equals(yearTotal, monthsTotal), "año \(yearTotal) ≠ 12 meses \(monthsTotal)")

        let month = Self.month(2026, 4)
        let monthTotal = Accounting.totals(expenses: expenses, incomes: incomes, period: month, usdToPen: Self.rate).spent
        let daysTotal = Money.sum(month.days.map { day in
            Accounting.totals(expenses: expenses, incomes: incomes,
                              period: Period(granularity: .dia, reference: day), usdToPen: Self.rate).spent
        })
        #expect(Money.equals(monthTotal, daysTotal), "mes \(monthTotal) ≠ sus días \(daysTotal)")

        // 12 semanas consecutivas deben sumar exactamente el rango que cubren.
        var weeks: [Period] = [Period(granularity: .semana,
                                      reference: cal.date(from: DateComponents(year: 2026, month: 3, day: 2))!)]
        for _ in 0..<11 { weeks.append(weeks[weeks.count - 1].next) }
        let span = Period(granularity: .rango,
                          customStart: weeks[0].interval.start,
                          customEnd: cal.date(byAdding: .day, value: -1, to: weeks[weeks.count - 1].interval.end)!)
        let spanTotal = Accounting.totals(expenses: expenses, incomes: incomes, period: span, usdToPen: Self.rate).spent
        let weeksTotal = Money.sum(weeks.map {
            Accounting.totals(expenses: expenses, incomes: incomes, period: $0, usdToPen: Self.rate).spent
        })
        #expect(Money.equals(spanTotal, weeksTotal), "rango \(spanTotal) ≠ 12 semanas \(weeksTotal)")
    }

    // MARK: - 3

    @Test("3. ningún movimiento cae en dos periodos consecutivos")
    func sinDobleConteoEnLaFrontera() {
        let (expenses, _) = Self.dataset()
        let cal = Period.calendar

        for month in 1...11 {
            let a = Self.month(2026, month)
            let b = a.next
            #expect(!expenses.contains { a.contains($0.date) && b.contains($0.date) },
                    "movimiento duplicado entre meses \(month) y \(month + 1)")
        }

        let start = cal.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        for offset in 0..<40 {
            let a = Period(granularity: .dia, reference: cal.date(byAdding: .day, value: offset, to: start)!)
            let b = a.next
            #expect(!expenses.contains { a.contains($0.date) && b.contains($0.date) },
                    "movimiento duplicado entre días consecutivos")
        }

        // El caso concreto: 00:00:00 del día 1 pertenece al mes nuevo y sólo a él.
        let midnight = cal.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        #expect(Self.month(2026, 9).contains(midnight))
        #expect(!Self.month(2026, 8).contains(midnight))
    }

    // MARK: - 4

    @Test("4. marcar o desmarcar una deuda no cambia el gasto")
    func deudaNoAlteraElGasto() {
        let data = Self.dataset()
        var expenses = data.expenses
        let incomes = data.incomes
        let period = Self.month(2026, 9)
        let before = Accounting.totals(expenses: expenses, incomes: incomes, period: period, usdToPen: Self.rate)

        var flipped = 0
        for index in expenses.indices where period.contains(expenses[index].date) && flipped < 5 {
            expenses[index].isDebt.toggle()
            flipped += 1
        }
        let after = Accounting.totals(expenses: expenses, incomes: incomes, period: period, usdToPen: Self.rate)

        #expect(flipped > 0, "el conjunto de prueba no tiene gastos en el periodo")
        #expect(Money.equals(before.spent, after.spent), "\(before.spent) → \(after.spent)")
    }

    // MARK: - 5

    @Test("5. un abono no cambia el gasto ni el ingreso; sólo baja el saldo")
    func abonoSoloBajaElSaldo() {
        let period = Self.month(2026, 9)
        let cal = Period.calendar
        let day = cal.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 10))!

        var debt = ExpenseSnapshot(amount: 500, currency: "PEN", date: day,
                                   category: "Otros", merchant: "Metro", isDebt: true)
        let salary = IncomeSnapshot(amount: 2000, currency: "PEN", date: day)

        let before = Accounting.totals(expenses: [debt], incomes: [salary], period: period, usdToPen: Self.rate)

        debt.paymentsInOwnCurrency = 40
        let payment = IncomeSnapshot(amount: 40, currency: "PEN",
                                     date: cal.date(from: DateComponents(year: 2026, month: 9, day: 9))!,
                                     isDebtPayment: true)
        let after = Accounting.totals(expenses: [debt], incomes: [salary, payment], period: period, usdToPen: Self.rate)

        #expect(Money.equals(before.spent, after.spent), "el gasto cambió: \(before.spent) → \(after.spent)")
        #expect(Money.equals(before.income, after.income), "el ingreso cambió: \(before.income) → \(after.income)")
        #expect(Money.equals(Money.subtract(before.debtOutstanding, after.debtOutstanding), 40),
                "el saldo no bajó 40: \(before.debtOutstanding) → \(after.debtOutstanding)")
        #expect(Money.equals(after.debtPayments, 40))
        // Y el abono no infla el balance por partida doble.
        #expect(Money.equals(after.balance ?? 0, Money.subtract(2000, 500)))
    }

    @Test("5b. un abono en otra moneda no salda una deuda en soles")
    func abonoEnOtraMonedaNoSalda() {
        let day = Period.calendar.date(from: DateComponents(year: 2026, month: 9, day: 5))!
        let debt = ExpenseSnapshot(amount: 500, currency: "PEN", date: day, isDebt: true,
                                   paymentsInOwnCurrency: 0, hasForeignPayments: true)
        #expect(Money.equals(Accounting.outstanding(of: debt), 500),
                "un abono de $ 40 restó soles: \(Accounting.outstanding(of: debt))")
        #expect(debt.hasForeignPayments)
    }

    @Test("5c. un abono no puede exceder el saldo")
    func abonoSeLimitaAlSaldo() {
        let day = Period.calendar.date(from: DateComponents(year: 2026, month: 9, day: 5))!
        let debt = ExpenseSnapshot(amount: 100, currency: "PEN", date: day, isDebt: true,
                                   paymentsInOwnCurrency: 60)
        #expect(Money.equals(Accounting.clampPayment(400, to: debt), 40))
    }

    // MARK: - 6

    @Test("6. el total de un mes cerrado no se mueve al actualizarse el tipo de cambio")
    func mesCerradoEsEstable() {
        let (all, incomes) = Self.dataset()
        // Con el tipo de cambio del día guardado en cada movimiento.
        let captured = all.filter { $0.currency == "PEN" || $0.fxRateAtCapture != nil }
        let period = Self.month(2026, 4)

        let low = Accounting.totals(expenses: captured, incomes: incomes, period: period, usdToPen: 3.75).spent
        let high = Accounting.totals(expenses: captured, incomes: incomes, period: period, usdToPen: 4.90).spent
        #expect(Money.equals(low, high), "el mes cerrado cambió: \(low) → \(high)")
    }

    // MARK: - 7

    @Test("7. con el periodo vacío no aparece nan, inf ni -0.00")
    func periodoVacioNoImprimeBasura() {
        let (expenses, incomes) = Self.dataset()
        let empty = Period(granularity: .mes,
                           reference: Period.calendar.date(from: DateComponents(year: 2019, month: 3, day: 1))!)
        let totals = Accounting.totals(expenses: expenses, incomes: incomes, period: empty, usdToPen: Self.rate)

        let values = [totals.spent, totals.income, totals.debtPayments,
                      totals.debtOutstanding, totals.unclassifiedTotal, totals.averagePerDay]
        for value in values {
            #expect(value.isFinite)
            #expect(!Money.format(value).contains("nan"))
            #expect(!Money.format(value).contains("-0.00"))
        }
        #expect(totals.balance == nil, "sin ingresos el balance debe apagarse, no salir en negativo")
        #expect(Money.ratio(10, to: 0) == nil)
        #expect(Money.percent(10, of: 0) == nil)
        #expect(Money.formatPercent(10, of: 0) == "—")
    }

    // MARK: - Money

    @Test("Money: la suma no deriva y 1.005 redondea a 1.01")
    func aritmeticaEstable() {
        #expect(Money.equals(Money.sum([0.1, 0.2]), 0.30))
        #expect(Money.equals(Money.normalized(1.005), 1.01),
                "1.005 se fue a \(Money.normalized(1.005)); el redondeo vuelve a partir del binario")
        #expect(Money.equals(Money.sum(Money.split(100, into: 3)), 100))
        #expect(Money.equals(Money.sum(Money.split(-10, into: 4)), -10))
        #expect(Money.equals(Money.sum(Array(repeating: 0.01, count: 10_000)), 100))
        #expect(Money.cents(45.50) == 4550)
    }

    @Test("Period: no se navega al futuro, pero sí dentro de la semana actual")
    func navegacionHaciaAdelante() {
        // ACCOUNTING.md §12: estando en lunes, la flecha derecha debe funcionar.
        let cal = Period.calendar
        let monday = cal.dateInterval(of: .weekOfYear, for: Date())!.start
        let today = Period(granularity: .dia, reference: monday)
        if cal.startOfDay(for: monday) < cal.startOfDay(for: Date()) {
            #expect(today.canGoForward, "no se puede avanzar de día dentro de la semana actual")
        }
        let future = Period(granularity: .mes, reference: cal.date(byAdding: .month, value: 1, to: Date())!)
        #expect(!future.canGoForward)
    }

    @Test("Period: sobrevive a @AppStorage")
    func periodoSeGuardaYSeLee() {
        let period = Period(granularity: .semana, reference: Date())
        let restored = Period(rawValue: period.rawValue)
        #expect(restored?.granularity == .semana)
        #expect(restored?.interval == period.interval)
    }
}

// MARK: - Utilidades de prueba

/// Generador determinista: los mismos datos en cada ejecución y en cada máquina.
private struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func double() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    mutating func int(in range: Range<Int>) -> Int {
        range.lowerBound + Int(double() * Double(range.count))
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
