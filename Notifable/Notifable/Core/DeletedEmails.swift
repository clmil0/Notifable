import Foundation

/// Los correos cuyos gastos el usuario borró a propósito.
///
/// `pendingRecoveryIDs` hace dos trabajos: es la lista que la lectura del
/// correo se salta (`GmailSyncService.processMessages`) y la que «Recuperar»
/// trae de vuelta. Antes, contestar «No» a la oferta de recuperar **borraba**
/// la lista y leía el rango a continuación: justo lo borrado volvía a entrar.
///
/// Ahora «No» deja la lista intacta y sólo anota que ya se preguntó por esos
/// correos (`declinedKey`), para no volver a preguntar en cada lectura.
enum DeletedEmails {

    static let key = "pendingRecoveryIDs"
    static let declinedKey = "declinedRecoveryIDs"

    static func all(_ defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    /// Borrados por los que todavía no se preguntó.
    static func undecided(_ defaults: UserDefaults = .standard) -> [String] {
        let declined = Set(defaults.stringArray(forKey: declinedKey) ?? [])
        return all(defaults).filter { !declined.contains($0) }
    }

    /// «No los recuperes»: siguen borrados y la pregunta no vuelve por ellos.
    static func decline(_ defaults: UserDefaults = .standard) {
        defaults.set(all(defaults), forKey: declinedKey)
    }

    /// Tras recuperarlos ya no queda nada que saltar ni por qué preguntar.
    static func clear(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: declinedKey)
    }
}
