import Foundation

/// Lectura y escritura del resumen en el contenedor del App Group.
///
/// Un archivo JSON y no `UserDefaults(suiteName:)`: la escritura es atómica
/// (el widget nunca lee medio archivo) y queda claro qué es lo único que se
/// comparte. La base de SwiftData se queda en el contenedor privado de la app.
enum WidgetSnapshotStore {

    static let appGroupID = "group.clmilo.Notifable"
    static let fileName = "widget-snapshot.json"

    /// `nil` si el App Group no está en los entitlements del proceso — el
    /// caso de una firma sin la capacidad. Quien llama degrada a "sin datos".
    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    static func load(from url: URL? = fileURL) -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.schemaVersion == WidgetSnapshot.currentSchema else { return nil }
        return snapshot
    }

    /// Devuelve `true` sólo si el contenido cambió: así quien escribe decide
    /// si vale la pena gastar una recarga de los widgets.
    @discardableResult
    static func save(_ snapshot: WidgetSnapshot, to url: URL? = fileURL) throws -> Bool {
        guard let url else { return false }
        let data = try encode(snapshot)
        if let current = try? Data(contentsOf: url), current == data { return false }
        try data.write(to: url, options: [.atomic])
        return true
    }

    static func encode(_ snapshot: WidgetSnapshot) throws -> Data {
        try encoder.encode(snapshot)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        // Claves ordenadas: el mismo resumen produce los mismos bytes y la
        // comparación de arriba evita recargas inútiles.
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}

/// Nombres de los widgets, compartidos para que la app recargue sólo los que toca.
enum WidgetKinds {
    static let pace = "PaceWidget"
    static let today = "TodayWidget"
    static let categories = "CategoriesWidget"
    static let categoryLimit = "CategoryLimitWidget"
    static let quickAdd = "QuickAddWidget"
    static let monthPanel = "MonthPanelWidget"
}
