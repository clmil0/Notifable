import Foundation
import SwiftData

/// El único `ModelContainer` del proceso.
///
/// Lo comparten la app y los intents de Siri. Antes `LogExpenseIntent` abría
/// el suyo con `ModelContainer(for: Expense.self)`: un esquema con un solo
/// modelo sobre el mismo archivo que la app abre con seis. Los cambios de un
/// contenedor no llegaban a las vistas del otro, y abrir el archivo con un
/// esquema parcial se arriesga a un error de migración.
///
/// El archivo vive en el contenedor privado de la app — **no** en el App
/// Group. Los widgets sólo ven `WidgetSnapshot`.
///
/// Hasta la versión 3.0.x no era así: con un único App Group en los
/// entitlements, `ModelConfiguration` sin URL guarda la base **en el App
/// Group**, al alcance de la extensión de widgets. `moveOutOfAppGroupIfNeeded`
/// la trae de vuelta una sola vez.
enum AppModelContainer {

    static let schema = Schema([
        Expense.self,
        Income.self,
        RecurringExpense.self,
        QuickExpense.self,
        CachedFriend.self,
        CachedFriendShare.self
    ])

    static let shared: ModelContainer = {
        let url = storeURL()
        // Migración aditiva: SwiftData crea las tablas nuevas sin tocar las
        // existentes.
        let configuration = ModelConfiguration(schema: schema, url: url)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("No se pudo crear el ModelContainer: \(error)")
        }
    }()

    static let storeName = "default.store"
    /// El `.store` y los dos archivos del registro de escritura de SQLite:
    /// sin el `-wal` se perderían los últimos guardados.
    static let storeSuffixes = ["", "-wal", "-shm"]

    private static var privateStoreURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(storeName)
    }

    private static var groupStoreURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshotStore.appGroupID)?
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(storeName)
    }

    /// La base privada; si la mudanza desde el App Group no se pudo hacer
    /// entera, la del App Group, para no arrancar con la base vacía.
    private static func storeURL() -> URL {
        let fm = FileManager.default
        let target = privateStoreURL
        try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let legacy = groupStoreURL else { return target }
        return moveOutOfAppGroupIfNeeded(from: legacy, to: target, fileManager: fm) ? target : legacy
    }

    /// Copia primero los tres archivos y sólo con los tres copiados borra los
    /// del App Group. Si falla a medias, deshace las copias y devuelve `false`:
    /// quien llama sigue con la base de antes y lo reintenta el próximo arranque.
    ///
    /// Antes de abrir ningún `ModelContainer`, así que nadie tiene la base
    /// abierta mientras se mueve.
    static func moveOutOfAppGroupIfNeeded(from legacy: URL, to target: URL,
                                          fileManager fm: FileManager = .default) -> Bool {
        func url(_ base: URL, _ suffix: String) -> URL {
            base.deletingLastPathComponent().appendingPathComponent(base.lastPathComponent + suffix)
        }
        // Ya mudada, o nunca hubo nada en el App Group.
        guard fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: target.path) else { return true }

        var copied: [URL] = []
        do {
            for suffix in storeSuffixes where fm.fileExists(atPath: url(legacy, suffix).path) {
                let destination = url(target, suffix)
                try fm.copyItem(at: url(legacy, suffix), to: destination)
                copied.append(destination)
            }
        } catch {
            for file in copied { try? fm.removeItem(at: file) }
            Diagnostics.shared.log("Base: no se pudo sacar del App Group (\(error)); se sigue usando allí")
            return false
        }
        for suffix in storeSuffixes { try? fm.removeItem(at: url(legacy, suffix)) }
        Diagnostics.shared.log("Base: movida del App Group al contenedor privado de la app")
        return true
    }
}
