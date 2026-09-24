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

    /// Se está deslizando: las burbujas del gráfico se detienen mientras
    /// tanto, para dejarle el fotograma entero al scroll.
    var isScrolling: Bool = false

    /// Más allá de esto el header ya está en su estado final: seguir
    /// publicando el desplazamiento sólo invalidaba vistas en cada fotograma.
    private static let publishLimit: CGFloat = 64

    func update(_ newOffset: CGFloat) {
        let clamped = min(max(0, newOffset), Self.publishLimit)
        if clamped != offset { offset = clamped }
    }

    func reset() {
        offset = 0
        isScrolling = false
    }
}
