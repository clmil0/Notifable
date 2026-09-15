import Foundation
import SwiftData
import Testing
@testable import Notifable

/// El cargo de BBVA "APPLE.COM/BILL" unido al recibo de Apple se duplicaba al
/// volver a leer por rango, y al rearmar en otro orden perdía su deuda.
@MainActor
struct LinkedEmailDuplicateTests {

    static func makeContext() throws -> ModelContext {
        let schema = Schema([Expense.self, Income.self, RecurringExpense.self, QuickExpense.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    static func defaults() -> UserDefaults {
        let name = "test-linked-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    /// Cargo del banco (`bank`) con el recibo de Apple (`receipt`) unido.
    static func linked(emailID: String, relatedEmailID: String) -> Expense {
        let e = Expense(amount: 32.9, merchant: "Apple: Claude Pro", date: Date(), category: "Servicios", emailID: emailID)
        e.relatedEmailID = relatedEmailID
        return e
    }

    @Test func lasDosLlavesEncuentranElGasto() {
        let e = Self.linked(emailID: "bank", relatedEmailID: "receipt")
        #expect(TransactionKey.lookupKeys(for: e) == ["mail:bank", "mail:receipt"])
        let byKey = TransactionKey.expensesByLookupKey([e])
        #expect(byKey["mail:bank"]?.id == e.id)
        #expect(byKey["mail:receipt"]?.id == e.id)
    }

    @Test func laDeudaSobreviveAQueLleguePrimeroElRecibo() throws {
        let context = try Self.makeContext()
        let defaults = Self.defaults()

        // Primera lectura: el banco llegó primero y ahí se marcó la deuda.
        let first = Self.linked(emailID: "bank", relatedEmailID: "receipt")
        ExpenseEditStore.record(first, isDebt: true, defaults: defaults)

        // Relectura desde cero con el orden invertido.
        let rebuilt = Self.linked(emailID: "receipt", relatedEmailID: "bank")
        context.insert(rebuilt)
        try context.save()

        ExpenseEditStore.apply(in: context, defaults: defaults)
        #expect(rebuilt.isDebt)
    }

    @Test func losCobrosVuelvenAlGastoConElOrdenInvertido() throws {
        let context = try Self.makeContext()
        let defaults = Self.defaults()
        let rebuilt = Self.linked(emailID: "receipt", relatedEmailID: "bank")
        let payment = Income(amount: 10, source: "Jorge")
        context.insert(rebuilt)
        context.insert(payment)
        try context.save()

        IncomeLinkStore.save(IncomeLink(incomeID: payment.id, markKey: "mail:bank", isFinal: false), defaults: defaults)
        IncomeLinkStore.apply(in: context, defaults: defaults)
        #expect(payment.debtReference?.id == rebuilt.id)
    }

    @Test func seBorraElDuplicadoSinDecisiones() throws {
        let context = try Self.makeContext()
        let original = Self.linked(emailID: "bank", relatedEmailID: "receipt")
        original.isDebt = true
        let duplicate = Expense(amount: 32.9, merchant: "Apple: Claude Pro", emailID: "receipt")
        let unrelated = Expense(amount: 32.9, merchant: "Apple: iCloud", emailID: "otro")
        [original, duplicate, unrelated].forEach(context.insert)
        try context.save()

        #expect(GmailSyncService.removeLinkedDuplicates(in: context) == 1)
        let left = try context.fetch(FetchDescriptor<Expense>()).map(\.emailID)
        #expect(Set(left) == ["bank", "otro"])
    }

    @Test func noSeBorraUnDuplicadoConDeuda() throws {
        let context = try Self.makeContext()
        let original = Self.linked(emailID: "bank", relatedEmailID: "receipt")
        let duplicate = Expense(amount: 32.9, merchant: "Apple: Claude Pro", emailID: "receipt", isDebt: true)
        [original, duplicate].forEach(context.insert)
        try context.save()

        #expect(GmailSyncService.removeLinkedDuplicates(in: context) == 0)
        #expect(try context.fetch(FetchDescriptor<Expense>()).count == 2)
    }
}
