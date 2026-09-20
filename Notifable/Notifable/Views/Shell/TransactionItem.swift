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

    /// El filtro de los dos buscadores —Hoy y Movimientos—, aquí y no copiado
    /// en cada vista: dos campos con el mismo texto de ayuda que buscaran
    /// cosas distintas serían un error que nadie ve hasta que le falta un
    /// resultado.
    ///
    /// Incluye las **etiquetas**: buscar "madre" tiene que encontrar sus gastos
    /// aunque estén repartidos entre Salud y Supermercado, que es la razón de
    /// ser de una etiqueta.
    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        switch self {
        case .expense(let e):
            return e.merchant.localizedCaseInsensitiveContains(query)
                || e.category.localizedCaseInsensitiveContains(query)
                || (e.notes ?? "").localizedCaseInsensitiveContains(query)
                || e.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        case .income(let i):
            return i.source.localizedCaseInsensitiveContains(query)
                || (i.title ?? "").localizedCaseInsensitiveContains(query)
                || (i.notes ?? "").localizedCaseInsensitiveContains(query)
        }
    }
}

/// El texto de ayuda de los dos buscadores. Nombra las tres cosas por las que
/// se puede buscar, que es la única forma de que alguien descubra que la
/// etiqueta también se busca.
enum MovementSearch {
    static let placeholder = "Buscar comercio, categoría o etiqueta…"
}
