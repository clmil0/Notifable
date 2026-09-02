import Foundation

/// Sugerencia de categoría para un comercio sin clasificar.
struct CategorySuggestion: Equatable {
    let category: String
    /// 0…1. Por debajo de 0.45 no se muestra el botón "Aplicar".
    let confidence: Double
    /// Texto corto que explica por qué. La sugerencia sin motivo no se aplica sola.
    let reason: String
}

/// Motor de sugerencias de la Bandeja.
///
/// El flujo anterior costaba: por cada comercio, abrir un sheet, buscar en una
/// lista, elegir, cerrar. Con 12 comercios son 48 toques. Aquí la app propone y
/// el usuario confirma con uno.
///
/// Orden de resolución: regla exacta → regla por raíz del nombre →
/// mayoría del canal (Yape/Plin) → diccionario de comercios conocidos.
enum SuggestionEngine {

    /// Diccionario de comercios frecuentes en Perú. Sólo se usa como último
    /// recurso, y siempre pidiendo confirmación.
    private static let keywords: [(tokens: [String], category: String)] = [
        (["metro", "tottus", "plaza vea", "vivanda", "wong", "makro", "mass", "oxxo", "tambo"], "Supermercado"),
        (["rappi", "pedidosya", "didi food", "kfc", "bembos", "starbucks", "papa john", "pizza", "burger", "norkys", "china wok", "popeyes"], "Comida"),
        (["uber", "cabify", "beat", "didi", "taxi", "metropolitano", "primax", "repsol", "petroperu", "grifo", "pecsa"], "Transporte"),
        (["netflix", "spotify", "disney", "hbo", "max", "prime video", "youtube", "crunchyroll", "cineplanet", "cinemark"], "Entretenimiento"),
        (["movistar", "claro", "entel", "bitel", "win", "luz del sur", "enel", "sedapal", "calidda"], "Servicios"),
        (["inkafarma", "mifarma", "boticas", "clinica", "farmacia"], "Salud"),
        (["falabella", "ripley", "oechsle", "saga", "h&m", "zara", "adidas", "nike"], "Compras")
    ]

    /// - Parameters:
    ///   - merchant: nombre crudo, tal como llega del parser (puede traer "YAPE - ").
    ///   - rules: `merchantCategories` de UserDefaults, [comercio: categoría].
    ///   - history: todos los gastos, para inferir por canal y por raíz de nombre.
    static func suggest(for merchant: String,
                        rules: [String: String],
                        history: [Expense]) -> CategorySuggestion? {

        // 1. Regla exacta ya guardada.
        if let exact = rules[merchant], exact != Accounting.unclassified {
            return CategorySuggestion(category: exact, confidence: 1.0, reason: "Ya tienes una regla para este comercio")
        }

        let clean = normalize(Accounting.displayName(merchant))

        // 2. Misma raíz de nombre: "METRO 0231" contra la regla "Metro".
        //    Los parsers de banco añaden número de local, así que el nombre
        //    nunca coincide exacto dos veces.
        for (ruleMerchant, category) in rules where category != Accounting.unclassified {
            let ruleClean = normalize(Accounting.displayName(ruleMerchant))
            guard ruleClean.count >= 4 else { continue }
            if clean.hasPrefix(ruleClean) || ruleClean.hasPrefix(clean) {
                return CategorySuggestion(
                    category: category,
                    confidence: 0.9,
                    reason: "Se parece a " + Accounting.displayName(ruleMerchant)
                )
            }
        }

        // 3. Mayoría del canal: la mayoría de tus Yape/Plin ya clasificados.
        if let channel = channel(of: merchant) {
            let sameChannel = history.filter {
                $0.merchant.hasPrefix(channel.prefix) && $0.category != Accounting.unclassified
            }
            let counts = Dictionary(grouping: sameChannel, by: { $0.category }).mapValues { $0.count }
            if let top = counts.max(by: { $0.value < $1.value }), top.value >= 2 {
                let total = sameChannel.count
                let share = Double(top.value) / Double(max(1, total))
                return CategorySuggestion(
                    category: top.key,
                    confidence: min(0.85, 0.45 + share * 0.4),
                    reason: "\(top.value) de tus \(total) \(channel.name) son " + top.key
                )
            }
        }

        // 4. Diccionario de comercios conocidos.
        for entry in keywords {
            if entry.tokens.contains(where: { clean.contains($0) }) {
                return CategorySuggestion(
                    category: entry.category,
                    confidence: 0.7,
                    reason: "Suele ser " + entry.category
                )
            }
        }

        return nil
    }

    /// Categorías más usadas por el usuario, para los chips de la tarjeta.
    /// Se excluye la sugerencia para no repetir la misma opción dos veces.
    static func frequentCategories(history: [Expense],
                                   excluding: String?,
                                   limit: Int = 3) -> [String] {
        let classified = history.filter { $0.category != Accounting.unclassified }
        let counts = Dictionary(grouping: classified, by: { $0.category }).mapValues { $0.count }
        return counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { $0.key }
            .filter { $0 != excluding }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Helpers

    private struct Channel { let prefix: String; let name: String }

    private static func channel(of merchant: String) -> Channel? {
        if merchant.hasPrefix("YAPE - ") { return Channel(prefix: "YAPE - ", name: "Yape") }
        if merchant.hasPrefix("PLIN - ") { return Channel(prefix: "PLIN - ", name: "Plin") }
        return nil
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_PE"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
