import Foundation

/// Todas las preferencias del usuario que viven en `UserDefaults`, en una sola
/// lista.
///
/// Antes cada ajuste nuevo exigía tres cambios coordinados —una columna en
/// Supabase, un campo en el payload y una línea en `applySettings`— y bastaba
/// olvidar uno para que ese ajuste se perdiera en silencio al cambiar de
/// teléfono. Aquí se declara **una vez**, en `syncable`, y viaja en un único
/// `jsonb`.
///
/// Lo que NO entra: tokens y credenciales (que son de este dispositivo), la
/// caché de correos leídos (se rehace sola), los filtros de pantalla (son de
/// este momento, no una preferencia) y el estado del onboarding (quien estrena
/// un teléfono merece verlo).
enum AppPreferences {

    /// Una preferencia sincronizable. El tipo importa porque `UserDefaults`
    /// distingue `Bool` de `Int` y restaurar un booleano como número lo
    /// silenciaría.
    enum Kind {
        case bool, int, double, string
    }

    struct Entry {
        let key: String
        let kind: Kind
        /// Para qué sirve — sale en el documento de qué se respalda.
        let note: String
    }

    static let syncable: [Entry] = [
        // Apariencia
        .init(key: "appAppearance", kind: .string, note: "Tema: claro, oscuro o automático"),
        .init(key: "appAccentColor", kind: .string, note: "Color de acento"),
        .init(key: "appTextSize", kind: .string, note: "Tamaño de letra"),
        .init(key: "circularReveal", kind: .bool, note: "Animación al cambiar de tema"),

        // Presupuesto
        .init(key: "monthlyBudget", kind: .double, note: "Presupuesto mensual"),
        .init(key: "budgetEnabled", kind: .bool, note: "Presupuesto activo"),
        .init(key: "trackIncome", kind: .bool, note: "Contar ingresos en el balance"),

        // Bancos que se leen
        .init(key: "syncBCP", kind: .bool, note: "Leer avisos del BCP"),
        .init(key: "syncBBVA", kind: .bool, note: "Leer avisos del BBVA"),
        .init(key: "syncYape", kind: .bool, note: "Leer avisos de Yape"),
        .init(key: "syncInterbank", kind: .bool, note: "Leer avisos de Interbank"),
        .init(key: "syncScotiabank", kind: .bool, note: "Leer avisos de Scotiabank"),

        // Notificaciones
        .init(key: "notificationsEnabled", kind: .bool, note: "Aviso de presupuesto"),
        .init(key: "remindRecurring", kind: .bool, note: "Aviso de recurrentes por confirmar"),
        .init(key: "categoryLimitAlerts", kind: .bool, note: "Aviso al pasar el límite de una categoría"),
        .init(key: "debtReminderEnabled", kind: .bool, note: "Aviso de cobros pendientes"),
        .init(key: "debtReminderHour", kind: .int, note: "Hora del aviso de cobros"),
        .init(key: "debtReminderMinute", kind: .int, note: "Minuto del aviso de cobros"),
        .init(key: "debtNotificationFrequency", kind: .string, note: "Cada cuánto avisa de los cobros"),

        // Lectura del correo
        .init(key: "readPeriodMonths", kind: .int, note: "Desde cuándo leer el correo"),

        // Preferencias de vista que sí son una elección duradera
        .init(key: "categoriesSegment", kind: .string, note: "Pestaña por defecto en Categorías")
    ]

    // MARK: - Fotografía

    /// Sólo las claves que el usuario ha tocado de verdad: mandar los valores
    /// por defecto de todo obligaría a que el otro teléfono los adopte, y un
    /// ajuste que nunca se cambió no es una preferencia.
    static func snapshot(_ defaults: UserDefaults = .standard) -> [String: AnyCodableValue] {
        var result: [String: AnyCodableValue] = [:]
        for entry in syncable {
            guard let raw = defaults.object(forKey: entry.key) else { continue }
            switch entry.kind {
            case .bool:   if let v = raw as? Bool { result[entry.key] = .bool(v) }
            case .int:    if let v = raw as? Int { result[entry.key] = .int(v) }
            case .double: if let v = raw as? Double { result[entry.key] = .double(v) }
            case .string: if let v = raw as? String { result[entry.key] = .string(v) }
            }
        }
        return result
    }

    /// Escribe de vuelta sólo lo conocido: una clave que no esté en la lista
    /// —de una versión más nueva, por ejemplo— se ignora en vez de acabar en
    /// `UserDefaults` con un tipo que nadie sabe leer.
    static func apply(_ values: [String: AnyCodableValue], _ defaults: UserDefaults = .standard) {
        let byKey = Dictionary(uniqueKeysWithValues: syncable.map { ($0.key, $0) })
        for (key, value) in values {
            guard let entry = byKey[key] else { continue }
            switch (entry.kind, value) {
            case (.bool, .bool(let v)):     defaults.set(v, forKey: key)
            case (.int, .int(let v)):       defaults.set(v, forKey: key)
            case (.double, .double(let v)): defaults.set(v, forKey: key)
            case (.double, .int(let v)):    defaults.set(Double(v), forKey: key)
            case (.string, .string(let v)): defaults.set(v, forKey: key)
            default: continue
            }
        }
    }
}

/// Un valor de preferencia: sólo los cuatro tipos que `UserDefaults` guarda
/// bien y que Postgres entiende como `jsonb` sin inventarse nada.
enum AnyCodableValue: Codable, Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // El orden importa: en JSON `true` también decodifica como número en
        // algunas implementaciones, así que el booleano va primero.
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(Int.self) { self = .int(v); return }
        if let v = try? container.decode(Double.self) { self = .double(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        throw DecodingError.dataCorruptedError(in: container,
                                               debugDescription: "Preferencia de tipo desconocido")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let v):   try container.encode(v)
        case .int(let v):    try container.encode(v)
        case .double(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        }
    }

    /// Para armar el cuerpo del RPC sin volver a serializar.
    var jsonValue: Any {
        switch self {
        case .bool(let v):   return v
        case .int(let v):    return v
        case .double(let v): return v
        case .string(let v): return v
        }
    }
}
