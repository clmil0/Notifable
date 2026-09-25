import Foundation
import SwiftData
import Testing
@testable import Notifable

/// Dividir un gasto (`2a`–`2d`): el pago deja de sumar, cuentan sus partes, y
/// la relación sobrevive a releer el correo.
@MainActor
struct ExpenseSplitTests {

    static func makeContext() throws -> ModelContext {
        let schema = Schema([Expense.self, Income.self, RecurringExpense.self, QuickExpense.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    static func yape(emailID: String? = "m1") -> Expense {
        let e = Expense(amount: 150, merchant: "YAPE - Juan Pérez", date: Date(),
                        category: Accounting.unclassified, emailID: emailID)
        e.sourceBank = "Yape"
        return e
    }

    static let parts = [
        SplitPart(amount: 100, category: "Supermercado", tags: []),
        SplitPart(amount: 50, category: "Comida", tags: [])
    ]

    static func all(_ context: ModelContext) throws -> [Expense] {
        try context.fetch(FetchDescriptor<Expense>())
    }

    @Test func elPagoDejaDeSumarYCuentanLasPartes() throws {
        let context = try Self.makeContext()
        let parent = Self.yape()
        context.insert(parent)

        #expect(ExpenseSplit.apply(Self.parts, to: parent, in: context))

        let snapshots = try Self.all(context).map(\.accountingSnapshot)
        let totals = Accounting.totals(expenses: snapshots, incomes: [], period: Period(), usdToPen: 3.7)
        #expect(Money.equals(totals.spent, 150))
        #expect(parent.isSplit)
        #expect(!parent.countsAsSpending)

        let children = ExpenseSplit.parts(of: parent, in: context)
        #expect(children.map(\.category) == ["Supermercado", "Comida"])
        #expect(children.allSatisfy { $0.emailID == nil && $0.sourceBank == "Yape" })
        #expect(ExpenseSplit.parent(of: children[0], in: context)?.id == parent.id)
    }

    @Test func noDivideSiNoCuadra() throws {
        let context = try Self.makeContext()
        let parent = Self.yape()
        context.insert(parent)

        let short = [SplitPart(amount: 100, category: "Comida", tags: []),
                     SplitPart(amount: 49.99, category: "Otros", tags: [])]
        #expect(!ExpenseSplit.apply(short, to: parent, in: context))
        #expect(!parent.isSplit)
        #expect(try Self.all(context).count == 1)
    }

    @Test func rehacerReutilizaLasPartes() throws {
        let context = try Self.makeContext()
        let parent = Self.yape()
        context.insert(parent)
        ExpenseSplit.apply(Self.parts, to: parent, in: context)
        let firstID = ExpenseSplit.parts(of: parent, in: context)[0].id

        let three = [SplitPart(amount: 50, category: "Supermercado", tags: []),
                     SplitPart(amount: 50, category: "Comida", tags: []),
                     SplitPart(amount: 50, category: "Otros", tags: [])]
        #expect(ExpenseSplit.apply(three, to: parent, in: context))
        let now = ExpenseSplit.parts(of: parent, in: context)
        #expect(now.count == 3)
        #expect(now[0].id == firstID)

        #expect(ExpenseSplit.apply(Self.parts, to: parent, in: context))
        #expect(ExpenseSplit.parts(of: parent, in: context).count == 2)
    }

    @Test func releerElCorreoRecuperaLaDivision() throws {
        let context = try Self.makeContext()
        let parent = Self.yape()
        context.insert(parent)
        ExpenseSplit.apply(Self.parts, to: parent, in: context)

        // «Volver a leer el correo desde cero»: el pago se rearma sin marca.
        context.delete(parent)
        let reread = Self.yape()
        context.insert(reread)
        try context.save()
        #expect(!reread.isSplit)

        ExpenseSplit.reconcile(in: context)
        #expect(reread.isSplit)
        #expect(ExpenseSplit.parts(of: reread, in: context).count == 2)
    }

    @Test func deshacerDevuelveElPagoEntero() throws {
        let context = try Self.makeContext()
        let parent = Self.yape()
        context.insert(parent)
        ExpenseSplit.apply(Self.parts, to: parent, in: context)

        ExpenseSplit.undo(parent, in: context)
        #expect(!parent.isSplit)
        #expect(try Self.all(context).count == 1)
    }

    @Test func unPagoAnotadoAManoSigueEncontrandoSusPartesTrasEditarlo() throws {
        let context = try Self.makeContext()
        let parent = Self.yape(emailID: nil)
        context.insert(parent)
        ExpenseSplit.apply(Self.parts, to: parent, in: context)

        let old = TransactionKey.key(for: parent)
        parent.merchant = "YAPE - Juan P."
        ExpenseSplit.rekey(from: old, to: TransactionKey.key(for: parent), in: context)

        ExpenseSplit.reconcile(in: context)
        #expect(parent.isSplit)
        #expect(ExpenseSplit.parts(of: parent, in: context).count == 2)
    }

    @Test func noSeDivideUnaDeudaNiUnaParte() throws {
        let context = try Self.makeContext()
        let parent = Self.yape()
        context.insert(parent)
        #expect(ExpenseSplit.canSplit(parent))

        ExpenseSplit.apply(Self.parts, to: parent, in: context)
        let child = ExpenseSplit.parts(of: parent, in: context)[0]
        #expect(!ExpenseSplit.canSplit(child))
        #expect(ExpenseSplit.canSplit(parent))

        let debt = Self.yape(emailID: "m2")
        debt.isDebt = true
        #expect(!ExpenseSplit.canSplit(debt))
    }
}
