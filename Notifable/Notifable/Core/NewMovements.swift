import Foundation
import Observation

/// Los movimientos que llegaron del correo y todavía no viste en Movimientos.
///
/// Cuentan para el globo de la tarjeta «Historial» del dashboard y son los que
/// Movimientos resalta un momento al entrar; entrar los da por vistos.
///
/// La llave es el id del correo (`TransactionKey`), no el `UUID`: releer el
/// correo borra y rearma los gastos con otro `UUID`, y todo volvería a ser
/// nuevo. Lo anotado a mano no cuenta: ya lo viste al anotarlo.
@Observable
final class NewMovements {

    static let shared = NewMovements()

    private static let seenKey = "newMovements.seen"
    private static let baselineKey = "newMovements.baselined"

    private(set) var seen: Set<String>
    /// Hasta la primera vez no hay con qué comparar: todo lo que ya existe se
    /// da por visto, en vez de estrenar la función con cientos de «nuevos».
    private(set) var isBaselined: Bool

    private init() {
        let defaults = UserDefaults.standard
        seen = Set(defaults.stringArray(forKey: Self.seenKey) ?? [])
        isBaselined = defaults.bool(forKey: Self.baselineKey)
    }

    static func key(_ expense: Expense) -> String? {
        guard !expense.isTransfer, let id = expense.emailID, !id.isEmpty else { return nil }
        return "mail:" + id
    }

    static func key(_ income: Income) -> String? {
        guard !income.isTransfer, let id = income.emailID, !id.isEmpty else { return nil }
        return "mail:" + id
    }

    static func key(_ item: TransactionItem) -> String? {
        switch item {
        case .expense(let e): return key(e)
        case .income(let i):  return key(i)
        }
    }

    static func keys(expenses: [Expense], incomes: [Income]) -> Set<String> {
        Set(expenses.compactMap(key) + incomes.compactMap(key))
    }

    func unseen(in keys: Set<String>) -> Set<String> {
        isBaselined ? keys.subtracting(seen) : []
    }

    /// La primera vez, todo lo que hay queda como visto.
    func baselineIfNeeded(_ keys: Set<String>) {
        guard !isBaselined else { return }
        isBaselined = true
        UserDefaults.standard.set(true, forKey: Self.baselineKey)
        markSeen(keys)
    }

    func markSeen(_ keys: Set<String>) {
        let added = keys.subtracting(seen)
        guard !added.isEmpty else { return }
        seen.formUnion(added)
        UserDefaults.standard.set(Array(seen), forKey: Self.seenKey)
    }
}
