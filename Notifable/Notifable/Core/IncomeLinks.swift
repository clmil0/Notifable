import Foundation
import SwiftData

/// El vínculo entre un cobro y el gasto que estaba por cobrar.
///
/// En SwiftData ese vínculo es la relación `Income.debtReference`, y eso lo
/// hace frágil por dos motivos:
///
/// 1. El gasto viene del correo y **se borra y se vuelve a crear** en cada
///    relectura (y al restaurar en un teléfono nuevo no existe todavía). La
///    relación apunta a un objeto, no a una identidad estable, así que se
///    rompe: el cobro sobrevive pero deja de estar unido a nada, y el gasto
///    vuelve a figurar como si nadie hubiera devuelto un sol.
/// 2. Un `UUID` de SwiftData tampoco sirve como llave: cambia en cada
///    reconstrucción.
///
/// Aquí el vínculo se guarda por la huella del gasto (`TransactionKey`), que
/// sí sobrevive, y se vuelve a atar cuando el gasto reaparece.
struct IncomeLink: Codable, Equatable {
    /// `id` del `Income`, que sí es estable: los ingresos se respaldan enteros.
    var incomeID: UUID
    /// Huella del gasto por cobrar al que abona.
    var markKey: String
    /// Si con este cobro quedó saldado.
    var isFinal: Bool
}

enum IncomeLinkStore {

    static let key = "incomeDebtLinks"

    static func all(_ defaults: UserDefaults = .standard) -> [UUID: IncomeLink] {
        guard let data = defaults.data(forKey: key),
              let list = try? JSONDecoder().decode([IncomeLink].self, from: data) else { return [:] }
        return Dictionary(list.map { ($0.incomeID, $0) }, uniquingKeysWith: { $1 })
    }

    static func markKey(for incomeID: UUID, _ defaults: UserDefaults = .standard) -> String? {
        all(defaults)[incomeID]?.markKey
    }

    // MARK: - Escribir

    /// Se anota en el momento de registrar el cobro, no al respaldar: si se
    /// dejara para después, una relectura del correo que rompa la relación
    /// llegaría antes que el respaldo y el vínculo se perdería sin rastro.
    static func record(income: Income, expense: Expense, isFinal: Bool,
                       defaults: UserDefaults = .standard) {
        save(IncomeLink(incomeID: income.id,
                        markKey: TransactionKey.key(for: expense),
                        isFinal: isFinal),
             defaults: defaults)
    }

    static func save(_ link: IncomeLink, defaults: UserDefaults = .standard) {
        var current = all(defaults)
        current[link.incomeID] = link
        persist(current, defaults: defaults)
    }

    static func merge(_ incoming: [IncomeLink], defaults: UserDefaults = .standard) {
        var current = all(defaults)
        for link in incoming where current[link.incomeID] == nil {
            current[link.incomeID] = link
        }
        persist(current, defaults: defaults)
    }

    static func removeAll(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    private static func persist(_ links: [UUID: IncomeLink], defaults: UserDefaults) {
        let encoded = (try? JSONEncoder().encode(links.values.sorted { $0.incomeID.uuidString < $1.incomeID.uuidString })) ?? Data()
        defaults.set(encoded, forKey: key)
    }

    // MARK: - Volver a atar

    /// Reconstruye las relaciones que existan hoy. Idempotente y barata: se
    /// llama al terminar cada lectura de Gmail, que es cuando los gastos por
    /// cobrar acaban de reaparecer.
    @discardableResult
    static func apply(in modelContext: ModelContext, defaults: UserDefaults = .standard) -> Int {
        let links = all(defaults)
        guard !links.isEmpty else { return 0 }

        let incomes = (try? modelContext.fetch(FetchDescriptor<Income>())) ?? []
        let expenses = (try? modelContext.fetch(FetchDescriptor<Expense>())) ?? []
        guard !incomes.isEmpty, !expenses.isEmpty else { return 0 }

        let expensesByKey = Dictionary(expenses.map { (TransactionKey.key(for: $0), $0) },
                                       uniquingKeysWith: { first, _ in first })
        var relinked = 0
        for income in incomes {
            guard let link = links[income.id] else { continue }
            guard let expense = expensesByKey[link.markKey] else { continue }
            if income.debtReference?.id != expense.id {
                income.debtReference = expense
                relinked += 1
            }
            if income.isFinalDebtPayment != link.isFinal {
                income.isFinalDebtPayment = link.isFinal
                relinked += 1
            }
        }
        if relinked > 0 { try? modelContext.save() }
        return relinked
    }
}
