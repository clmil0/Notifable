import Foundation
import LocalAuthentication
import UIKit

/// Por qué no se pudo desbloquear, con lo que hay que hacer para salir.
///
/// Antes esto era un `String` suelto y la pantalla sólo podía enseñarlo en
/// rojo. Un mensaje no es una salida: "Face ID quedó bloqueado" deja al usuario
/// mirando sus datos desde fuera sin saber que se arregla desbloqueando el
/// iPhone con su código. Cada caso trae ahora sus pasos y sus dos botones, así
/// que la pantalla puede llevarle de la mano en vez de informarle del problema.
enum AppLockFailure: Equatable {

    /// El usuario cerró el diálogo. No es un error: es un "ahora no".
    case cancelled
    /// La biometría funcionó, pero no reconoció al usuario. Tampoco es un
    /// error que arreglar: es volver a mirar el teléfono.
    case notRecognized
    /// El iPhone no tiene biometría configurada.
    case notEnrolled
    /// Hay biometría, pero esta app no tiene permiso.
    case notAvailable
    /// iOS desactivó la biometría tras varios intentos fallidos.
    case lockout
    /// El iPhone no tiene ni código: no hay con qué desbloquear.
    case noPasscode
    /// Cualquier otra cosa, con el texto que dio el sistema.
    case other(String)

    // MARK: - Qué pantalla toca

    /// `true` si hay **algo que arreglar fuera de la app** y por tanto toca la
    /// pantalla guiada (1b): titular con el motivo, pasos numerados y el botón
    /// que de verdad desbloquea.
    ///
    /// `false` cuando la biometría está configurada y disponible y sencillamente
    /// no se completó la verificación —cancelaste, no te reconoció, o el
    /// sistema devolvió un fallo suelto sin motivo concreto (`.other`)—. Ahí no
    /// hay nada que explicar ni ningún ajuste que tocar: lo único que hay que
    /// hacer es volver a mirar el teléfono, así que se sigue en la pantalla en
    /// reposo (2b), que ya dice "Toca para entrar". Sacar los tres pasos y dos
    /// botones para decir "vuelve a mirar" convierte un tropiezo de un segundo
    /// en un incidente. `.other` no tiene pasos de verdad que dar —"vuelve a
    /// intentarlo" no es un ajuste externo—, así que mandarlo a la guiada sólo
    /// cambiaba "Toca para entrar" por una tarjeta de error sin salida real.
    var needsGuidance: Bool {
        switch self {
        case .cancelled, .notRecognized, .other:
            return false
        case .notEnrolled, .notAvailable, .lockout, .noPasscode:
            return true
        }
    }

    /// Lo que la pantalla en reposo pone bajo "Toca para entrar" cuando este
    /// fallo no merece la pantalla guiada.
    var idleSubtitle: String {
        switch self {
        case .cancelled: return "Cancelaste la verificación. Toca el sello y vuelve a mirar."
        case .notRecognized: return "\(AppLock.biometryName) no te reconoció. Toca el sello y vuelve a mirar."
        case .other: return "\(AppLock.biometryName) no respondió. Toca el sello y vuelve a intentar."
        default: return body
        }
    }

    // MARK: - Qué se enseña

    var icon: String {
        switch self {
        case .cancelled, .notRecognized: return "arrow.counterclockwise"
        case .notEnrolled, .notAvailable: return "gearshape.fill"
        case .lockout: return "lock.slash.fill"
        case .noPasscode: return "exclamationmark.triangle.fill"
        case .other: return "exclamationmark.circle.fill"
        }
    }

    enum Tone { case neutral, warning, error }

    var tone: Tone {
        switch self {
        case .cancelled, .notRecognized: return .neutral
        case .notEnrolled, .notAvailable: return .warning
        case .lockout, .noPasscode, .other: return .error
        }
    }

    var headline: String {
        switch self {
        case .cancelled: return "Cancelaste la verificación"
        case .notRecognized: return "\(AppLock.biometryName) no te reconoció"
        case .notEnrolled: return "Este iPhone no tiene \(AppLock.biometryName) configurado"
        case .notAvailable: return "AgruPay no tiene permiso de \(AppLock.biometryName)"
        case .lockout: return "\(AppLock.biometryName) quedó bloqueado"
        case .noPasscode: return "No hay con qué desbloquear"
        case .other: return "No se pudo verificar tu identidad"
        }
    }

    var body: String {
        switch self {
        case .cancelled:
            return "No pasó nada: AgruPay sigue cerrada. Intenta de nuevo o entra con el código del iPhone."
        case .notRecognized:
            return "Vuelve a mirar el iPhone de frente, o entra con su código."
        case .notEnrolled:
            return "Puedes entrar con el código del iPhone ahora mismo, o configurarlo para que la próxima vez sea con la cara."
        case .notAvailable:
            return "\(AppLock.biometryName) funciona en este iPhone, pero no para esta app. El permiso se devuelve en Ajustes de iOS."
        case .lockout:
            return "iOS lo desactiva tras varios intentos fallidos. Se reactiva al desbloquear el iPhone con su código."
        case .noPasscode:
            return "El bloqueo de AgruPay depende del código del iPhone, y este no tiene ninguno."
        case .other(let message):
            return message
        }
    }

    var steps: [String] {
        switch self {
        case .cancelled, .notRecognized:
            return ["Toca «Intentar con \(AppLock.biometryName)»",
                    "Mira tu iPhone de frente",
                    "O entra con el código"]
        case .notEnrolled:
            return ["Abre Ajustes de iOS",
                    "Entra en «\(AppLock.biometryName) y código»",
                    "Configúralo y vuelve a AgruPay"]
        case .notAvailable:
            return ["Abre Ajustes de iOS → AgruPay",
                    "Activa \(AppLock.biometryName)",
                    "Vuelve aquí y desbloquea"]
        case .lockout:
            return ["Bloquea el iPhone",
                    "Desbloquéalo escribiendo su código",
                    "Vuelve a AgruPay"]
        case .noPasscode:
            return ["Abre Ajustes de iOS → \(AppLock.biometryName) y código",
                    "Activa un código de desbloqueo",
                    "Vuelve a AgruPay"]
        case .other:
            return ["Vuelve a intentarlo",
                    "Si sigue igual, entra con el código del iPhone"]
        }
    }

    /// Lo que un botón hace de verdad. La pantalla no decide: sólo dibuja.
    enum Action: Equatable {
        case retryBiometrics
        case usePasscode
        case openSettings
        /// Sólo cuando no hay código en el iPhone: sin él, autenticarse para
        /// quitar el bloqueo es imposible y el usuario quedaría encerrado.
        case turnOffLock
    }

    var primary: (label: String, action: Action) {
        switch self {
        case .cancelled, .notRecognized:
            return ("Intentar con \(AppLock.biometryName)", .retryBiometrics)
        case .notEnrolled:  return ("Entrar con el código del iPhone", .usePasscode)
        case .notAvailable: return ("Abrir Ajustes de iOS", .openSettings)
        case .lockout:      return ("Entrar con el código del iPhone", .usePasscode)
        case .noPasscode:   return ("Abrir Ajustes de iOS", .openSettings)
        case .other:        return ("Volver a intentar", .retryBiometrics)
        }
    }

    var secondary: (label: String, action: Action)? {
        switch self {
        case .cancelled, .notRecognized:
            return ("Usar código del iPhone", .usePasscode)
        case .notEnrolled:  return ("Abrir Ajustes de iOS", .openSettings)
        case .notAvailable: return ("Usar código del iPhone", .usePasscode)
        // El diseño proponía "Cerrar AgruPay": iOS no deja que una app se
        // cierre a sí misma, y fingirlo sería peor. Reintentar es lo único
        // honesto que queda aquí.
        case .lockout:      return ("Volver a intentar", .retryBiometrics)
        case .noPasscode:   return ("Desactivar el bloqueo", .turnOffLock)
        case .other:        return ("Usar código del iPhone", .usePasscode)
        }
    }

    // MARK: - De dónde sale

    /// Traduce el error de `LocalAuthentication`. Cancelar no llega aquí como
    /// fallo del sistema sino como decisión del usuario, y por eso tiene su
    /// propio caso en vez de mezclarse con los errores de verdad.
    static func from(_ error: Error) -> AppLockFailure {
        guard let laError = error as? LAError else {
            return .other(error.localizedDescription)
        }
        switch laError.code {
        case .userCancel, .appCancel, .systemCancel, .userFallback:
            return .cancelled
        case .authenticationFailed:
            return .notRecognized
        case .biometryNotEnrolled:
            return .notEnrolled
        case .biometryNotAvailable:
            return .notAvailable
        case .biometryLockout:
            return .lockout
        case .passcodeNotSet:
            return .noPasscode
        default:
            return .other("No se pudo verificar tu identidad.")
        }
    }
}
