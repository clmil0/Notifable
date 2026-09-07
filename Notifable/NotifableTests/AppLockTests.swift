import Testing
import Foundation
import LocalAuthentication
@testable import Notifable

/// Qué pantalla de bloqueo toca en cada caso.
///
/// Esto existe por un error real: la pantalla decidía con `if lastFailure != nil`,
/// así que **cerrar el diálogo de Face ID** —teniéndolo configurado y sin más
/// problema que no haber mirado el teléfono— sacaba la pantalla guiada, con su
/// titular de error, sus tres pasos y sus dos botones. La regla correcta no es
/// "¿falló algo?" sino "¿hay algo que arreglar fuera de la app?".
struct AppLockRoutingTests {

    // MARK: - Se quedan en la pantalla en reposo (2b)

    @Test("Cancelar el diálogo no saca la pantalla guiada")
    func cancelarSeQuedaEnReposo() {
        #expect(AppLockFailure.cancelled.needsGuidance == false)
    }

    @Test("Que la biometría no te reconozca tampoco: es volver a mirar")
    func noReconocidoSeQuedaEnReposo() {
        #expect(AppLockFailure.notRecognized.needsGuidance == false)
    }

    @Test("Las cuatro formas de cerrar el diálogo son el mismo caso")
    func cerrarElDialogo() {
        let codes: [LAError.Code] = [.userCancel, .appCancel, .systemCancel, .userFallback]
        for code in codes {
            let failure = AppLockFailure.from(LAError(code))
            #expect(failure == .cancelled, "\(code) debería ser .cancelled")
            #expect(failure.needsGuidance == false)
        }
    }

    @Test("No reconocer la cara se distingue de un error del sistema")
    func caraNoReconocida() {
        // Antes caía en `.other`, que sí lleva a la pantalla guiada.
        #expect(AppLockFailure.from(LAError(.authenticationFailed)) == .notRecognized)
    }

    // MARK: - Van a la pantalla guiada (1b)

    @Test("Sin Face ID configurado hay que ir a Ajustes: pantalla guiada")
    func sinBiometriaConfigurada() {
        let failure = AppLockFailure.from(LAError(.biometryNotEnrolled))
        #expect(failure == .notEnrolled)
        #expect(failure.needsGuidance)
    }

    @Test("Sin permiso, bloqueado o sin código: los tres necesitan pasos")
    func casosQueNecesitanGuia() {
        let casos: [(LAError.Code, AppLockFailure)] = [
            (.biometryNotAvailable, .notAvailable),
            (.biometryLockout, .lockout),
            (.passcodeNotSet, .noPasscode)
        ]
        for (code, expected) in casos {
            let failure = AppLockFailure.from(LAError(code))
            #expect(failure == expected, "\(code) mal traducido")
            #expect(failure.needsGuidance, "\(expected) debería llevar a la pantalla guiada")
        }
    }

    @Test("Un error desconocido guía: es mejor sobrar que dejar sin salida")
    func desconocidoGuia() {
        #expect(AppLockFailure.other("lo que sea").needsGuidance)
    }

    // MARK: - Que cada caso guiado sepa salir

    @Test("Todo caso guiado trae motivo, pasos y una acción que desbloquea")
    func losCasosGuiadosTienenSalida() {
        let guiados: [AppLockFailure] = [.notEnrolled, .notAvailable, .lockout,
                                         .noPasscode, .other("fallo raro")]
        for failure in guiados {
            #expect(!failure.headline.isEmpty)
            #expect(!failure.body.isEmpty)
            #expect(failure.steps.count >= 2, "\(failure) sin pasos que seguir")
            #expect(!failure.primary.label.isEmpty)
            #expect(failure.secondary != nil, "\(failure) sin segunda salida")
        }
    }

    /// Sin código en el iPhone no se puede autenticar, así que exigir una
    /// verificación para apagar el bloqueo dejaría al dueño encerrado fuera de
    /// sus propios datos para siempre. Ese caso —y sólo ese— ofrece apagarlo.
    @Test("Sin código, la salida es poder desactivar el bloqueo")
    func sinCodigoSePuedeDesactivar() {
        #expect(AppLockFailure.noPasscode.secondary?.action == .turnOffLock)

        let resto: [AppLockFailure] = [.cancelled, .notRecognized, .notEnrolled,
                                       .notAvailable, .lockout]
        for failure in resto {
            #expect(failure.secondary?.action != .turnOffLock,
                    "\(failure) no debería poder apagar el bloqueo sin autenticarse")
            #expect(failure.primary.action != .turnOffLock)
        }
    }

    @Test("Los casos de reposo llevan su propio subtítulo, no el genérico")
    func subtituloDeReposo() {
        #expect(AppLockFailure.cancelled.idleSubtitle.contains("Cancelaste"))
        #expect(AppLockFailure.notRecognized.idleSubtitle.contains("no te reconoció"))
    }
}
