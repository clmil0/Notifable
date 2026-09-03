import Foundation

/// Reglas de categoría por comercio, en `UserDefaults` bajo `merchantCategories`.
///
/// Antes clasificar un comercio sólo reetiquetaba los gastos que ya estaban en
/// la base: el siguiente correo del mismo comercio volvía a caer en la Bandeja.
/// Guardar la regla hace que valga para el pasado **y** para lo que llegue.
enum MerchantRules {

    static let key = "merchantCategories"

    static func all(_ defaults: UserDefaults = .standard) -> [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    static func category(for merchant: String, defaults: UserDefaults = .standard) -> String? {
        let rules = all(defaults)
        if let exact = rules[merchant] { return exact }

        // Los parsers de banco añaden número de local ("METRO 0231"), así que el
        // nombre casi nunca coincide exacto dos veces. Se compara la raíz.
        let clean = normalized(Accounting.displayName(merchant))
        guard clean.count >= 4 else { return nil }
        for (ruleMerchant, category) in rules {
            let ruleClean = normalized(Accounting.displayName(ruleMerchant))
            guard ruleClean.count >= 4 else { continue }
            if clean.hasPrefix(ruleClean) || ruleClean.hasPrefix(clean) { return category }
        }
        return nil
    }

    static func set(_ category: String, for merchant: String, defaults: UserDefaults = .standard) {
        var rules = all(defaults)
        rules[merchant] = category
        defaults.set(rules, forKey: key)
    }

    static func remove(_ merchant: String, defaults: UserDefaults = .standard) {
        var rules = all(defaults)
        rules.removeValue(forKey: merchant)
        defaults.set(rules, forKey: key)
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "es_PE"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Lo necesario para deshacer una clasificación.
///
/// Aplicar una categoría es reversible, así que la app no pregunta antes: aplica
/// y ofrece "Deshacer" durante unos segundos. Un `alert` de confirmación por cada
/// comercio convertiría la Bandeja en lo que era.
///
/// Cubre tanto un comercio suelto como una selección mixta de varios comercios
/// y movimientos individuales (Pendientes): un solo toast debe poder revertir
/// todo lo que se tocó en un solo gesto de "Asignar a…".
struct UndoToken: Identifiable, Equatable {
    let id = UUID()
    /// Texto corto para el toast: "TOTTUS → Supermercado" o "3 comercios → Comida".
    let summary: String
    let category: String
    /// Categoría que tenía cada gasto antes, para poder devolverla exactamente
    /// — sea porque su comercio llevaba regla o porque se reclasificó suelto.
    let previousCategories: [UUID: String]
    /// Regla que había antes por cada comercio tocado con regla completa.
    /// `nil` en el valor = no había regla. Los comercios que sólo aportaron
    /// movimientos sueltos no aparecen aquí: no se tocó ninguna regla suya.
    let previousRules: [String: String?]

    static func == (lhs: UndoToken, rhs: UndoToken) -> Bool { lhs.id == rhs.id }
}

extension MerchantRules {

    /// Guarda la regla de un comercio y reclasifica su historial. Devuelve lo
    /// necesario para deshacer sólo ese comercio; quien combina una selección
    /// de varios usa esto como pieza y arma un único `UndoToken`.
    @discardableResult
    static func applyRule(_ category: String,
                          to merchant: String,
                          in expenses: [Expense],
                          defaults: UserDefaults = .standard) -> (previousCategories: [UUID: String], previousRule: String?) {
        let affected = expenses.filter { $0.merchant == merchant }
        var previous: [UUID: String] = [:]
        for expense in affected {
            previous[expense.id] = expense.category
            expense.category = category
        }
        let previousRule = all(defaults)[merchant]
        set(category, for: merchant, defaults: defaults)
        return (previous, previousRule)
    }

    /// Reclasifica movimientos puntuales **sin** crear ni tocar una regla de
    /// comercio: el siguiente movimiento del mismo comercio vuelve a Pendientes
    /// en vez de heredar la categoría del suelto. Es el caso de un Yape/Plin
    /// donde el resto de movimientos del mismo remitente puede ir a otra parte.
    @discardableResult
    static func applyToMovements(_ ids: Set<Expense.ID>,
                                 category: String,
                                 in expenses: [Expense]) -> [UUID: String] {
        var previous: [UUID: String] = [:]
        for expense in expenses where ids.contains(expense.id) {
            previous[expense.id] = expense.category
            expense.category = category
        }
        return previous
    }

    /// Guarda la regla y reclasifica los gastos pasados del comercio.
    /// Devuelve el token que permite revertirlo entero.
    @discardableResult
    static func apply(_ category: String,
                      to merchant: String,
                      in expenses: [Expense],
                      defaults: UserDefaults = .standard) -> UndoToken {
        let (previous, previousRule) = applyRule(category, to: merchant, in: expenses, defaults: defaults)
        return UndoToken(summary: Accounting.displayName(merchant) + " → " + category,
                         category: category,
                         previousCategories: previous,
                         previousRules: [merchant: previousRule])
    }

    /// Aplica una categoría a varios comercios completos de una vez ("Aceptar N"
    /// de un lote de sugerencias), con un único `UndoToken` para el conjunto.
    @discardableResult
    static func applyBatch(_ category: String,
                           to merchants: [String],
                           in expenses: [Expense],
                           defaults: UserDefaults = .standard) -> UndoToken {
        var previousCategories: [UUID: String] = [:]
        var previousRules: [String: String?] = [:]
        for merchant in merchants {
            let (previous, previousRule) = applyRule(category, to: merchant, in: expenses, defaults: defaults)
            previousCategories.merge(previous) { current, _ in current }
            previousRules[merchant] = previousRule
        }
        let summary = merchants.count == 1
            ? Accounting.displayName(merchants[0]) + " → " + category
            : "\(merchants.count) comercios → " + category
        return UndoToken(summary: summary,
                         category: category,
                         previousCategories: previousCategories,
                         previousRules: previousRules)
    }

    static func undo(_ token: UndoToken, in expenses: [Expense], defaults: UserDefaults = .standard) {
        for expense in expenses where token.previousCategories[expense.id] != nil {
            expense.category = token.previousCategories[expense.id] ?? Accounting.unclassified
        }
        for (merchant, rule) in token.previousRules {
            if let rule {
                set(rule, for: merchant, defaults: defaults)
            } else {
                remove(merchant, defaults: defaults)
            }
        }
    }
}
