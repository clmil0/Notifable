import Testing
import Foundation
@testable import Notifable

/// Los límites por categoría. Lo que se comprueba aquí es lo que la pantalla no
/// puede enseñar mal: el ciclo (que no depende del periodo visible), el mes con
/// otro límite, el sobrante traspasado y el promedio contra el que se propone
/// un monto alcanzable.
struct CategoryBudgetTests {

    static let cal = Period.calendar

    static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    static func expense(_ amount: Double, _ date: Date, category: String = "Comida") -> ExpenseSnapshot {
        ExpenseSnapshot(amount: amount, currency: "PEN", date: date, category: category, merchant: "TIENDA")
    }

    static func budget(amount: Double = 600,
                       cycle: CategoryBudget.Cycle = .mes,
                       anchorDay: Int = 1,
                       rollsOver: Bool = false,
                       overrides: [CategoryBudget.Override] = []) -> CategoryBudget {
        CategoryBudget(category: "Comida",
                       amount: amount,
                       cycle: cycle,
                       anchorDay: anchorDay,
                       alertThreshold: 0.8,
                       rollsOver: rollsOver,
                       countsInGlobalBudget: true,
                       overrides: overrides)
    }

    // MARK: - Ciclo

    @Test("El ciclo mensual con día 1 es el mes natural")
    func cicloMensual() {
        let interval = Self.budget().interval(containing: Self.day(2026, 9, 11))
        #expect(Self.cal.component(.day, from: interval.start) == 1)
        #expect(Self.cal.component(.month, from: interval.start) == 9)
        #expect(Self.cal.component(.month, from: interval.end) == 10)
    }

    @Test("El día de corte mueve el ciclo al mes anterior")
    func cicloConDiaDePago() {
        let budget = Self.budget(anchorDay: 28)

        // El 11 de septiembre todavía estás en el ciclo que empezó el 28 de agosto.
        let before = budget.interval(containing: Self.day(2026, 9, 11))
        #expect(Self.cal.component(.month, from: before.start) == 8)
        #expect(Self.cal.component(.day, from: before.start) == 28)

        // El 29 ya estás en el siguiente.
        let after = budget.interval(containing: Self.day(2026, 9, 29))
        #expect(Self.cal.component(.month, from: after.start) == 9)
        #expect(Self.cal.component(.day, from: after.start) == 28)
    }

    @Test("La quincena parte el ciclo en dos")
    func cicloQuincenal() {
        let budget = Self.budget(cycle: .quincena)
        let first = budget.interval(containing: Self.day(2026, 9, 3))
        let second = budget.interval(containing: Self.day(2026, 9, 20))
        #expect(first.end == second.start)
        #expect(first.start < first.end)
    }

    /// La decisión de producto: filtrar por un día no encoge el límite. El saldo
    /// que se ve al asignar es siempre el del ciclo, nunca el de la ventana
    /// visible del Resumen.
    @Test("Filtrar por un día no cambia el ciclo del límite")
    func elFiltroNoEncogeElLimite() {
        let budget = Self.budget()
        let expenses = [
            Self.expense(200, Self.day(2026, 9, 2)),
            Self.expense(150, Self.day(2026, 9, 11)),
            Self.expense(100, Self.day(2026, 9, 25))
        ]

        var day = Period(granularity: .dia, reference: Self.day(2026, 9, 11))
        let onDay = CategoryLimits.status(category: "Comida",
                                          budget: budget,
                                          expenses: expenses,
                                          on: CategoryLimits.referenceDate(for: day),
                                          usdToPen: 3.7)
        #expect(Money.equals(onDay.spent, 450))

        day.granularity = .mes
        let onMonth = CategoryLimits.status(category: "Comida",
                                            budget: budget,
                                            expenses: expenses,
                                            on: CategoryLimits.referenceDate(for: day),
                                            usdToPen: 3.7)
        #expect(Money.equals(onMonth.spent, onDay.spent))
    }

    @Test("Un rango de varios meses se mira en el más reciente")
    func rangoTomaElMesMasReciente() {
        var range = Period(granularity: .rango, reference: Self.day(2026, 9, 15))
        range.customStart = Self.day(2026, 7, 1)
        range.customEnd = Self.day(2026, 9, 15)

        let reference = CategoryLimits.referenceDate(for: range)
        #expect(Self.cal.component(.month, from: reference) == 9)
    }

    // MARK: - Excepciones

    @Test("Diciembre usa su propio límite y se repite cada año")
    func excepcionPorMes() {
        let budget = Self.budget(overrides: [CategoryBudget.Override(month: 12, year: nil, amount: 1100)])
        #expect(Money.equals(budget.amount(on: Self.day(2026, 12, 5)), 1100))
        #expect(Money.equals(budget.amount(on: Self.day(2030, 12, 5)), 1100))
        #expect(Money.equals(budget.amount(on: Self.day(2026, 11, 5)), 600))
    }

    @Test("Una excepción con año sólo vale ese año")
    func excepcionDeUnAno() {
        let budget = Self.budget(overrides: [CategoryBudget.Override(month: 3, year: 2026, amount: 900)])
        #expect(Money.equals(budget.amount(on: Self.day(2026, 3, 5)), 900))
        #expect(Money.equals(budget.amount(on: Self.day(2027, 3, 5)), 600))
    }

    // MARK: - Estado

    @Test("El saldo y el nivel salen del gasto del ciclo")
    func nivelDelLimite() {
        let budget = Self.budget()
        let expenses = [Self.expense(555, Self.day(2026, 9, 10))]
        let status = CategoryLimits.status(category: "Comida",
                                           budget: budget,
                                           expenses: expenses,
                                           on: Self.day(2026, 9, 22),
                                           usdToPen: 3.7)

        #expect(Money.equals(status.remaining, 45))
        #expect(status.level == .cerca)          // 92% con umbral en 80%
        #expect(status.shortLabel == "S/ 45 libres")
        #expect(status.daysLeft == 9)
    }

    @Test("Pasarse informa, no bloquea")
    func pasado() {
        let budget = Self.budget(amount: 400)
        let expenses = [Self.expense(460, Self.day(2026, 9, 9))]
        let status = CategoryLimits.status(category: "Comida",
                                           budget: budget,
                                           expenses: expenses,
                                           on: Self.day(2026, 9, 21),
                                           usdToPen: 3.7)
        #expect(status.isOver)
        #expect(Money.equals(status.overBy, 60))
        #expect(status.shortLabel == "S/ 60 pasado")
        #expect(status.fraction == 1)            // la barra no se sale de la pista
    }

    @Test("Sin límite no hay nivel ni barra")
    func sinLimite() {
        let status = CategoryLimits.status(category: "Transporte",
                                           budget: nil,
                                           expenses: [],
                                           on: Self.day(2026, 9, 11),
                                           usdToPen: 3.7)
        #expect(!status.hasLimit)
        #expect(status.level == .sinLimite)
        #expect(status.shortLabel == "Sin límite")
    }

    // MARK: - Traspaso

    @Test("El sobrante del ciclo anterior suma al límite, y sólo un ciclo")
    func traspaso() {
        let budget = Self.budget(amount: 600, rollsOver: true)
        let expenses = [
            Self.expense(400, Self.day(2026, 8, 10)),   // sobraron 200
            Self.expense(100, Self.day(2026, 9, 5))
        ]
        let status = CategoryLimits.status(category: "Comida",
                                           budget: budget,
                                           expenses: expenses,
                                           on: Self.day(2026, 9, 11),
                                           usdToPen: 3.7)
        #expect(Money.equals(status.carriedOver, 200))
        #expect(Money.equals(status.limit, 800))
        #expect(Money.equals(status.remaining, 700))
    }

    @Test("Sin traspaso el sobrante no viaja")
    func sinTraspaso() {
        let budget = Self.budget(amount: 600)
        let expenses = [Self.expense(400, Self.day(2026, 8, 10))]
        let status = CategoryLimits.status(category: "Comida",
                                           budget: budget,
                                           expenses: expenses,
                                           on: Self.day(2026, 9, 11),
                                           usdToPen: 3.7)
        #expect(Money.isZero(status.carriedOver))
        #expect(Money.equals(status.limit, 600))
    }

    // MARK: - Promedio

    @Test("El promedio son los ciclos cerrados, no el actual")
    func promedio() {
        let budget = Self.budget()
        let expenses = [
            Self.expense(600, Self.day(2026, 6, 10)),
            Self.expense(700, Self.day(2026, 7, 10)),
            Self.expense(686, Self.day(2026, 8, 10)),
            Self.expense(9999, Self.day(2026, 9, 10))   // el mes en curso no cuenta
        ]
        let average = CategoryLimits.average(budget: budget,
                                             expenses: expenses,
                                             on: Self.day(2026, 9, 11),
                                             usdToPen: 3.7)
        #expect(Money.equals(average ?? 0, 662))
    }

    @Test("La propuesta redondea al alza: por debajo del promedio se incumple siempre")
    func propuesta() {
        #expect(CategoryLimits.suggestedLimit(from: 662) == 670)
        #expect(CategoryLimits.suggestedLimit(from: 660) == 660)
    }

    @Test("Sin ningún ciclo cerrado con gasto no hay promedio que proponer")
    func promedioVacio() {
        let average = CategoryLimits.average(budget: Self.budget(),
                                             expenses: [],
                                             on: Self.day(2026, 9, 11),
                                             usdToPen: 3.7)
        #expect(average == nil)
    }

    // MARK: - Reparto contra el presupuesto

    @Test("La suma de límites se normaliza a mensual")
    func repartoMensual() {
        let store = CategoryBudgetStore(defaults: UserDefaults(suiteName: "test-reparto")!)
        store.save(CategoryBudget(category: "Comida", amount: 600))
        store.save(CategoryBudget(category: "Hogar", amount: 400))
        var semanal = CategoryBudget(category: "Transporte", amount: 100)
        semanal.cycle = .semana
        store.save(semanal)

        let total = store.assignedTotal(on: Self.day(2026, 9, 11))
        // 600 + 400 + 100 * 52/12 = 1433.33
        #expect(Money.cents(total) == Money.cents(1433.33))

        store.remove("Comida")
        store.remove("Hogar")
        store.remove("Transporte")
    }

    @Test("Un gasto reembolsable no cuenta en el reparto")
    func reembolsableFueraDelReparto() {
        let store = CategoryBudgetStore(defaults: UserDefaults(suiteName: "test-reembolsable")!)
        var budget = CategoryBudget(category: "Trabajo", amount: 500)
        budget.countsInGlobalBudget = false
        store.save(budget)

        #expect(Money.isZero(store.assignedTotal(on: Self.day(2026, 9, 11))))
        store.remove("Trabajo")
    }

    @Test("Fusionar suma los límites en lugar de perder uno")
    func fusion() {
        let store = CategoryBudgetStore(defaults: UserDefaults(suiteName: "test-fusion")!)
        store.save(CategoryBudget(category: "Comida", amount: 600))
        store.save(CategoryBudget(category: "Delivery", amount: 200))

        store.merge("Delivery", into: "Comida")

        #expect(Money.equals(store.budget(for: "Comida")?.amount ?? 0, 800))
        #expect(store.budget(for: "Delivery") == nil)
        store.remove("Comida")
    }
}
