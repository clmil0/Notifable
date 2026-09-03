import Foundation
import SwiftUI

/// Identidad de una categoría creada o personalizada por el usuario.
///
/// Hasta ahora una categoría era **sólo** el `String` de `Expense.category`: el
/// color y el icono salían de un `switch` fijo en `CategoryStyle` y no había
/// forma de renombrarla. Esto es lo mínimo para que `6b` pueda cambiar nombre,
/// color e icono sin tocar el modelo de datos: el nombre sigue siendo la clave,
/// y renombrar reescribe los gastos y las reglas de comercio.
struct CustomCategory: Codable, Equatable, Identifiable {

    var id: String { name }
    var name: String
    /// Identificador de `CategoryPalette`, no un `Color`: `Color` no es `Codable`
    /// de forma estable entre versiones de iOS.
    var colorID: String?
    /// SF Symbol. `nil` = el que decida `CategoryStyle` por el nombre.
    var icon: String?

    init(name: String, colorID: String? = nil, icon: String? = nil) {
        self.name = name
        self.colorID = colorID
        self.icon = icon
    }
}

/// Los colores elegibles en `6b`. Cinco, con nombre y contraste ya verificados:
/// una rueda de color libre produce categorías ilegibles en modo claro.
enum CategoryPalette {

    struct Option: Identifiable, Equatable {
        let id: String
        let label: String
        let color: Color
    }

    static let options: [Option] = [
        Option(id: "naranja", label: "Naranja", color: .orange),
        Option(id: "morado",  label: "Morado",  color: .purple),
        Option(id: "azul",    label: "Azul",    color: .blue),
        Option(id: "verde",   label: "Verde",   color: .green),
        Option(id: "rojo",    label: "Rojo",    color: Color(red: 1.0, green: 0.42, blue: 0.38)),
        Option(id: "turquesa", label: "Turquesa", color: .teal),
        Option(id: "rosa",    label: "Rosa",    color: .pink),
        Option(id: "indigo",  label: "Índigo",  color: .indigo)
    ]

    static func color(for id: String?) -> Color? {
        guard let id else { return nil }
        return options.first { $0.id == id }?.color
    }

    /// Los cinco de la fila de `6b`; el resto queda disponible por si se añade
    /// un selector completo más adelante.
    static var primary: [Option] { Array(options.prefix(5)) }
}

/// Iconos ofrecidos al personalizar. Los mismos que ya usa `CategoryStyle`
/// más un puñado de usos frecuentes, para no abrir el catálogo entero de
/// SF Symbols dentro de una pantalla de ajustes.
enum CategoryIcons {
    static let all: [String] = [
        "fork.knife", "cart.fill", "car.fill", "bus.fill", "fuelpump.fill",
        "house.fill", "bolt.fill", "drop.fill", "flame.fill", "wifi",
        "cross.case.fill", "pills.fill", "heart.fill", "dumbbell.fill",
        "bag.fill", "tshirt.fill", "gift.fill", "pawprint.fill",
        "play.tv.fill", "gamecontroller.fill", "music.note", "book.fill",
        "graduationcap.fill", "briefcase.fill", "airplane", "creditcard.fill",
        "person.2.fill", "scissors", "wrench.and.screwdriver.fill", "tray.full.fill"
    ]
}

/// Catálogo de categorías personalizadas.
///
/// Guarda **sólo** lo que el usuario cambió. Una categoría que nunca se tocó no
/// tiene fila aquí y sigue resolviéndose por `CategoryStyle`, así que este store
/// puede estar vacío y la app se comporta igual que antes.
final class CategoryCatalog: ObservableObject {

    static let shared = CategoryCatalog()

    static let key = "categoryCatalog"

    @Published private(set) var entries: [String: CustomCategory] = [:]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = Self.decode(defaults.data(forKey: Self.key) ?? Data())
    }

    func entry(for name: String) -> CustomCategory? { entries[name] }

    func color(for name: String) -> Color? { CategoryPalette.color(for: entries[name]?.colorID) }

    func icon(for name: String) -> String? { entries[name]?.icon }

    /// Categorías creadas por el usuario que aún no tienen ningún gasto: sin
    /// esto, crear una categoría desde `6a` y no asignar nada la haría
    /// desaparecer al cerrar la pantalla.
    var names: [String] { Array(entries.keys) }

    func save(_ category: CustomCategory) {
        entries[category.name] = category
        persist()
    }

    func remove(_ name: String) {
        entries[name] = nil
        persist()
    }

    func rename(_ name: String, to newName: String) {
        guard name != newName else { return }
        var moved = entries[name] ?? CustomCategory(name: name)
        moved.name = newName
        entries[name] = nil
        entries[newName] = moved
        persist()
    }

    /// Las categorías por defecto y la bandeja no se borran ni se renombran: son
    /// el suelo sobre el que se apoyan las reglas y el motor de sugerencias.
    static func isSystem(_ name: String) -> Bool {
        name == Accounting.unclassified || CategoryStyle.defaults.contains(name)
    }

    private func persist() {
        let encoded = (try? JSONEncoder().encode(Array(entries.values))) ?? Data()
        defaults.set(encoded, forKey: Self.key)
    }

    private static func decode(_ data: Data) -> [String: CustomCategory] {
        guard let list = try? JSONDecoder().decode([CustomCategory].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: list.map { ($0.name, $0) })
    }
}

// MARK: - Operaciones sobre categorías

/// Renombrar, fusionar y eliminar tocan cuatro sitios a la vez —los gastos, las
/// reglas de comercio, el catálogo y el límite—. Están aquí juntas para que
/// ninguna vista haga sólo tres de las cuatro.
///
/// El `modelContext.save()` lo hace quien llama: es la vista la que sabe si el
/// usuario puede deshacer todavía.
enum CategoryEditor {

    /// Cuántos gastos caen hoy en la categoría. Es el número que `6b` enseña
    /// antes de eliminar; sin él, borrar es una apuesta.
    static func expenseCount(of category: String, in expenses: [Expense]) -> Int {
        expenses.reduce(0) { $0 + ($1.category == category ? 1 : 0) }
    }

    /// Comercios cuya regla apunta a esta categoría ("QUÉ CAE AQUÍ").
    static func merchants(for category: String,
                          defaults: UserDefaults = .standard) -> [String] {
        MerchantRules.all(defaults)
            .filter { $0.value == category }
            .keys
            .sorted { Accounting.displayName($0) < Accounting.displayName($1) }
    }

    static func rename(_ category: String,
                       to newName: String,
                       in expenses: [Expense],
                       catalog: CategoryCatalog = .shared,
                       budgets: CategoryBudgetStore = .shared,
                       defaults: UserDefaults = .standard) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != category, !CategoryCatalog.isSystem(category) else { return }

        for expense in expenses where expense.category == category {
            expense.category = trimmed
        }
        for (merchant, target) in MerchantRules.all(defaults) where target == category {
            MerchantRules.set(trimmed, for: merchant, defaults: defaults)
        }
        catalog.rename(category, to: trimmed)
        budgets.rename(category, to: trimmed)
    }

    /// Mueve los gastos y **suma** los límites. Fusionar existe para no perder
    /// información: eliminar era la única salida y dejaba los gastos huérfanos.
    static func merge(_ source: String,
                      into target: String,
                      in expenses: [Expense],
                      catalog: CategoryCatalog = .shared,
                      budgets: CategoryBudgetStore = .shared,
                      defaults: UserDefaults = .standard) {
        guard source != target else { return }

        for expense in expenses where expense.category == source {
            expense.category = target
        }
        for (merchant, category) in MerchantRules.all(defaults) where category == source {
            MerchantRules.set(target, for: merchant, defaults: defaults)
        }
        budgets.merge(source, into: target)
        catalog.remove(source)
    }

    /// Los gastos pasan a `Sin Clasificar` y las reglas del comercio se borran:
    /// dejarlas apuntando a una categoría que ya no existe haría reaparecer el
    /// nombre en la siguiente sincronización.
    static func delete(_ category: String,
                       in expenses: [Expense],
                       catalog: CategoryCatalog = .shared,
                       budgets: CategoryBudgetStore = .shared,
                       defaults: UserDefaults = .standard) {
        guard !CategoryCatalog.isSystem(category) else { return }

        for expense in expenses where expense.category == category {
            expense.category = Accounting.unclassified
        }
        for (merchant, target) in MerchantRules.all(defaults) where target == category {
            MerchantRules.remove(merchant, defaults: defaults)
        }
        budgets.remove(category)
        catalog.remove(category)
    }
}
