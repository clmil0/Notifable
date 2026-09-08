import Testing
import Foundation
import SwiftData
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

    /// La marca por sí sola no cambia nada: lo que descuenta es el dinero
    /// devuelto, no la etiqueta. Un gasto marcado por cobrar del que aún no te
    /// han devuelto nada sigue costándote lo mismo.
    @Test("4. marcar o desmarcar una deuda, sin devoluciones, no cambia el gasto")
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

    /// **Cambiado a propósito.** Antes se exigía que un abono no tocara el
    /// gasto ("un gasto de S/ 100 con S/ 40 abonados sigue siendo de S/ 100").
    /// Eso contradecía lo que la app promete —"lo marcas como por cobrar y no
    /// cuenta en tu mes"— y dejaba la función sin efecto: marcar algo por
    /// cobrar y cobrarlo no movía ninguna cifra. Ahora el abono **sí** baja el
    /// gasto; lo que sigue sin tocar es el ingreso, porque cobrar una deuda es
    /// liquidar un pasivo, no ingresar.
    @Test("5. un abono baja el gasto y el saldo, pero nunca es ingreso")
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

        #expect(Money.equals(Money.subtract(before.spent, after.spent), 40),
                "el gasto no bajó los 40 devueltos: \(before.spent) → \(after.spent)")
        #expect(Money.equals(before.income, after.income), "el ingreso cambió: \(before.income) → \(after.income)")
        #expect(Money.equals(Money.subtract(before.debtOutstanding, after.debtOutstanding), 40),
                "el saldo no bajó 40: \(before.debtOutstanding) → \(after.debtOutstanding)")
        #expect(Money.equals(after.debtPayments, 40))
        // Y el abono no infla el balance por partida doble.
        #expect(Money.equals(after.balance ?? 0, Money.subtract(2000, 460)),
                "el balance debe partir del gasto neto, ya sin los 40 devueltos")
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

/// El atajo de `totalsSnapshot`: `Accounting.totals` no debe cambiar de
/// resultado por saltarse la relación `payments` en los gastos que no son deuda.
///
/// Se prueba sobre `@Model` reales y no sobre `ExpenseSnapshot`, porque lo que
/// se está fijando es justamente el puente entre SwiftData y la contabilidad:
/// si el `guard isDebt` se invirtiera, el saldo de las deudas se calcularía
/// como si no tuvieran abonos y nada más lo detectaría.
@MainActor
struct TotalsSnapshotTests {

    static let cal = Period.calendar

    static func makeContext() throws -> ModelContext {
        let schema = Schema([Expense.self, Income.self, RecurringExpense.self, QuickExpense.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    static func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 9))!
    }

    @Test("Una deuda con abonos conserva su saldo pendiente en los totales")
    func deudaConAbonos() throws {
        let context = try Self.makeContext()
        let fecha = Self.day(2026, 3, 10)

        let deuda = Expense(amount: 200, merchant: "Cena", date: fecha,
                            category: "Comida", currency: "PEN", isDebt: true)
        context.insert(deuda)

        let abono = Income(amount: 80, currency: "PEN", source: "Jorge",
                           date: Self.day(2026, 3, 15))
        abono.debtReference = deuda
        context.insert(abono)

        let normal = Expense(amount: 50, merchant: "Metro", date: fecha,
                             category: "Supermercado", currency: "PEN")
        context.insert(normal)

        let period = Period(granularity: .mes, reference: fecha)
        let totals = Accounting.totals(expenses: [deuda, normal], incomes: [abono],
                                       period: period, usdToPen: 3.7)

        // El gasto neto: la deuda aporta lo que aún no te han devuelto
        // (200 − 80 = 120) más el gasto normal de 50.
        #expect(Money.cents(totals.spent) == Money.cents(170))
        // El saldo pendiente sí descuenta el abono: 200 − 80.
        #expect(Money.cents(totals.debtOutstanding) == Money.cents(120))
        // Y el abono no es ingreso.
        #expect(Money.isZero(totals.income))
        #expect(Money.cents(totals.debtPayments) == Money.cents(80))
    }

    @Test("El atajo da exactamente lo mismo que el snapshot completo")
    func atajoEquivalente() throws {
        let context = try Self.makeContext()
        let fecha = Self.day(2026, 3, 10)

        let deuda = Expense(amount: 300, merchant: "Viaje", date: fecha,
                            category: "Otros", currency: "PEN", isDebt: true)
        context.insert(deuda)
        let abono = Income(amount: 120, currency: "PEN", source: "Ana", date: fecha)
        abono.debtReference = deuda
        context.insert(abono)

        let sueltos = (1...5).map { i in
            Expense(amount: Double(i) * 17.5, merchant: "Comercio \(i)", date: fecha,
                    category: i.isMultiple(of: 2) ? "Comida" : "Transporte")
        }
        sueltos.forEach { context.insert($0) }

        let todos = [deuda] + sueltos
        let period = Period(granularity: .mes, reference: fecha)

        let rapido = Accounting.totals(expenses: todos, incomes: [abono],
                                       period: period, usdToPen: 3.7)
        let completo = Accounting.totals(expenses: todos.map(\.accountingSnapshot),
                                         incomes: [abono.accountingSnapshot],
                                         period: period, usdToPen: 3.7)

        #expect(Money.cents(rapido.spent) == Money.cents(completo.spent))
        #expect(Money.cents(rapido.debtOutstanding) == Money.cents(completo.debtOutstanding))
        #expect(rapido.byCategory.map { $0.category } == completo.byCategory.map { $0.category })
        #expect(rapido.byMerchant.map { $0.merchant } == completo.byMerchant.map { $0.merchant })
        #expect(rapido.expenseCount == completo.expenseCount)
        #expect(rapido.hasForeignDebtPayments == completo.hasForeignDebtPayments)
    }
}

/// Devoluciones: lo que cuesta un gasto y cuándo queda saldada una deuda.
///
/// Los dos bugs que fija este archivo se reportaron juntos y salían del mismo
/// sitio —el flujo de registrar un abono—, así que se prueban juntos.
@MainActor
struct DevolucionesTests {

    static func makeContext() throws -> ModelContext {
        let schema = Schema([Expense.self, Income.self, RecurringExpense.self, QuickExpense.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    static func deuda(_ context: ModelContext, amount: Double = 500) -> Expense {
        let e = Expense(amount: amount, merchant: "Prestamo a Ana", date: Date(),
                        category: "Prestamos", isDebt: true)
        context.insert(e)
        try? context.save()
        return e
    }

    /// Reproduce el caso reportado paso a paso, por el mismo camino que el
    /// formulario: elegir la deuda, teclear el monto y guardar.
    ///
    /// El bug: `AddTransactionSheet` leía `draft.cancelsDebt` **después** de
    /// crear el `Income`, y construirlo con `debtReference` ya lo engancha a
    /// `debt.payments`. Desde ese instante el saldo descontaba el abono que se
    /// estaba registrando, así que la condición real era "saldo_después ≤
    /// monto": con 500 y dos abonos de 200, (500−400)=100 ≤ 200 y la deuda se
    /// daba por saldada faltando 100.
    @Test("Dos abonos de 200 sobre 500 dejan saldo de 100 y NO saldan la deuda")
    func dosAbonosNoSaldanDeMas() throws {
        let context = try Self.makeContext()
        let deuda = Self.deuda(context)

        for _ in 1...2 {
            var draft = TransactionDraft(type: .ingreso)
            draft.isDebtPayment = true
            draft.selectDebt(deuda)
            draft.currency = deuda.currency
            draft.source = "Ana"
            draft.amountText = "200"

            guard let resolution = draft.resolveIncome() else {
                Issue.record("el formulario rechazó un abono válido")
                return
            }
            context.insert(resolution.income)
            if resolution.cancelsDebt { deuda.isDebt = false }
            try? context.save()
        }

        #expect(Money.equals(Accounting.paid(of: deuda), 400))
        #expect(Money.equals(Accounting.outstanding(of: deuda), 100))
        #expect(deuda.isDebt, "quedó saldada con 400 de 500")
    }

    @Test("El abono que sí cubre el saldo restante salda la deuda")
    func elUltimoAbonoSalda() throws {
        let context = try Self.makeContext()
        let deuda = Self.deuda(context)

        for monto in ["200", "200", "100"] {
            var draft = TransactionDraft(type: .ingreso)
            draft.isDebtPayment = true
            draft.selectDebt(deuda)
            draft.currency = deuda.currency
            draft.source = "Ana"
            draft.amountText = monto

            guard let resolution = draft.resolveIncome() else { continue }
            context.insert(resolution.income)
            if resolution.cancelsDebt { deuda.isDebt = false }
            try? context.save()
        }

        #expect(Money.equals(Accounting.outstanding(of: deuda), 0))
        #expect(!deuda.isDebt, "con los 500 devueltos debería quedar saldada")
    }

    /// El otro síntoma del mismo bug: al guardar, el monto se pintaba en rojo
    /// como si superara lo que te deben.
    @Test("Un abono parcial no se marca como excedido")
    func abonoParcialNoExcede() throws {
        let context = try Self.makeContext()
        let deuda = Self.deuda(context)

        var draft = TransactionDraft(type: .ingreso)
        draft.isDebtPayment = true
        draft.selectDebt(deuda)
        draft.currency = deuda.currency
        draft.source = "Ana"
        draft.amountText = "200"

        let resolution = draft.resolveIncome()
        context.insert(resolution!.income)
        try? context.save()

        // Un segundo abono de 200 sobre un saldo de 300 no excede nada.
        var segundo = TransactionDraft(type: .ingreso)
        segundo.isDebtPayment = true
        segundo.selectDebt(deuda)
        segundo.currency = deuda.currency
        segundo.source = "Ana"
        segundo.amountText = "200"

        #expect(Money.equals(segundo.debtOutstanding ?? 0, 300))
        #expect(segundo.excessOverDebt == nil, "dice que excede sin exceder")
        #expect(!segundo.cancelsDebt)
        #expect(segundo.validation == .ready)
    }

    // MARK: - Lo devuelto resta del gasto

    /// La app promete en el onboarding que lo que te van a devolver "no cuenta
    /// en tu mes". Antes el gasto se contaba entero y marcarlo por cobrar no
    /// movía ninguna cifra.
    @Test("Lo devuelto baja el gasto del mes")
    func loDevueltoBajaElGasto() throws {
        let context = try Self.makeContext()
        let hoy = Date()
        let deuda = Expense(amount: 500, merchant: "Cena", date: hoy,
                            category: "Comida", isDebt: true)
        context.insert(deuda)

        let periodo = Period(granularity: .mes, reference: hoy)
        let antes = Accounting.totals(expenses: [deuda], incomes: [],
                                      period: periodo, usdToPen: 3.7)
        #expect(Money.equals(antes.spent, 500))

        let abono = Income(amount: 200, currency: "PEN", source: "Ana",
                           date: hoy, debtReference: deuda)
        context.insert(abono)
        try? context.save()

        let despues = Accounting.totals(expenses: [deuda], incomes: [abono],
                                        period: periodo, usdToPen: 3.7)
        #expect(Money.equals(despues.spent, 300), "el gasto no bajó con la devolución")
        #expect(Money.equals(despues.debtOutstanding, 300))
        // El abono sigue sin ser ingreso: es liquidación de un pasivo.
        #expect(Money.isZero(despues.income))
        #expect(Money.equals(despues.debtPayments, 200))
    }

    @Test("Un gasto devuelto por completo no cuenta en el mes")
    func devueltoEnteroNoCuenta() throws {
        let context = try Self.makeContext()
        let hoy = Date()
        let gasto = Expense(amount: 500, merchant: "Cena", date: hoy,
                            category: "Comida", isDebt: true)
        context.insert(gasto)
        let abono = Income(amount: 500, currency: "PEN", source: "Ana",
                           date: hoy, debtReference: gasto)
        context.insert(abono)
        // Al saldarse deja de estar por cobrar: aun así no debe volver a contar.
        gasto.isDebt = false
        try? context.save()

        let totals = Accounting.totals(expenses: [gasto], incomes: [abono],
                                       period: Period(granularity: .mes, reference: hoy),
                                       usdToPen: 3.7)
        #expect(Money.isZero(totals.spent), "un gasto ya devuelto sigue contando")
    }

    @Test("Los desgloses siguen sumando exactamente el gasto neto")
    func desglosesCuadranConDevoluciones() throws {
        let context = try Self.makeContext()
        let hoy = Date()
        let a = Expense(amount: 500, merchant: "Cena", date: hoy, category: "Comida", isDebt: true)
        let b = Expense(amount: 120, merchant: "Taxi", date: hoy, category: "Transporte")
        context.insert(a)
        context.insert(b)
        let abono = Income(amount: 200, currency: "PEN", source: "Ana", date: hoy, debtReference: a)
        context.insert(abono)
        try? context.save()

        let totals = Accounting.totals(expenses: [a, b], incomes: [abono],
                                       period: Period(granularity: .mes, reference: hoy),
                                       usdToPen: 3.7)

        #expect(Money.equals(totals.spent, 420))          // (500−200) + 120
        #expect(Money.equals(Money.sum(totals.byCategory) { $0.total }, totals.spent))
        #expect(Money.equals(Money.sum(totals.byMerchant) { $0.total }, totals.spent))
        #expect(Money.equals(Money.sum(totals.dailySpent) { $0.total }, totals.spent))
    }
}

/// El formulario no puede cambiar de opinión después de guardar.
///
/// Al construir el `Income` con `debtReference`, el abono queda enganchado a la
/// deuda al instante. Si el borrador leyera el saldo en vivo, durante los
/// instantes que la hoja tarda en cerrarse recalcularía todo contra un saldo que
/// ya descuenta ese abono: el monto se pintaba en rojo por "exceso" y el aviso
/// de "queda saldado" salía sin motivo, con el movimiento ya guardado bien.
@MainActor
struct BorradorTrasGuardarTests {

    static func makeContext() throws -> ModelContext {
        let schema = Schema([Expense.self, Income.self, RecurringExpense.self, QuickExpense.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    /// El caso reportado: 15.10 por cobrar, abono de 10.00.
    @Test("Tras guardar, el borrador sigue diciendo lo mismo que antes")
    func elBorradorNoSeContradice() throws {
        let context = try Self.makeContext()
        let deuda = Expense(amount: 15.10, merchant: "Almuerzo", date: Date(),
                            category: "Comida", isDebt: true)
        context.insert(deuda)
        try? context.save()

        var draft = TransactionDraft(type: .ingreso)
        draft.isDebtPayment = true
        draft.selectDebt(deuda)
        draft.currency = deuda.currency
        draft.source = "Ana"
        draft.amountText = "10.00"

        // Lo que el usuario ve antes de tocar guardar.
        #expect(Money.equals(draft.debtRemainder ?? -1, 5.10))
        #expect(draft.validation == .ready)
        #expect(draft.excessOverDebt == nil)
        #expect(!draft.cancelsDebt)

        guard let resolution = draft.resolveIncome() else {
            Issue.record("el formulario rechazó un abono válido")
            return
        }
        context.insert(resolution.income)
        try? context.save()

        // Y exactamente lo mismo después: la hoja sigue en pantalla un momento.
        #expect(draft.validation == .ready, "el monto se pintó en rojo tras guardar")
        #expect(draft.excessOverDebt == nil, "dijo que excedía un saldo que él mismo acababa de bajar")
        #expect(!draft.cancelsDebt, "anunció que quedaba saldada faltando 5.10")
        #expect(Money.equals(draft.debtRemainder ?? -1, 5.10))

        // Y la contabilidad, correcta.
        #expect(Money.equals(Accounting.outstanding(of: deuda), 5.10))
        #expect(deuda.isDebt)
    }
}
