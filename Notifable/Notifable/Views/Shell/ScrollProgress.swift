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

    /// El scroll va hacia abajo: la píldora de tabs se encoge a sólo íconos.
    var isScrollingDown: Bool = false

    private var lastOffset: CGFloat = 0

    func update(_ newOffset: CGFloat) {
        let clamped = max(0, newOffset)
        // Umbral de 6 pt: sin él, el temblor natural del dedo alterna el
        // estado de las etiquetas varias veces por segundo.
        if abs(clamped - lastOffset) > 6 {
            isScrollingDown = clamped > lastOffset && clamped > 40
            lastOffset = clamped
        }
        offset = clamped
    }

    func reset() {
        offset = 0
        lastOffset = 0
        isScrollingDown = false
    }
}
