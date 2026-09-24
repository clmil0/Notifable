import SwiftUI

/// Cuánto se ha desplazado la pestaña visible.
///
/// Vive en una clase observable a propósito. `TrackableScrollView` avisa de que
/// publicar el desplazamiento en un `@State` de la raíz invalidaba el cuerpo de
/// `ContentView` en cada fotograma —y con él `Accounting.totals` sobre todo el
/// historial—, que es lo que hacía que la app se sintiera pesada justo al
/// desplazarse. Con `@Observable`, sólo se vuelven a dibujar las vistas que
/// leen `offset`: el header flotante y la píldora de tabs, que no calculan nada.
@Observable
final class ScrollProgress {
    /// Puntos desplazados desde el tope. Nunca negativo (el rebote elástico no
    /// debe encender el blur del header).
    var offset: CGFloat = 0

    /// Más allá de esto el header ya está en su estado final (el degradado
    /// llega a opaco en `blurThreshold`): seguir publicando el desplazamiento
    /// sólo invalidaba vistas en cada fotograma.
    private static let publishLimit: CGFloat = ShellMetrics.blurThreshold

    /// Redondeado a puntos enteros: en pantallas 3x el desplazamiento avanza
    /// en tercios de punto, y cada uno redibujaba el header. Un punto es un
    /// 4 % de opacidad del degradado, imperceptible en movimiento.
    func update(_ newOffset: CGFloat) {
        let clamped = min(max(0, newOffset), Self.publishLimit).rounded()
        if clamped != offset { offset = clamped }
    }

    func reset() {
        offset = 0
    }
}

/// Si alguna lista de la app se está deslizando ahora mismo.
///
/// Lo consulta el sync de Gmail antes de guardar un movimiento nuevo:
/// guardarlo hace que `@Query` avise y el dashboard entero se vuelva a
/// calcular, y a mitad de un deslizamiento eso es un tirón. Esperar a que se
/// suelte el dedo son unos cientos de milisegundos.
///
/// Cuenta deslizamientos y no un simple sí/no: el dashboard sigue vivo debajo
/// de una pantalla abierta encima, y cada una avisa por su cuenta.
enum ScrollActivity {
    private static let lock = NSLock()
    private static var active = 0

    static var isScrolling: Bool { lock.withLock { active > 0 } }

    static func began() { lock.withLock { active += 1 } }
    static func ended() { lock.withLock { active = max(0, active - 1) } }

    /// Para trabajo diferido del hilo principal (respaldo, avisos, lo que
    /// compartes): espera, sin bloquear, a que no haya deslizamientos. Hecho a
    /// mitad de un gesto, cualquiera de ellos es un tirón. Con tope, por si un
    /// aviso de fin se perdiera.
    static func idle(timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while isScrolling && Date() < deadline && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(120))
        }
    }

    /// Bloquea el hilo que llama —nunca el principal— hasta que no haya
    /// deslizamientos, o hasta `timeout`: un aviso de fin perdido no puede
    /// dejar el sync esperando para siempre.
    static func waitUntilIdle(timeout: TimeInterval = 3) {
        // En el principal no se espera: bloquearlo congelaría el propio
        // deslizamiento que se quiere proteger.
        guard !Thread.isMainThread else { return }
        let deadline = Date().addingTimeInterval(timeout)
        while isScrolling && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
    }
}
