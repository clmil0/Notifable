import Foundation
import Observation

/// Los movimientos que todavía no viste en Movimientos: los que llegaron del
/// correo y los que anotaste a mano.
///
/// Cuentan para el globo de la tarjeta «Historial» del dashboard y son los que
/// Movimientos resalta un momento al entrar; entrar los da por vistos.
///
/// Lo del correo se reconoce por el id del mensaje, no por el `UUID`: releer
/// el correo borra y rearma los gastos con otro `UUID`, y todo volvería a ser
/// nuevo. Lo anotado a mano no se rearma, así que su `UUID` basta.
@Observable
final class NewMovements {

    static let shared = NewMovements()

    private static let seenKey = "newMovements.seen"
    /// `v2`: desde que cuenta lo anotado a mano; lo que ya existía se vuelve
    /// a dar por visto una vez.
    private static let baselineKey = "newMovements.baselined.v2"

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
        guard !expense.isTransfer else { return nil }
        if let id = expense.emailID, !id.isEmpty { return "mail:" + id }
        return "id:" + expense.id.uuidString
    }

    static func key(_ income: Income) -> String? {
        guard !income.isTransfer else { return nil }
        if let id = income.emailID, !id.isEmpty { return "mail:" + id }
        return "id:" + income.id.uuidString
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
