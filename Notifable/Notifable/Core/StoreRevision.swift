import Foundation
import SwiftData

/// Cuántas veces se guardaron datos tuyos en esta sesión.
///
/// Sirve para saber si algo cambió desde la última vez que se leyó el
/// historial entero: al volver al dashboard desde otra pantalla, si nadie
/// guardó nada, releerlo es trabajo tirado en el hilo principal justo cuando
/// se empieza a deslizar. No cuenta lo que sólo tocó las cachés de amigos
/// (`SocialCacheSave`).
enum StoreRevision {
    private static let lock = NSLock()
    private static var count = 0

    private static let observer: NSObjectProtocol = NotificationCenter.default.addObserver(
        forName: ModelContext.didSave, object: nil, queue: nil
    ) { note in
        guard !SocialCacheSave.isCacheOnly(note) else { return }
        lock.withLock { count += 1 }
    }

    /// Se llama al arrancar, antes de que nada guarde.
    static func start() { _ = observer }

    static var current: Int { lock.withLock { count } }
}
