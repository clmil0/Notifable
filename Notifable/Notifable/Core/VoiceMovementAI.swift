import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Entiende una frase dictada con el modelo de Apple Intelligence que viene en
/// el iPhone (iOS 26+). Gratis, sin red y sin API key.
///
/// **Las reglas siguen mandando en el monto.** El modelo es bueno eligiendo
/// título y categoría, pero puede inventar un número; por eso un monto suyo
/// sólo se acepta si es uno de los que `VoiceMovementParser` encuentra en la
/// frase. Sin Apple Intelligence —o si el modelo falla— el resultado es el de
/// las reglas tal cual.
enum VoiceMovementAI {

    /// Hay modelo disponible en este equipo, ahora mismo.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    static func parse(_ text: String, categories: [String], now: Date = Date()) async -> [VoiceMovement] {
        let rules = VoiceMovementParser.parse(text, now: now)

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), isAvailable,
           let generated = try? await generate(text, categories: categories) {
            return merge(generated, rules: rules, text: text, categories: categories, now: now)
        }
        #endif
        return rules
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func generate(_ text: String, categories: [String]) async throws -> [DictatedMovement] {
        let instructions = """
        Extraes movimientos de dinero de frases dictadas en español peruano para una app de gastos.
        La gente habla como piensa: da contexto, divaga y se corrige antes de llegar al gasto. Ignora
        el relato y quédate sólo con el dinero que realmente se gastó o se recibió. Si se corrige
        («iba a gastar 50, pero al final fueron 30»), vale el último monto. Una historia con un solo
        pago es un solo movimiento.
        Moneda por defecto: soles (PEN). «lucas» son soles; «dólares» o «cocos» es USD.
        Un gasto es algo que se pagó o compró; un ingreso es dinero recibido (me pagaron, cobré, sueldo).
        El título es lo comprado, el lugar o el origen del dinero, de 1 a 3 palabras, sin verbo, sin artículo y sin monto.
        Si el monto no se dijo, déjalo vacío: nunca lo inventes.
        La categoría de un gasto debe ser exactamente una de: \(categories.joined(separator: ", ")). Si ninguna encaja, déjala vacía.
        """
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: "Frase: \(text)", generating: DictatedMovements.self)
        return response.content.items
    }

    @available(iOS 26.0, *)
    private static func merge(_ generated: [DictatedMovement],
                              rules: [VoiceMovement],
                              text: String,
                              categories: [String],
                              now: Date) -> [VoiceMovement] {
        guard !generated.isEmpty else { return rules }
        let spoken = VoiceMovementParser.allAmounts(in: text)

        return generated.enumerated().map { index, item in
            var result = index < rules.count ? rules[index] : VoiceMovement(date: now)
            result.kind = item.kind == .ingreso ? .ingreso : .gasto

            if result.amount == nil, let amount = item.amount,
               spoken.contains(where: { Money.cents($0) == Money.cents(amount) }) {
                result.amount = amount
            }
            if item.currency.uppercased() == "USD" { result.currency = "USD" }

            if let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                result.title = title.capitalizedFirst
            }
            if result.kind == .gasto,
               let category = item.category,
               let match = categories.first(where: { $0.caseInsensitiveCompare(category) == .orderedSame }) {
                // Una regla del usuario pesa más que la opinión del modelo.
                let rule = result.title.flatMap { MerchantRules.category(for: $0) }
                result.category = rule ?? match
            }
            return result
        }
    }
    #endif
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
enum DictatedKind {
    case gasto
    case ingreso
}

@available(iOS 26.0, *)
@Generable
struct DictatedMovement {
    @Guide(description: "gasto si se pagó o compró algo; ingreso si se recibió dinero")
    var kind: DictatedKind

    @Guide(description: "El monto como número, sin moneda. Vacío si no se dijo")
    var amount: Double?

    @Guide(description: "PEN para soles, USD para dólares")
    var currency: String

    @Guide(description: "Qué se compró o de dónde vino el dinero, de 1 a 3 palabras. Ej.: Almuerzo, Taxi, Freelance")
    var title: String?

    @Guide(description: "Categoría del gasto, exactamente una de la lista dada, o vacío")
    var category: String?
}

@available(iOS 26.0, *)
@Generable
struct DictatedMovements {
    @Guide(description: "Cada movimiento de dinero mencionado, en el orden en que se dijo")
    var items: [DictatedMovement]
}
#endif
