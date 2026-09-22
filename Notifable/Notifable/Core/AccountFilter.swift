import Foundation
import Observation

/// La cuenta elegida en el chip «Todas las cuentas» del dashboard (`1b`).
///
/// Es **una sola** para toda la app: elegir BBVA arriba del dashboard filtra
/// el monto, el gráfico, los stats y las tarjetas, y al entrar a Movimientos
/// el carrusel ya llega con BBVA marcada. Y al revés: tocar otra cuenta en el
/// carrusel cambia el chip al volver.
@Observable
final class AccountFilter {

    static let shared = AccountFilter()

    /// La clave de `AccountCatalog`; `nil` es «Todas las cuentas».
    var selection: String?

    /// Las cuentas que toca un movimiento: la de origen (ya unida a su
    /// tarjeta, ver `AccountCatalog.canonical`) y, si va a una persona, la
    /// del destinatario.
    static func keys(of item: TransactionItem, catalog: AccountCatalog) -> [String] {
        switch item {
        case .expense(let e):
            return (catalog.resolve(e.originKey, at: e.date).map { [$0] } ?? []) + (e.payeeKey.map { [$0] } ?? [])
        case .income(let i):
            return (catalog.resolve(i.originKey, at: i.date).map { [$0] } ?? []) + (i.senderKey.map { [$0] } ?? [])
        }
    }

    static func matches(_ expense: Expense, account: String?, catalog: AccountCatalog) -> Bool {
        guard let account else { return true }
        return keys(of: .expense(expense), catalog: catalog).contains(account)
    }

    static func matches(_ income: Income, account: String?, catalog: AccountCatalog) -> Bool {
        guard let account else { return true }
        return keys(of: .income(income), catalog: catalog).contains(account)
    }
}
