import Foundation
import SwiftUI

/// Etiquetas: el corte que la categoría no puede dar.
///
/// La regla que separa las dos cosas, y de la que depende todo lo demás:
///
/// - **La categoría particiona el gasto.** Un gasto tiene exactamente una, así
///   que la suma de categorías es el total. Por eso puede haber límites, dona y
///   presupuesto general.
/// - **La etiqueta lo atraviesa.** Un gasto tiene cero o varias, así que la
///   suma de etiquetas **no** cuadra con el total: un gasto con "madre" y
///   "urgente" cuenta en las dos.
///
/// De ahí sale que los límites se queden en categorías: un límite sobre algo
/// que se solapa no tiene aritmética. Y de ahí sale también la regla de UI que
/// hay que respetar en todas partes: las etiquetas **nunca** se pintan como
/// dona ni como barras comparadas contra el total; se pintan como lista con
/// monto y como filtro.
struct CustomTag: Codable, Equatable, Identifiable {

    /// El nombre es la clave, igual que en `CustomCategory`: renombrar
    /// reescribe los gastos (ver `TagEditor`).
    var id: String { name }
    var name: String
    /// Identificador de `CategoryPalette`, compartida con las categorías: dos
    /// ruedas de color distintas producirían una app de dos paletas.
    /// `nil` = color derivado del nombre, estable entre ejecuciones.
    var colorID: String?

    init(name: String, colorID: String? = nil) {
        self.name = name
        self.colorID = colorID
    }
}

/// Catálogo de etiquetas.
///
/// A diferencia de `CategoryCatalog`, aquí **sí** se guarda una fila por cada
/// etiqueta que existe, aunque no se le haya cambiado nada: no hay un `switch`
/// de etiquetas por defecto del que tirar, así que este store es la única
/// lista de "qué etiquetas hay" y es lo que alimenta el selector.
///
/// Sin icono a propósito: el icono es la identidad visual de la categoría. Si
/// la etiqueta también lo tuviera, la cápsula competiría con la fila y se
/// dejaría de distinguir qué es cada cosa.
final class TagCatalog: ObservableObject {

    static let shared = TagCatalog()

    static let key = "tagCatalog"

    @Published private(set) var entries: [String: CustomTag] = [:]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = Self.decode(defaults.string(forKey: Self.key))
    }

    /// Lo que mata a las etiquetas en cualquier app que las tenga: "Madre",
    /// "madre" y "MADRE " conviviendo como tres etiquetas. Se compara sin
    /// tildes, sin mayúsculas y sin espacios de sobra —igual que
    /// `MerchantRules.normalized`—, pero se **guarda** lo que escribió el
    /// usuario: la que manda es la primera forma con la que se creó.
    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "es_PE"))
    }

    /// Tope blando por gasto. No bloquea nada en el modelo; es lo que la UI
    /// usa para dejar de ofrecer "añadir". Sin tope, la ficha del gasto deja
    /// de leerse a las seis cápsulas.
    static let maxPerExpense = 5

    var names: [String] { entries.values.map(\.name).sorted { $0.localizedCompare($1) == .orderedAscending } }

    func entry(for name: String) -> CustomTag? { entries[Self.normalized(name)] }

    /// El nombre tal como se guardó la primera vez. Es lo que se escribe en el
    /// gasto, para que dos formas de teclear la misma etiqueta acaben en la
    /// misma cadena dentro de `Expense.tags`.
    func canonicalName(for name: String) -> String {
        entry(for: name)?.name ?? name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func color(for name: String) -> Color {
        if let id = entry(for: name)?.colorID, let color = CategoryPalette.color(for: id) { return color }
        // Derivado del nombre y estable entre ejecuciones (`hashValue` no lo
        // es), igual que hace `CategoryStyle` con las categorías nuevas.
        let sum = Self.normalized(name).unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Color(hue: Double(sum % 360) / 360.0, saturation: 0.55, brightness: 0.78)
    }

    func exists(_ name: String) -> Bool { entries[Self.normalized(name)] != nil }

    /// Crea la etiqueta si no existía y devuelve el nombre canónico a escribir
    /// en el gasto. Un solo sitio para "usar una etiqueta", porque crear y
    /// asignar son el mismo gesto: nadie crea una etiqueta para no ponerla.
    @discardableResult
    func use(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let key = Self.normalized(trimmed)
        if let existing = entries[key] { return existing.name }
        entries[key] = CustomTag(name: trimmed)
        persist()
        return trimmed
    }

    func save(_ tag: CustomTag) {
        let trimmed = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var stored = tag
        stored.name = trimmed
        entries[Self.normalized(trimmed)] = stored
        persist()
    }

    func remove(_ name: String) {
        entries[Self.normalized(name)] = nil
        persist()
    }

    /// Empezar de cero (Configuración › Borrar datos).
    func removeAll() {
        entries = [:]
        persist()
    }

    /// Sólo el catálogo. Los gastos los reescribe `TagEditor.rename`, que es
    /// quien sabe llamar a esto en el orden correcto.
    func rename(_ name: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldKey = Self.normalized(name)
        guard !trimmed.isEmpty, let existing = entries[oldKey] else { return }
        var moved = existing
        moved.name = trimmed
        entries[oldKey] = nil
        entries[Self.normalized(trimmed)] = moved
        persist()
    }

    /// Texto y no `Data`, al revés que `CategoryCatalog`: así el catálogo entra
    /// en `AppPreferences.syncable` y se respalda sin abrir una columna nueva
    /// en Supabase ni un campo más en el payload — el mismo camino que usan
    /// los vínculos de cobros y las notas por amigo.
    private func persist() {
        guard let data = try? JSONEncoder().encode(Array(entries.values)),
              let text = String(data: data, encoding: .utf8) else { return }
        defaults.set(text, forKey: Self.key)
    }

    private static func decode(_ text: String?) -> [String: CustomTag] {
        guard let data = text?.data(using: .utf8),
              let list = try? JSONDecoder().decode([CustomTag].self, from: data) else { return [:] }
        return Dictionary(list.map { (normalized($0.name), $0) }, uniquingKeysWith: { first, _ in first })
    }
}

// MARK: - Operaciones sobre etiquetas

/// Renombrar, fusionar y eliminar tocan los gastos, el catálogo y el registro
/// de ediciones a la vez. Están aquí juntas por el mismo motivo que
/// `CategoryEditor`: para que ninguna vista haga sólo dos de las tres.
///
/// Fusionar pesa más aquí que en categorías: las etiquetas se escriben a mano,
/// así que los duplicados por variante ("mamá" / "madre") son inevitables y
/// tiene que haber una salida que no pierda nada.
enum TagEditor {

    static func expenseCount(of tag: String, in expenses: [Expense]) -> Int {
        let key = TagCatalog.normalized(tag)
        return expenses.reduce(0) { $0 + ($1.hasTag(key) ? 1 : 0) }
    }

    static func rename(_ tag: String,
                       to newName: String,
                       in expenses: [Expense],
                       catalog: TagCatalog = .shared,
                       defaults: UserDefaults = .standard) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = TagCatalog.normalized(tag)
        guard !trimmed.isEmpty, TagCatalog.normalized(trimmed) != key || trimmed != tag else { return }

        // Si el destino ya existe es una fusión, no un renombre: un gasto que
        // tuviera las dos se quedaría con la etiqueta repetida.
        if catalog.exists(trimmed), TagCatalog.normalized(trimmed) != key {
            await merge(tag, into: trimmed, in: expenses, catalog: catalog, defaults: defaults)
            return
        }

        await Batching.run(expenses.filter { $0.hasTag(key) }) { expense in
            expense.tags = expense.tags.map { TagCatalog.normalized($0) == key ? trimmed : $0 }
        }
        ExpenseEditStore.replaceTag(tag, with: trimmed, defaults: defaults)
        catalog.rename(tag, to: trimmed)
    }

    static func merge(_ source: String,
                      into target: String,
                      in expenses: [Expense],
                      catalog: TagCatalog = .shared,
                      defaults: UserDefaults = .standard) async {
        let sourceKey = TagCatalog.normalized(source)
        let targetName = catalog.canonicalName(for: target)
        guard sourceKey != TagCatalog.normalized(targetName) else { return }

        await Batching.run(expenses.filter { $0.hasTag(sourceKey) }) { expense in
            var list = expense.tags.filter { TagCatalog.normalized($0) != sourceKey }
            if !list.contains(where: { TagCatalog.normalized($0) == TagCatalog.normalized(targetName) }) {
                list.append(targetName)
            }
            expense.tags = list
        }
        ExpenseEditStore.replaceTag(source, with: targetName, defaults: defaults)
        catalog.remove(source)
    }

    /// Eliminar una etiqueta **no** toca la categoría de nada: los gastos
    /// siguen donde estaban, sólo pierden la cápsula. Es la diferencia con
    /// borrar una categoría, que manda sus gastos a Sin Clasificar.
    static func delete(_ tag: String,
                       in expenses: [Expense],
                       catalog: TagCatalog = .shared,
                       defaults: UserDefaults = .standard) async {
        let key = TagCatalog.normalized(tag)
        await Batching.run(expenses.filter { $0.hasTag(key) }) { expense in
            expense.tags = expense.tags.filter { TagCatalog.normalized($0) != key }
        }
        ExpenseEditStore.replaceTag(tag, with: nil, defaults: defaults)
        catalog.remove(tag)
    }
}

// MARK: - Cálculo

/// Los totales por etiqueta, fuera de las vistas y sobre `ExpenseSnapshot`
/// para poder probarse sin `ModelContainer`, igual que `CategoryLimits`.
///
/// Lo que **no** hay aquí, a propósito: nada que compare una etiqueta contra
/// el total del periodo. Las etiquetas se solapan, así que un porcentaje sobre
/// el total sería una cifra que no suma 100 y que invita a leerla como si lo
/// hiciera. La referencia honesta es el monto y, como mucho, el gasto sin
/// etiquetar, que sí es disjunto de todo lo demás.
enum TagTotals {

    struct Row: Identifiable, Equatable {
        let tag: String
        let total: Double
        let count: Int
        var id: String { TagCatalog.normalized(tag) }
    }

    static func cost(of expense: ExpenseSnapshot, usdToPen: Double) -> Int {
        Accounting.penCents(amount: Accounting.netCost(of: expense),
                            currency: expense.currency,
                            fxRateAtCapture: expense.fxRateAtCapture,
                            fallbackRate: usdToPen)
    }

    /// Una fila por etiqueta usada en el intervalo. `known` añade las del
    /// catálogo que no se usaron: una etiqueta que existe y no aparece en el
    /// mes es información, no un hueco.
    static func rows(expenses: [ExpenseSnapshot],
                     in interval: DateInterval,
                     usdToPen: Double,
                     known: [String] = []) -> [Row] {
        var cents: [String: Int] = [:]
        var counts: [String: Int] = [:]
        var display: [String: String] = [:]

        for expense in expenses {
            guard expense.date >= interval.start, expense.date < interval.end,
                  !expense.tags.isEmpty else { continue }
            let cost = cost(of: expense, usdToPen: usdToPen)
            // `Set` de claves: un gasto con la misma etiqueta repetida por un
            // respaldo antiguo no se contaría dos veces.
            for key in Set(expense.tags.map(TagCatalog.normalized)) {
                guard let name = expense.tags.first(where: { TagCatalog.normalized($0) == key }) else { continue }
                cents[key, default: 0] += cost
                counts[key, default: 0] += 1
                display[key] = display[key] ?? name
            }
        }

        for name in known {
            let key = TagCatalog.normalized(name)
            display[key] = display[key] ?? name
            cents[key] = cents[key] ?? 0
            counts[key] = counts[key] ?? 0
        }

        return display.map { key, name in
            Row(tag: name, total: Money.value(cents[key] ?? 0), count: counts[key] ?? 0)
        }
        .sorted {
            if Money.cents($0.total) != Money.cents($1.total) {
                return Money.cents($0.total) > Money.cents($1.total)
            }
            return $0.tag.localizedCompare($1.tag) == .orderedAscending
        }
    }

    /// Gasto del intervalo que no lleva ninguna etiqueta. Es la única cifra de
    /// esta pantalla que se puede restar del total sin mentir.
    static func untagged(expenses: [ExpenseSnapshot],
                         in interval: DateInterval,
                         usdToPen: Double) -> Double {
        var cents = 0
        for expense in expenses where expense.tags.isEmpty {
            guard expense.date >= interval.start, expense.date < interval.end else { continue }
            cents += cost(of: expense, usdToPen: usdToPen)
        }
        return Money.value(cents)
    }

    /// Las etiquetas que alguna vez se usaron, en **todo** el historial.
    ///
    /// Separa los dos vacíos que la lista dibuja distinto: una etiqueta que se
    /// usó otros meses ("Sin movimientos este mes") no es lo mismo que una que
    /// se creó y nunca se puso a nada ("Asígnala desde cualquier movimiento"),
    /// que es la única que necesita un empujón.
    static func everUsed(_ expenses: [ExpenseSnapshot]) -> Set<String> {
        var keys: Set<String> = []
        for expense in expenses {
            for tag in expense.tags { keys.insert(TagCatalog.normalized(tag)) }
        }
        return keys
    }

    /// Cómo queda la etiqueta destino tras absorber a otra.
    ///
    /// Es una **unión**, no una suma: un movimiento que ya llevaba las dos
    /// cuenta una vez. Sumar los dos totales prometería en la hoja de fusión
    /// una cifra que después no aparece.
    static func mergePreview(source: String,
                             target: String,
                             expenses: [ExpenseSnapshot],
                             in interval: DateInterval,
                             usdToPen: Double) -> (count: Int, total: Double) {
        let sourceKey = TagCatalog.normalized(source)
        let targetKey = TagCatalog.normalized(target)
        var cents = 0
        var count = 0
        for expense in expenses {
            guard expense.date >= interval.start, expense.date < interval.end else { continue }
            let keys = Set(expense.tags.map(TagCatalog.normalized))
            guard keys.contains(sourceKey) || keys.contains(targetKey) else { continue }
            cents += cost(of: expense, usdToPen: usdToPen)
            count += 1
        }
        return (count, Money.value(cents))
    }

    /// Reparto por categoría **dentro** de una etiqueta: "madre" se fue en
    /// Salud y en Supermercado. Aquí sí suma el total de la etiqueta, porque
    /// la categoría es una partición.
    static func byCategory(tag: String,
                           expenses: [ExpenseSnapshot],
                           in interval: DateInterval,
                           usdToPen: Double) -> [(category: String, total: Double)] {
        let key = TagCatalog.normalized(tag)
        var cents: [String: Int] = [:]
        for expense in expenses {
            guard expense.date >= interval.start, expense.date < interval.end,
                  expense.tags.contains(where: { TagCatalog.normalized($0) == key }) else { continue }
            cents[expense.category, default: 0] += cost(of: expense, usdToPen: usdToPen)
        }
        return cents.map { ($0.key, Money.value($0.value)) }
            .sorted { Money.cents($0.total) > Money.cents($1.total) }
    }
}
