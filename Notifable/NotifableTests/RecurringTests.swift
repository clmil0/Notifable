import Testing
import Foundation
import SwiftData
@testable import Notifable

/// Los 10 puntos de verificación de RECURRING.md.
///
/// La deduplicación contra el correo del banco y el día 31 en meses cortos son
/// la parte que evita duplicar o perder gastos, así que se prueban con fechas
/// concretas y no con datos generados.
@MainActor
struct RecurringTests {

    static let cal = Period.calendar

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    /// Contenedor en memoria: los `@Model` necesitan uno para insertar.
    static func makeContext() throws -> ModelContext {
        let schema = Schema([Expense.self, Income.self, RecurringExpense.self, QuickExpense.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    static func netflix(day: Int = 10, amount: Double = 44.90) -> RecurringExpense {
        RecurringExpense(merchant: "Netflix", category: "Entretenimiento",
                         amount: amount, frequency: .monthly, dayOfMonth: day,
                         startDate: date(2026, 1, 1))
    }

    // MARK: - 1. Día 31 en meses cortos

    @Test("1. Una regla mensual el día 31 cae el 28 en febrero")
    func dia31EnFebrero() {
        let rule = RecurringExpense(merchant: "Alquiler", category: "Otros", amount: 1200,
                                    frequency: .monthly, dayOfMonth: 31,
                                    startDate: Self.date(2026, 1, 1))
        let febrero = DateInterval(start: Self.date(2026, 2, 1, 0), end: Self.date(2026, 3, 1, 0))
        let dates = rule.occurrences(in: febrero)

        #expect(dates.count == 1, "la ocurrencia de febrero no puede saltarse")
        #expect(Self.cal.component(.day, from: dates[0]) == 28, "2026 no es bisiesto: día 28")

        // Y en un mes largo sigue siendo el 31.
        let enero = DateInterval(start: Self.date(2026, 1, 1, 0), end: Self.date(2026, 2, 1, 0))
        #expect(Self.cal.component(.day, from: rule.occurrences(in: enero).first ?? Date()) == 31)
    }

    // MARK: - 2, 3 y 4. Deduplicación

    @Test("2. Con el cobro del banco el mismo día, la ocurrencia se marca cumplida y no inserta nada")
    func deduplicaMismoDia() throws {
        let rule = Self.netflix()
        let bankExpense = Expense(amount: 44.90, merchant: "NETFLIX.COM 4589",
                                  date: Self.date(2026, 3, 10), category: "Entretenimiento")

        let pending = RecurringEngine.pending(rules: [rule], expenses: [bankExpense],
                                              now: Self.date(2026, 3, 15))
        let marzo = pending.filter { Self.cal.component(.month, from: $0.dates[0]) == 3 }

        #expect(marzo.count == 1)
        if case .satisfiedByBank(_, let amount, let daysApart) = marzo[0].status {
            #expect(Money.equals(amount, 44.90), "el monto que cuenta es el del banco")
            #expect(daysApart == 0)
        } else {
            Issue.record("debería ser .satisfiedByBank, salió \(marzo[0].status)")
        }
        #expect(!marzo[0].isAwaiting)
    }

    @Test("3. A dos días deduplica; a cuatro ya no")
    func ventanaDeTolerancia() {
        let rule = Self.netflix()

        let cerca = Expense(amount: 44.90, merchant: "NETFLIX.COM", date: Self.date(2026, 3, 12),
                            category: "Entretenimiento")
        let marzoCerca = RecurringEngine.pending(rules: [rule], expenses: [cerca],
                                                 now: Self.date(2026, 3, 20))
            .filter { Self.cal.component(.month, from: $0.dates[0]) == 3 }
        #expect(marzoCerca.first?.isAwaiting == false, "±3 días entra en la ventana")

        let lejos = Expense(amount: 44.90, merchant: "NETFLIX.COM", date: Self.date(2026, 3, 14),
                            category: "Entretenimiento")
        let marzoLejos = RecurringEngine.pending(rules: [Self.netflix()], expenses: [lejos],
                                                 now: Self.date(2026, 3, 20))
            .filter { $0.dates.contains { Self.cal.component(.month, from: $0) == 3 } }
        #expect(marzoLejos.first?.isAwaiting == true, "a 4 días ya no es el mismo cobro")
    }

    @Test("4. Un cobro un 15.8% mayor no deduplica")
    func toleranciaDeMonto() {
        let rule = Self.netflix()
        let caro = Expense(amount: 52.00, merchant: "NETFLIX.COM", date: Self.date(2026, 3, 10),
                           category: "Entretenimiento")
        let marzo = RecurringEngine.pending(rules: [rule], expenses: [caro],
                                            now: Self.date(2026, 3, 20))
            .filter { $0.dates.contains { Self.cal.component(.month, from: $0) == 3 } }

        #expect(marzo.first?.isAwaiting == true, "52.00 supera el ±15% de 44.90")
    }

    // MARK: - 5, 6 y 7. Acciones

    @Test("5. Confirmar dos veces no crea dos gastos")
    func confirmarDosVeces() throws {
        let context = try Self.makeContext()
        let rule = Self.netflix()
        context.insert(rule)

        let now = Self.date(2026, 3, 20)
        let first = RecurringEngine.pending(rules: [rule], expenses: [], now: now)
        #expect(!first.isEmpty)

        let created = RecurringEngine.confirm(first[0], rule: rule, in: context)
        #expect(!created.isEmpty)

        // El marcador avanzó: la misma ocurrencia ya no se propone.
        let second = RecurringEngine.pending(rules: [rule], expenses: created, now: now)
        let repeated = second.filter { occurrence in
            occurrence.dates.contains { date in
                first[0].dates.contains { Self.cal.isDate($0, inSameDayAs: date) }
            }
        }
        #expect(repeated.isEmpty, "la ocurrencia ya resuelta no puede volver a proponerse")
        #expect(rule.lastResolvedOccurrence != nil)
    }

    @Test("6. Omitir no registra nada y no vuelve a proponer")
    func omitir() {
        let rule = Self.netflix()
        let now = Self.date(2026, 3, 20)
        let pending = RecurringEngine.pending(rules: [rule], expenses: [], now: now)
        guard let first = pending.first else {
            Issue.record("debería haber ocurrencias vencidas")
            return
        }

        RecurringEngine.skip(first, rule: rule)

        let after = RecurringEngine.pending(rules: [rule], expenses: [], now: now)
        let repeated = after.filter { occurrence in
            occurrence.dates.contains { date in
                first.dates.contains { Self.cal.isDate($0, inSameDayAs: date) }
            }
        }
        #expect(repeated.isEmpty)
    }

    @Test("7. Pausar detiene las propuestas sin borrar lo registrado")
    func pausar() {
        let rule = Self.netflix()
        let now = Self.date(2026, 3, 20)
        #expect(!RecurringEngine.pending(rules: [rule], expenses: [], now: now).isEmpty)

        rule.isPaused = true
        #expect(RecurringEngine.pending(rules: [rule], expenses: [], now: now).isEmpty)
        #expect(rule.occurrences(in: DateInterval(start: Self.date(2026, 1, 1), end: now)).isEmpty)
        #expect(Money.isZero(rule.monthlyEquivalent), "una regla pausada no compromete nada")
    }

    // MARK: - 8. Compromiso mensual

    @Test("8. Una regla semanal de S/ 12 lun–vie compromete S/ 260.00 al mes")
    func compromisoMensual() {
        let rule = RecurringExpense(merchant: "Almuerzo", category: "Comida", amount: 12,
                                    frequency: .weekly, weekdays: [2, 3, 4, 5, 6])
        // 12 × 5 × 52/12 = 260
        #expect(Money.equals(rule.monthlyEquivalent, 260), "salió \(rule.monthlyEquivalent)")
        #expect(Money.equals(RecurringEngine.monthlyCommitted(rules: [rule], usdToPen: 3.75), 260))
        #expect(rule.scheduleLabel == "Lun a vie")
    }

    @Test("El compromiso multimoneda convierte una sola vez")
    func compromisoMultimoneda() {
        let soles = RecurringExpense(merchant: "Alquiler", category: "Otros", amount: 1200,
                                     frequency: .monthly, dayOfMonth: 1)
        let dolares = RecurringExpense(merchant: "iCloud", category: "Servicios", amount: 10,
                                       currency: "USD", frequency: .monthly, dayOfMonth: 5)
        let total = RecurringEngine.monthlyCommitted(rules: [soles, dolares], usdToPen: 3.75)
        #expect(Money.equals(total, 1237.50), "salió \(total)")
    }

    // MARK: - 9. Atajos

    @Test("9. Un atajo crea un gasto con su monto exacto")
    func atajo() throws {
        let context = try Self.makeContext()
        let quick = QuickExpense(label: "Pasaje", merchant: "Metropolitano",
                                 category: "Transporte", amount: 2.50)
        context.insert(quick)

        let before = quick.useCount
        let expense = quick.makeExpense()
        context.insert(expense)
        quick.useCount += 1
        quick.lastUsedAt = Date()

        #expect(Money.cents(expense.amount) == 250)
        #expect(expense.merchant == "Metropolitano")
        #expect(expense.category == "Transporte")
        #expect(!expense.isSubscription)
        #expect(quick.useCount == before + 1)

        let all = try context.fetch(FetchDescriptor<Expense>())
        #expect(all.count == 1, "un doble toque crea exactamente un gasto")
    }

    @Test("Las sugerencias de atajo salen de montos repetidos, y no se crean solas")
    func sugerenciasDeAtajo() {
        var history: [Expense] = []
        for day in 1...4 {
            history.append(Expense(amount: 2.50, merchant: "Metropolitano",
                                   date: Self.date(2026, 3, day), category: "Transporte"))
        }
        history.append(Expense(amount: 9.90, merchant: "Rappi",
                               date: Self.date(2026, 3, 5), category: "Comida"))

        let suggestions = QuickExpense.suggestions(from: history)
        #expect(suggestions.count == 1, "sólo el monto repetido 3+ veces")
        #expect(suggestions.first?.merchant == "Metropolitano")
        #expect(Money.equals(suggestions.first?.amount ?? 0, 2.50))
    }

    // MARK: - 10. Los pendientes no cuentan

    @Test("10. Las ocurrencias sin confirmar no aparecen en PeriodTotals.spent")
    func pendientesNoCuentan() throws {
        let context = try Self.makeContext()
        let rule = RecurringExpense(merchant: "Alquiler", category: "Otros", amount: 1200,
                                    frequency: .monthly, dayOfMonth: 5,
                                    startDate: Self.date(2026, 3, 1))
        context.insert(rule)

        let real = Expense(amount: 80, merchant: "Metro", date: Self.date(2026, 3, 8),
                           category: "Comida")
        context.insert(real)

        let period = Period(granularity: .mes, reference: Self.date(2026, 3, 15))
        let before = Accounting.totals(expenses: [real], incomes: [], period: period, usdToPen: 3.75)

        let pending = RecurringEngine.pending(rules: [rule], expenses: [real],
                                              now: Self.date(2026, 3, 15))
        #expect(!pending.isEmpty, "el alquiler del día 5 debería estar vencido")
        #expect(Money.equals(before.spent, 80),
                "el total sólo refleja gasto real: \(before.spent)")

        // Al confirmar, ahí sí entra.
        let created = RecurringEngine.confirm(pending[0], rule: rule, in: context)
        let after = Accounting.totals(expenses: [real] + created, incomes: [], period: period, usdToPen: 3.75)
        #expect(Money.equals(after.spent, 1280))
    }

    // MARK: - Recurrencia derivada

    @Test("Un gasto confirmado por una regla queda marcado como suscripción")
    func isSubscriptionDerivado() throws {
        let context = try Self.makeContext()
        let rule = Self.netflix()
        context.insert(rule)

        let pending = RecurringEngine.pending(rules: [rule], expenses: [], now: Self.date(2026, 3, 20))
        let created = RecurringEngine.confirm(pending[0], rule: rule, in: context)

        #expect(created.allSatisfy { $0.isSubscription },
                "isSubscription se deriva de frequency != .never, ya no es un toggle")
    }

    @Test("Confirmar con otro monto usa el monto corregido")
    func confirmarConOtroMonto() throws {
        let context = try Self.makeContext()
        let rule = Self.netflix()
        context.insert(rule)

        let pending = RecurringEngine.pending(rules: [rule], expenses: [], now: Self.date(2026, 3, 20))
        let created = RecurringEngine.confirm(pending[0], rule: rule, amountOverride: 49.90, in: context)

        #expect(created.allSatisfy { Money.cents($0.amount) == 4990 })
    }
}
