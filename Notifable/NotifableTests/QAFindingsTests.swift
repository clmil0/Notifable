import Foundation
import SwiftData
import Testing
@testable import Notifable

/// Los fallos que encontró la ronda de QA con datos falsos (QA-001 a QA-005).
/// Cada test reproduce el caso tal como se vio en el simulador.
@MainActor
struct QAFindingsTests {

    // MARK: - QA-001 · Montos con separador de miles

    @Test("Money.parse: coma de miles, coma decimal y los dos separadores")
    func montosConMiles() {
        #expect(Money.parse("1,250.00") == 1250)
        #expect(Money.parse("1,250") == 1250)
        #expect(Money.parse("1,250,000") == 1_250_000)
        #expect(Money.parse("1.250,00") == 1250)
        #expect(Money.parse("45,50") == 45.5)
        #expect(Money.parse("25.50") == 25.5)
    }

    static func yapeBody(_ amount: String) -> String {
        "¡Yapeaste! Monto de yapeo S/ \(amount) Nombre del Beneficiario Inmobiliaria Sol "
            + "N° de operación 01234567 Fecha y Hora de la operación 13 septiembre 2026 - 01:00 pm "
            + "Celular del Beneficiario *** *** 209"
    }

    @Test("Un yapeo de S/ 1,250.00 se lee como 1,250 y no como cero")
    func yapeoConMiles() throws {
        let expense = try #require(YapeParser().parse(cleanText: Self.yapeBody("1,250.00")))
        #expect(Money.cents(expense.amount) == 125_000)
    }

    @Test("Un correo reconocido cuyo monto no se puede leer no crea un gasto en cero")
    func montoIlegibleNoSeGuarda() {
        let parsed = GmailSyncService.shared.parseEmailBody(Self.yapeBody("1..2"), receivedAt: Date())
        #expect(parsed == nil)
    }

    // MARK: - QA-002 · «No» a recuperar no resucita lo borrado

    static func freshDefaults() -> UserDefaults {
        let name = "qa-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Rechazar la recuperación deja los correos en la lista de borrados")
    func rechazarNoBorraLaLista() {
        let defaults = Self.freshDefaults()
        defaults.set(["m1", "m2"], forKey: DeletedEmails.key)

        DeletedEmails.decline(defaults)

        // La lectura sigue saltándoselos…
        #expect(DeletedEmails.all(defaults) == ["m1", "m2"])
        // …y no se vuelve a preguntar por ellos.
        #expect(DeletedEmails.undecided(defaults).isEmpty)
    }

    @Test("Un borrado nuevo después de rechazar sí vuelve a preguntar")
    func borradoNuevoPregunta() {
        let defaults = Self.freshDefaults()
        defaults.set(["m1"], forKey: DeletedEmails.key)
        DeletedEmails.decline(defaults)
        defaults.set(["m1", "m3"], forKey: DeletedEmails.key)

        #expect(DeletedEmails.undecided(defaults) == ["m3"])
    }

    // MARK: - QA-003 · La base sale del App Group

    static func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qa-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("La base y su registro se mudan enteros y el App Group queda vacío")
    func mudanzaCompleta() throws {
        let fm = FileManager.default
        let group = try Self.tempDir(), app = try Self.tempDir()
        for suffix in AppModelContainer.storeSuffixes {
            try Data("x\(suffix)".utf8).write(to: group.appendingPathComponent("default.store" + suffix))
        }
        let legacy = group.appendingPathComponent("default.store")
        let target = app.appendingPathComponent("default.store")

        #expect(AppModelContainer.moveOutOfAppGroupIfNeeded(from: legacy, to: target))
        for suffix in AppModelContainer.storeSuffixes {
            #expect(fm.fileExists(atPath: target.path + suffix))
            #expect(!fm.fileExists(atPath: legacy.path + suffix))
        }
        let wal = try String(contentsOf: app.appendingPathComponent("default.store-wal"), encoding: .utf8)
        #expect(wal == "x-wal")
    }

    @Test("Si ya hay base privada no se pisa con la del App Group")
    func noPisaLaPrivada() throws {
        let group = try Self.tempDir(), app = try Self.tempDir()
        let legacy = group.appendingPathComponent("default.store")
        let target = app.appendingPathComponent("default.store")
        try Data("vieja".utf8).write(to: legacy)
        try Data("nueva".utf8).write(to: target)

        #expect(AppModelContainer.moveOutOfAppGroupIfNeeded(from: legacy, to: target))
        #expect(try String(contentsOf: target, encoding: .utf8) == "nueva")
    }

    // MARK: - Pendientes · «Los anteriores»

    static func makeContext() throws -> ModelContext {
        let schema = Schema([Expense.self, Income.self, RecurringExpense.self, QuickExpense.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    @Test("«Los anteriores» son los pendientes más antiguos del mismo comercio, nada más")
    func losAnteriores() throws {
        let context = try Self.makeContext()
        func add(_ merchant: String, daysAgo: Double, _ category: String = Accounting.unclassified) -> Expense {
            let e = Expense(amount: 10, merchant: merchant, date: Date(timeIntervalSinceNow: -daysAgo * 86_400),
                            category: category)
            context.insert(e)
            return e
        }
        let chosen = add("TAMBO", daysAgo: 3)
        let newer = add("TAMBO", daysAgo: 1)            // posterior: no entra
        let older = add("TAMBO", daysAgo: 40)           // anterior pendiente: entra
        _ = add("TAMBO", daysAgo: 50, "Comida")         // ya clasificado: no entra
        _ = add("UBER", daysAgo: 60)                    // otro comercio: no entra
        try context.save()

        let all = try context.fetch(FetchDescriptor<Expense>())
        let earlier = PendingView.earlierPending(than: [chosen.id], in: all)

        #expect(earlier.map(\.id) == [older.id])
        #expect(!earlier.contains { $0.id == newer.id })
    }
}
