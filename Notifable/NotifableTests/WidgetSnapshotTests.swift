import Testing
import Foundation
@testable import Notifable

/// El resumen de los widgets. Lo que importa es que el widget no pueda
/// contradecir a la app: las mismas cifras que `Accounting`, y que siga
/// cuadrando a medianoche y al cambiar de mes sin que la app se abra.
struct WidgetSnapshotTests {

    static let cal = Period.calendar

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    static func inputs(expenses: [ExpenseSnapshot] = [],
                       incomes: [IncomeSnapshot] = [],
                       monthlyBudget: Double = 0,
                       budgetEnabled: Bool = true,
                       tracksIncome: Bool = true,
                       budgets: [CategoryBudget] = []) -> WidgetSnapshotBuilder.Inputs {
        WidgetSnapshotBuilder.Inputs(
            expenses: expenses, incomes: incomes, usdToPen: 3.75,
            monthlyBudget: monthlyBudget, budgetEnabled: budgetEnabled,
            tracksIncome: tracksIncome, hideAmounts: false,
            categoryBudgets: budgets, quickActions: [],
            pendingRecurringCount: 0, nextRecurring: nil,
            categoryNames: [],
            theme: .init(accentHex: "2E5BFF", accentDarkHex: "2E5BFF", incomeHex: "248A3D"),
            style: { _ in .init(symbol: "bag.fill", colorHex: "808080") }
        )
    }

    // MARK: - Armado

    @Test("El resumen usa las mismas cifras que Accounting")
    func mismasCifras() {
        let now = Self.date(2026, 9, 14)
        let expenses = [
            ExpenseSnapshot(amount: 100, date: Self.date(2026, 9, 1), category: "Comida", merchant: "A"),
            ExpenseSnapshot(amount: 20, currency: "USD", date: Self.date(2026, 9, 10), category: "Ocio",
                            merchant: "B", fxRateAtCapture: 3.5),
            ExpenseSnapshot(amount: 50, date: Self.date(2026, 8, 3), category: "Comida", merchant: "A"),
            ExpenseSnapshot(amount: 999, date: Self.date(2026, 7, 3), category: "Comida", merchant: "A")
        ]
        let incomes = [IncomeSnapshot(amount: 3000, date: Self.date(2026, 9, 1)),
                       IncomeSnapshot(amount: 40, date: Self.date(2026, 9, 2), isDebtPayment: true)]

        let snapshot = WidgetSnapshotBuilder.build(Self.inputs(expenses: expenses, incomes: incomes), now: now)
        let totals = Accounting.totals(expenses: expenses, incomes: incomes,
                                       period: Period(granularity: .mes, reference: now), usdToPen: 3.75)

        #expect(snapshot.month.spentCents == Money.cents(totals.spent))
        #expect(snapshot.month.spentCents == 100_00 + 70_00)
        #expect(snapshot.month.dailySpentCents.reduce(0, +) == snapshot.month.spentCents)
        #expect(snapshot.month.dailySpentCents.count == 30)
        #expect(snapshot.month.previousDailySpentCents.count == 31)
        #expect(snapshot.month.previousDailySpentCents.reduce(0, +) == 50_00)
        // El abono a deuda no es ingreso.
        #expect(snapshot.month.incomeCents == 3000_00)
        #expect(snapshot.topCategories.map(\.name) == ["Comida", "Ocio"])
        #expect(snapshot.otherCents == 0)
    }

    @Test("Sin ingresos ni presupuesto, el resumen no inventa cifras")
    func sinIngresosNiPresupuesto() {
        let now = Self.date(2026, 9, 14)
        let off = WidgetSnapshotBuilder.build(Self.inputs(monthlyBudget: 2000, budgetEnabled: false,
                                                          tracksIncome: false), now: now)
        #expect(off.budget == nil)
        #expect(off.month.incomeCents == nil)

        let on = WidgetSnapshotBuilder.build(Self.inputs(monthlyBudget: 2000), now: now)
        #expect(on.budget?.targetCents == 2000_00)
    }

    @Test("Las categorías fuera del top suman en 'otros'")
    func otros() {
        let now = Self.date(2026, 9, 14)
        let expenses = ["A", "B", "C", "D", "E", "F"].enumerated().map { i, name in
            ExpenseSnapshot(amount: Double(10 * (i + 1)), date: Self.date(2026, 9, 2), category: name, merchant: name)
        }
        let snapshot = WidgetSnapshotBuilder.build(Self.inputs(expenses: expenses), now: now)
        #expect(snapshot.topCategories.count == WidgetSnapshotBuilder.maxCategories)
        #expect(snapshot.topCategories.first?.name == "F")
        #expect(snapshot.otherCents == 10_00 + 20_00)
        #expect(snapshot.topCategories.reduce(0) { $0 + $1.totalCents } + snapshot.otherCents == snapshot.month.spentCents)
    }

    @Test("Los límites pasados van primero y cuadran con CategoryLimits")
    func limites() {
        let now = Self.date(2026, 9, 14)
        let expenses = [
            ExpenseSnapshot(amount: 500, date: Self.date(2026, 9, 3), category: "Comida", merchant: "A"),
            ExpenseSnapshot(amount: 90, date: Self.date(2026, 9, 3), category: "Ocio", merchant: "B"),
            ExpenseSnapshot(amount: 10, date: Self.date(2026, 9, 3), category: "Hogar", merchant: "C")
        ]
        let budgets = [CategoryBudget(category: "Comida", amount: 400),
                       CategoryBudget(category: "Ocio", amount: 100),
                       CategoryBudget(category: "Hogar", amount: 100),
                       CategoryBudget(category: "Vacía", amount: 0)]
        let limits = WidgetSnapshotBuilder.build(Self.inputs(expenses: expenses, budgets: budgets), now: now).limits

        #expect(limits.map(\.category) == ["Comida", "Ocio", "Hogar"])
        #expect(limits[0].isOver)
        #expect(limits[1].isNear)
        #expect(limits[0].cycleEnd == Self.cal.dateInterval(of: .month, for: now)!.end)
        #expect(limits[1].daysLeft(at: now) == 17)
    }

    @Test("Deudas: suma todo lo pendiente, de cualquier mes")
    func deudas() {
        let now = Self.date(2026, 9, 14)
        let expenses = [
            ExpenseSnapshot(amount: 100, date: Self.date(2026, 5, 1), isDebt: true, paymentsInOwnCurrency: 30),
            ExpenseSnapshot(amount: 10, currency: "USD", date: Self.date(2026, 9, 1), isDebt: true, fxRateAtCapture: 3.5),
            ExpenseSnapshot(amount: 50, date: Self.date(2026, 9, 1), isDebt: true, paymentsInOwnCurrency: 50)
        ]
        let attention = WidgetSnapshotBuilder.build(Self.inputs(expenses: expenses), now: now).attention
        #expect(attention.debtOutstandingCents == 70_00 + 35_00)
        #expect(attention.debtCount == 2)
    }

    // MARK: - Derivados por fecha

    static func septemberSnapshot() -> WidgetSnapshot {
        var daily = Array(repeating: 0, count: 30)
        daily[0] = 300_00      // 1 sept
        daily[13] = 100_00     // 14 sept
        daily[14] = 50_00      // 15 sept
        var previous = Array(repeating: 0, count: 31)
        previous[0] = 200_00
        previous[20] = 900_00
        var snapshot = WidgetSnapshot.sample(now: date(2026, 9, 14))
        let month = cal.dateInterval(of: .month, for: date(2026, 9, 14))!
        snapshot.month = .init(start: month.start, end: month.end, spentCents: 450_00, incomeCents: nil,
                               dailySpentCents: daily, previousDailySpentCents: previous,
                               expenseCount: 3, hasMixedCurrencies: false)
        snapshot.budget = .init(targetCents: 3000_00)
        return snapshot
    }

    @Test("Ritmo, disponible por día y comparación al mismo día")
    func derivadosDelDia() {
        let d = WidgetDerived(Self.septemberSnapshot(), at: Self.date(2026, 9, 14, 20))
        #expect(d.isCurrentMonth)
        #expect(d.elapsedDays == 14)
        #expect(d.todayCents == 100_00)
        #expect(d.spentCents == 450_00)
        #expect(d.remainingCents == 2550_00)
        // 2550 / 16 días restantes
        #expect(d.availablePerDayCents == 15_938)
        #expect(d.status == .ok)
        // Mes pasado hasta el 14: sólo los 200 del día 1.
        #expect(d.previousToDateCents == 200_00)
        #expect(abs((d.changeVsPrevious ?? 0) - 1.25) < 0.0001)
        #expect(d.cumulativeCents.count == 14)
        #expect(d.cumulativeCents.last == 400_00)
    }

    @Test("A medianoche el widget pasa al día siguiente sin la app")
    func medianoche() {
        let snapshot = Self.septemberSnapshot()
        let midnight = Self.cal.startOfDay(for: Self.date(2026, 9, 15))
        let d = WidgetDerived(snapshot, at: midnight)
        #expect(d.elapsedDays == 15)
        #expect(d.todayCents == 50_00)
    }

    @Test("Al cambiar de mes sin abrir la app, todo vuelve a cero")
    func mesNuevo() {
        let d = WidgetDerived(Self.septemberSnapshot(), at: Self.date(2026, 10, 1, 8))
        #expect(!d.isCurrentMonth)
        #expect(d.spentCents == 0)
        #expect(d.todayCents == 0)
        #expect(d.status == .ok)
        #expect(d.changeVsPrevious == nil)
    }

    @Test("Estado del ritmo: encima del esperado y pasado del presupuesto")
    func estados() {
        var snapshot = Self.septemberSnapshot()
        snapshot.budget = .init(targetCents: 600_00)
        // Día 14 de 30: lo esperado es 280; lleva 450.
        #expect(WidgetDerived(snapshot, at: Self.date(2026, 9, 14)).status == .warning)
        snapshot.budget = .init(targetCents: 400_00)
        let over = WidgetDerived(snapshot, at: Self.date(2026, 9, 14))
        #expect(over.status == .over)
        #expect(over.remainingCents == 0)
        // El último día no queda "por día".
        #expect(WidgetDerived(snapshot, at: Self.date(2026, 9, 30)).availablePerDayCents == nil)
    }

    // MARK: - Archivo y enlaces

    @Test("El archivo sólo se reescribe si cambió")
    func archivo() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let snapshot = WidgetSnapshot.sample(now: Self.date(2026, 9, 14))
        #expect(try WidgetSnapshotStore.save(snapshot, to: url))
        let rewritten = try WidgetSnapshotStore.save(snapshot, to: url)
        #expect(!rewritten)
        #expect(WidgetSnapshotStore.load(from: url) == snapshot)

        var old = snapshot
        old.schemaVersion = 0
        try WidgetSnapshotStore.save(old, to: url)
        #expect(WidgetSnapshotStore.load(from: url) == nil)
    }

    @Test("Los enlaces de los widgets van y vuelven")
    func enlaces() {
        let id = UUID()
        let links: [AppDeepLink] = [.add(isIncome: true, source: "Yape"), .add(isIncome: false, source: nil),
                                    .quick(id), .summary, .categories, .pending, .rhythm,
                                    .friendInvite(code: "ABCDEFGHJKMNPQRSTVWX")]
        for link in links {
            #expect(AppDeepLink(url: link.url) == link, "\(link.url)")
        }
        #expect(AppDeepLink(url: URL(string: "https://agrupay.app/add")!) == nil)
        #expect(AppDeepLink(url: URL(string: "agrupay://quick?id=nope")!) == nil)
        // Invitaciones: 20 caracteres Crockford base32, con o sin guiones.
        #expect(AppDeepLink(url: URL(string: "agrupay://amigo?codigo=abcd-efgh-jkmn-pqrs-tvwx")!) == .friendInvite(code: "ABCDEFGHJKMNPQRSTVWX"))
        #expect(AppDeepLink(url: URL(string: "agrupay://amigo?codigo=a1b2c3d4")!) == nil)
        // Sólo el dominio configurado cuenta como invitación.
        #expect(AppDeepLink(url: URL(string: "https://ejemplo.com/amigo/ABCDEFGHJKMNPQRSTVWX")!) == nil)
        if let host = InviteLinks.webHosts.first {
            #expect(AppDeepLink(url: URL(string: "https://\(host)/amigo/ABCDEFGHJKMNPQRSTVWX")!) == .friendInvite(code: "ABCDEFGHJKMNPQRSTVWX"))
            #expect(AppDeepLink(url: URL(string: "https://\(host)/otra/ABCDEFGHJKMNPQRSTVWX")!) == nil)
        }
        #expect(!InviteLinks.shareText(token: "ABCDEFGHJKMNPQRSTVWX", linkReady: false).contains("https"))
    }
}
