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
struct UndoToken: Identifiable, Equatable {
    let id = UUID()
    let merchant: String
    let category: String
    /// Categoría que tenía cada gasto antes, para poder devolverla exactamente.
    let previousCategories: [UUID: String]
    /// Regla que había antes, si la había.
    let previousRule: String?

    static func == (lhs: UndoToken, rhs: UndoToken) -> Bool { lhs.id == rhs.id }
}

extension MerchantRules {

    /// Guarda la regla y reclasifica los gastos pasados del comercio.
    /// Devuelve el token que permite revertirlo entero.
    @discardableResult
    static func apply(_ category: String,
                      to merchant: String,
                      in expenses: [Expense],
                      defaults: UserDefaults = .standard) -> UndoToken {
        let affected = expenses.filter { $0.merchant == merchant }
        var previous: [UUID: String] = [:]
        for expense in affected {
            previous[expense.id] = expense.category
            expense.category = category
        }
        let previousRule = all(defaults)[merchant]
        set(category, for: merchant, defaults: defaults)

        return UndoToken(merchant: merchant,
                         category: category,
                         previousCategories: previous,
                         previousRule: previousRule)
    }

    static func undo(_ token: UndoToken, in expenses: [Expense], defaults: UserDefaults = .standard) {
        for expense in expenses where token.previousCategories[expense.id] != nil {
            expense.category = token.previousCategories[expense.id] ?? Accounting.unclassified
        }
        if let rule = token.previousRule {
            set(rule, for: token.merchant, defaults: defaults)
        } else {
            remove(token.merchant, defaults: defaults)
        }
    }
}
