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
/// Orden de resolución: regla exacta → regla por raíz del nombre (no para
/// Yape/Plin/transferencias) → diccionario de comercios conocidos.
///
/// Yape, Plin y las transferencias bancarias ("YAPE - ", "PLIN - ", "BBVA - ")
/// llevan el nombre de la **persona** destinataria como comercio, no el de un
/// negocio: no se repite de forma predecible ni dice nada de la categoría del
/// gasto. Por eso sólo cuentan para la regla 1 (ya clasificaste exactamente a
/// esa persona antes) — ni la raíz del nombre ni "la mayoría de tus Yapes son
/// Comida" son señales confiables ahí, así que esta última se quitó del todo.
enum SuggestionEngine {

    /// Diccionario de comercios frecuentes en Perú. Sólo se usa como último
    /// recurso, y siempre pidiendo confirmación.
    ///
    /// Marcas con posesivo en español ("McDonald's", "Domino's", "Norky's")
    /// van sin el "'s": los parsers de banco no siempre conservan el
    /// apóstrofo, y la raíz sin él sigue apareciendo dentro del nombre completo
    /// tenga o no comilla ("mcdonald" está contenido en "mcdonald's" y en
    /// "mcdonalds" por igual).
    private static let keywords: [(tokens: [String], category: String)] = [
        (["metro", "tottus", "plaza vea", "plazavea", "vivanda", "wong", "makro", "mass", "mass xtra", "oxxo",
          "tambo", "tambo+", "economax", "holi", "listo", "viva", "repshop", "petro market", "bodega", "bodeguita",
          "minimarket", "mini market", "supermercado", "hipermercado", "autoservicio", "mercado", "mercadillo",
          "abarrotes", "abarrotería", "despensa", "provisiones", "canasta familiar", "delicatessen", "verdulería",
          "frutería", "carnicería", "pescadería", "granos y abarrotes", "plaza vea express", "grocery", "market",
          "superette", "tienda de conveniencia", "cooperativa de consumo", "canasta basica", "dia a dia",
          "el chinito", "provincial market", "el super"], "Supermercado"),
        (["rappi", "pedidosya", "didi food", "uber eats", "glovo", "kfc", "bembos", "starbucks", "papa john",
          "pizza", "pizza hut", "burger", "burger king", "mcdonald", "norky", "china wok", "chinawok", "popeye",
          "roky", "pardos chicken", "la lucha", "dunkin", "cinnabon", "subway", "domino", "telepizza", "tanta",
          "la mar", "chifa", "pollería", "cevichería", "anticuchos", "sanguchería", "menu", "menú", "restaurante",
          "almuerzo", "cena", "desayuno", "comida rápida", "hamburguesa", "sushi", "nikkei", "panadería",
          "pastelería", "heladería", "helados", "cafe", "café", "cafeteria", "cafetería", "bar", "cerveza",
          "discoteca", "licorería", "taco bell"], "Comida"),
        (["uber", "cabify", "beat", "didi", "indriver", "yango", "taxi", "taxi directo", "taxi satelital",
          "metropolitano", "corredor", "tren", "línea 1", "tren eléctrico", "primax", "repsol", "petroperu",
          "petroperú", "pecsa", "grifo", "gasolina", "combustible", "peaje", "estacionamiento", "parking",
          "cochera", "los portales", "taller", "mecánico", "mantenimiento auto", "cruz del sur", "oltursa",
          "movil tours", "movil bus", "tepsa", "flores", "civa", "cavassa", "bus", "autobús", "pasajes",
          "terminal terrestre", "aeropuerto", "latam", "sky airline", "jetsmart", "avianca", "vuelos", "avión",
          "aerolínea", "soat", "revisión técnica", "llantas", "neumáticos"], "Transporte"),
        (["netflix", "spotify", "disney", "hbo", "max", "prime video", "amazon prime", "youtube premium",
          "apple tv", "crunchyroll", "cineplanet", "cinemark", "cinestar", "teleticket", "joinnus", "tuentrada",
          "atrapalo", "cine", "película", "películas", "teatro", "concierto", "entradas", "museo", "exposición",
          "parque de diversiones", "playstation", "xbox", "nintendo", "steam", "epic games", "riot games",
          "gaming", "videojuegos", "juegos", "twitch", "discord nitro", "paramount+", "star+", "vix",
          "claro video", "movistar play", "directv go", "deezer", "tidal", "boliche", "karaoke", "feria",
          "circo", "zoológico", "acuario", "escape room"], "Entretenimiento"),
        (["movistar", "claro", "entel", "bitel", "win", "wow", "luz del sur", "enel", "sedapal", "calidda",
          "hidrandina", "seal", "electro sur", "electrocentro", "electronoroeste", "agua", "luz", "gas",
          "internet", "teléfono", "cable", "directv", "recarga", "plan móvil", "rimac", "pacifico", "mapfre",
          "la positiva", "eps", "seguro", "seguros", "póliza", "banco", "comisión bancaria",
          "mantenimiento de cuenta", "membresía", "sunat", "tributos", "arbitrios", "predial", "multas",
          "municipalidad", "sedapar", "sedalib", "epsel", "seda chimbote", "telefonica", "fibra óptica", "wifi",
          "plan postpago", "plan prepago", "recibo de luz", "recibo de agua"], "Servicios"),
        (["inkafarma", "mifarma", "boticas y salud", "botica", "farmacia", "arcángel", "albis", "clínica",
          "hospital", "clínica anglo americana", "clínica ricardo palma", "clínica internacional",
          "clínica san pablo", "clínica delgado", "auna", "essalud", "minsa", "doctor", "médico", "dentista",
          "odontólogo", "odontología", "terapia", "psicólogo", "psicología", "oftalmólogo", "pediatra",
          "laboratorio", "análisis clínicos", "examenes médicos", "medicina", "pastillas", "receta", "óptica",
          "lentes", "vacuna", "vacunación", "consulta médica", "emergencia médica", "ambulancia",
          "fisioterapia", "nutricionista", "dermatólogo", "ginecólogo", "cardiólogo", "traumatólogo",
          "farmacia universal", "mi farmacia", "boticas torres de limatambo", "fasa", "inca farma",
          "óptica gmo"], "Salud"),
        (["falabella", "saga falabella", "ripley", "oechsle", "sodimac", "promart", "maestro", "hiraoka",
          "la curacao", "curacao", "tiendas efe", "carsa", "elektra", "zara", "h&m", "adidas", "nike", "puma",
          "forever 21", "topitop", "platanitos", "payless", "ropa", "moda", "zapatos", "zapatillas", "calzado",
          "joyería", "relojes", "accesorios", "tecnología", "electrónica", "celular", "smartphone", "iphone",
          "samsung", "xiaomi", "laptop", "computadora", "muebles", "decoración", "ferretería", "herramientas",
          "regalos", "juguetería", "juguetes", "librería", "papelería", "cosméticos", "perfumería",
          "tienda por departamento", "mall", "centro comercial"], "Compras")
    ]

    /// - Parameters:
    ///   - merchant: nombre crudo, tal como llega del parser (puede traer "YAPE - ").
    ///   - rules: `merchantCategories` de UserDefaults, [comercio: categoría].
    static func suggest(for merchant: String,
                        rules: [String: String]) -> CategorySuggestion? {

        // 1. Regla exacta ya guardada.
        if let exact = rules[merchant], exact != Accounting.unclassified {
            return CategorySuggestion(category: exact, confidence: 1.0, reason: "Ya tienes una regla para este comercio")
        }

        let clean = normalize(Accounting.displayName(merchant))

        // 2. Misma raíz de nombre: "METRO 0231" contra la regla "Metro". No
        //    aplica a Yape/Plin/transferencias: ahí lo que se repite es un
        //    nombre de persona, no de negocio, y dos personas con nombres
        //    parecidos no son el mismo tipo de gasto.
        if !isPersonToPerson(merchant) {
            for (ruleMerchant, category) in rules where category != Accounting.unclassified {
                guard !isPersonToPerson(ruleMerchant) else { continue }
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
        }

        // 3. Diccionario de comercios conocidos.
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

    /// Yape, Plin y transferencias bancarias: el comercio es el nombre de la
    /// persona destinataria, puesto ahí por el parser correspondiente (ver
    /// `YapeParser`, `BBVAParser.parseBBVATransfer`). Si algún banco más suma
    /// su propio parser de transferencias con otro prefijo, hay que sumarlo
    /// aquí también.
    private static func isPersonToPerson(_ merchant: String) -> Bool {
        merchant.hasPrefix("YAPE - ") || merchant.hasPrefix("PLIN - ") || merchant.hasPrefix("BBVA - ")
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_PE"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
