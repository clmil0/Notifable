import Foundation
import LocalAuthentication
import SwiftUI

/// Bloqueo de la app con Face ID / Touch ID.
///
/// Lo que protege: la app enseña sueldo, deudas, comercios y en qué se va el
/// dinero. Con el teléfono desbloqueado en la mano de otro, todo eso está a un
/// toque. El bloqueo no cifra nada —los datos siguen protegidos por el cifrado
/// del propio iPhone—; lo que hace es poner una puerta delante de la pantalla.
///
/// Dos decisiones que importan:
/// - Se evalúa `.deviceOwnerAuthentication`, no
///   `.deviceOwnerAuthenticationWithBiometrics`: si Face ID falla (mascarilla,
///   gafas de sol, tres intentos) iOS ofrece el código del teléfono. Con la
///   variante sólo-biométrica el usuario se quedaría fuera de sus propios datos
///   sin salida, y la única forma de recuperarlos sería reinstalar.
/// - Activarlo exige autenticarse **antes**: así nadie deja el bloqueo puesto
///   en un teléfono cuyo Face ID no reconoce a su dueño.
@MainActor
final class AppLock: ObservableObject {

    static let shared = AppLock()

    static let enabledKey = "appLockEnabled"
    static let graceKey = "appLockGraceSeconds"

    /// Cuánto puede estar la app en segundo plano sin volver a pedir la cara.
    /// Sin margen, cada vez que se sale a copiar un dato del banco y se vuelve
    /// hay que autenticarse otra vez, y el ajuste acaba desactivado.
    enum Grace: Int, CaseIterable, Identifiable {
        case immediately = 0
        case oneMinute = 60
        case fiveMinutes = 300

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .immediately: return "Enseguida"
            case .oneMinute: return "Tras 1 minuto"
            case .fiveMinutes: return "Tras 5 minutos"
            }
        }
    }

    /// `true` mientras la pantalla de bloqueo debe tapar la app.
    @Published private(set) var isLocked: Bool
    /// Motivo del último intento fallido, para poder decirlo en pantalla.
    @Published private(set) var lastError: String?

    /// El propio diálogo de Face ID manda la escena a `.inactive`. Sin esta
    /// marca, salir de él volvería a bloquear la app y el desbloqueo no
    /// terminaría nunca.
    private var isAuthenticating = false
    private var leftForegroundAt: Date?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Si el ajuste está puesto, la app arranca bloqueada. Nunca al revés:
        // desbloquear es siempre una acción explícita.
        self.isLocked = defaults.bool(forKey: Self.enabledKey)
    }

    var isEnabled: Bool { defaults.bool(forKey: Self.enabledKey) }

    var grace: Grace {
        Grace(rawValue: defaults.integer(forKey: Self.graceKey)) ?? .immediately
    }

    // MARK: - Disponibilidad

    /// Qué biometría tiene este teléfono. `.none` si no hay ninguna disponible
    /// —sin sensor, sin códigos registrados o con Face ID denegado a la app—.
    static var biometry: LABiometryType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                        error: &error) else { return .none }
        return context.biometryType
    }

    /// `false` en un teléfono sin código: ahí no hay nada con qué desbloquear,
    /// así que el ajuste ni se ofrece.
    static var canLock: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// "Face ID", "Touch ID"… El nombre real, no uno inventado: el usuario tiene
    /// que reconocer en el ajuste lo mismo que le pedirá el sistema.
    static var biometryName: String {
        switch biometry {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "el código del iPhone"
        }
    }

    static var biometryIcon: String {
        switch biometry {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "lock.fill"
        }
    }

    // MARK: - Activar y desactivar

    /// Enciende el bloqueo, pero sólo si el usuario se autentica primero.
    /// Devuelve `nil` si quedó activado, o el motivo si no.
    func enable() async -> String? {
        if let error = await authenticate(reason: "Confirma que eres tú para activar el bloqueo.") {
            return error
        }
        defaults.set(true, forKey: Self.enabledKey)
        isLocked = false
        objectWillChange.send()
        return nil
    }

    /// Apagarlo también se autentica: si no, a quien tenga el teléfono en la
    /// mano le bastaría con entrar a Ajustes para quitar la puerta.
    func disable() async -> String? {
        if let error = await authenticate(reason: "Confirma que eres tú para quitar el bloqueo.") {
            return error
        }
        defaults.set(false, forKey: Self.enabledKey)
        isLocked = false
        objectWillChange.send()
        return nil
    }

    func setGrace(_ value: Grace) {
        defaults.set(value.rawValue, forKey: Self.graceKey)
        objectWillChange.send()
    }

    // MARK: - Bloquear y desbloquear

    /// El intento de desbloqueo de la pantalla de bloqueo.
    func unlock() async {
        guard isLocked else { return }
        lastError = await authenticate(reason: "Desbloquea AgruPay para ver tus movimientos.")
        if lastError == nil {
            isLocked = false
            leftForegroundAt = nil
        }
    }

    /// La app deja de estar activa. Se bloquea **aquí** y no al volver, porque
    /// esta es la pantalla que iOS fotografía para el conmutador de apps: si se
    /// esperara al regreso, el saldo quedaría a la vista en la vista de tarjetas.
    func sceneWillResignActive() {
        guard isEnabled, !isAuthenticating, !isLocked else { return }
        leftForegroundAt = Date()
        isLocked = true
    }

    /// La app vuelve. Si el margen elegido todavía no se ha agotado, se
    /// devuelve el acceso sin preguntar nada.
    func sceneDidBecomeActive() {
        guard isEnabled, !isAuthenticating, isLocked else { return }
        guard grace != .immediately, let left = leftForegroundAt else { return }
        if Date().timeIntervalSince(left) < Double(grace.rawValue) {
            isLocked = false
            leftForegroundAt = nil
        }
    }

    // MARK: - LocalAuthentication

    /// `nil` si el usuario se autenticó; si no, el motivo en lenguaje llano.
    private func authenticate(reason: String) async -> String? {
        guard Self.canLock else {
            return "Este iPhone no tiene código ni biometría configurados."
        }

        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedCancelTitle = "Cancelar"

        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                      localizedReason: reason)
            return ok ? nil : "No se pudo verificar tu identidad."
        } catch {
            return Self.describe(error)
        }
    }

    private static func describe(_ error: Error) -> String {
        guard let laError = error as? LAError else { return error.localizedDescription }
        switch laError.code {
        case .userCancel, .appCancel, .systemCancel:
            return "Verificación cancelada."
        case .userFallback:
            return "Elige «Usar código» para continuar."
        case .biometryLockout:
            return "Demasiados intentos. Desbloquea el iPhone con su código y vuelve a intentarlo."
        case .biometryNotAvailable:
            return biometryName + " no está disponible para AgruPay. Puedes darle permiso en Ajustes de iOS."
        case .biometryNotEnrolled:
            return "No hay " + biometryName + " configurado en este iPhone."
        case .passcodeNotSet:
            return "Este iPhone no tiene código configurado."
        default:
            return "No se pudo verificar tu identidad."
        }
    }
}
