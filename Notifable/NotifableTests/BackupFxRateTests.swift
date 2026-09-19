import Foundation
import SwiftData
import Testing
@testable import Notifable

/// El tipo de cambio de los gastos en dólares del correo tiene que sobrevivir
/// a reinstalar: al releer el correo el gasto nace con el tipo de hoy, y el
/// respaldado tiene que ganarle.
@MainActor
struct BackupFxRateTests {

    static func makeContext() throws -> ModelContext {
        let schema = Schema([Expense.self, Income.self, RecurringExpense.self, QuickExpense.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    static func defaults() -> UserDefaults {
        let name = "test-fx-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func mergeKeepsTheFirstRate() {
        let original = ExpenseEdit(markKey: "mail:1", fxRate: 3.7512)
        let reread = ExpenseEdit(markKey: "mail:1", category: "Viajes", fxRate: 3.41)
        let merged = original.merged(with: reread)
        #expect(merged.fxRate == 3.7512)
        #expect(merged.category == "Viajes")
    }

    @Test func rateSurvivesTheJSONRoundTrip() throws {
        let edit = ExpenseEdit(markKey: "mail:1", fxRate: 3.751234)
        let data = try ConfigBackupManager.makeEncoder().encode(edit)
        let back = try ConfigBackupManager.makeDecoder().decode(ExpenseEdit.self, from: data)
        #expect(back.fxRate == 3.751234)
        #expect(!back.isUserEdit)
        #expect(!back.isEmpty)
    }

    @Test func restoredRateWinsOverTheReread() throws {
        let context = try Self.makeContext()
        let d = Self.defaults()

        // Llega del respaldo antes de releer el correo.
        ExpenseEditStore.merge([ExpenseEdit(markKey: "mail:usd-1", fxRate: 3.75)], defaults: d)

        // La relectura lo crea con el tipo de cambio de hoy.
        let expense = Expense(amount: 20, merchant: "Netflix", date: Date(), currency: "USD",
                              emailID: "usd-1", fxRateAtCapture: 3.41)
        context.insert(expense)
        try context.save()

        ExpenseEditStore.captureFxRates(in: context, defaults: d)
        ExpenseEditStore.apply(in: context, defaults: d)

        #expect(expense.fxRateAtCapture == 3.75)
    }

    @Test func captureRecordsOnlyOnce() throws {
        let context = try Self.makeContext()
        let d = Self.defaults()
        let expense = Expense(amount: 10, merchant: "Spotify", date: Date(), currency: "USD",
                              emailID: "usd-2", fxRateAtCapture: 3.8)
        context.insert(expense)
        try context.save()

        ExpenseEditStore.captureFxRates(in: context, defaults: d)
        expense.fxRateAtCapture = 3.2
        ExpenseEditStore.captureFxRates(in: context, defaults: d)

        #expect(ExpenseEditStore.all(d)["mail:usd-2"]?.fxRate == 3.8)
    }
}
