import Foundation

/// Un movimiento de la lista, sea gasto o ingreso.
///
/// Vivía dentro de `DashboardView`. Al partir aquella pantalla en Hoy,
/// Movimientos y Balance dejó de tener dueño único, así que se muda a su
/// propio archivo en vez de quedarse colgando en la vista que ya no existe.
enum TransactionItem: Identifiable {
    case expense(Expense)
    case income(Income)

    var id: UUID {
        switch self {
        case .expense(let e): return e.id
        case .income(let i):  return i.id
        }
    }

    var date: Date {
        switch self {
        case .expense(let e): return e.date
        case .income(let i):  return i.date
        }
    }
}
