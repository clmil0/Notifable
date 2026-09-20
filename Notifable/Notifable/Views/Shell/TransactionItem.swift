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
    /// Busca en comercio, categoría, descripción y **etiquetas**: escribir
    /// "madre" tiene que encontrar sus gastos aunque estén repartidos entre
    /// Salud y Supermercado, que es la razón de ser de una etiqueta.
    ///
    /// Con `#` delante busca **sólo** por etiqueta. Es para cuando el nombre
    /// choca con el de un comercio o una categoría: "salidas" de texto libre
    /// trae también la cena cuyo comercio se llama así, y `#salidas` trae
    /// exactamente lo que etiquetaste.
    func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        if let tag = Self.tagQuery(trimmed) { return hasTagMatching(tag) }

        switch self {
        case .expense(let e):
            return e.merchant.localizedCaseInsensitiveContains(trimmed)
                || e.category.localizedCaseInsensitiveContains(trimmed)
                || (e.notes ?? "").localizedCaseInsensitiveContains(trimmed)
                || e.tags.contains { $0.localizedCaseInsensitiveContains(trimmed) }
        case .income(let i):
            return i.source.localizedCaseInsensitiveContains(trimmed)
                || (i.title ?? "").localizedCaseInsensitiveContains(trimmed)
                || (i.notes ?? "").localizedCaseInsensitiveContains(trimmed)
        }
    }

    /// La etiqueta que se busca, ya normalizada, o `nil` si la consulta no es
    /// de etiqueta. Un `#` suelto todavía no es una búsqueda: quien acaba de
    /// escribirlo está a mitad de teclear, y vaciarle la lista en ese momento
    /// parece que no hay nada.
    static func tagQuery(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        let name = TagCatalog.normalized(String(trimmed.dropFirst()))
        return name.isEmpty ? nil : name
    }

    /// Los ingresos no llevan etiquetas, así que una búsqueda por etiqueta los
    /// deja fuera enteros en vez de colarlos sin filtrar.
    private func hasTagMatching(_ normalizedNeedle: String) -> Bool {
        guard case .expense(let e) = self else { return false }
        return e.tags.contains { TagCatalog.normalized($0).contains(normalizedNeedle) }
    }
}

/// Lo que se dice cuando una búsqueda no encuentra nada. Con `#` el consejo
/// no puede ser "prueba con el comercio": la consulta dijo explícitamente que
/// sólo quería etiquetas, y lo útil es decir que esa etiqueta no existe o no
/// tiene movimientos aquí.
enum MovementSearch {
    static let placeholder = "Buscar comercio, categoría o etiqueta…"

    /// `#salidas` busca **sólo** etiquetas; sin `#`, busca en todo.
    static func emptyMessage(for query: String) -> String {
        TransactionItem.tagQuery(query) == nil
            ? "Prueba con el nombre del comercio, la categoría o una etiqueta."
            : "Ninguna etiqueta con ese nombre tiene movimientos aquí. Sin la almohadilla se busca también por comercio y categoría."
    }
}
