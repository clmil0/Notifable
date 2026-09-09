import Foundation

/// Recorre listas largas cediendo el hilo principal cada cierto número de
/// elementos.
///
/// El problema que resuelve: reclasificar cientos de gastos, o renombrar una
/// categoría con años de historial, son bucles síncronos sobre `@Model` — no
/// hay ninguna tarea de red que envolver en un spinner. Sin ceder el hilo, la
/// UI se congela hasta que el bucle termina y no hay forma de dibujar ni
/// animar ningún indicador mientras tanto. Cediendo cada `chunkSize`
/// elementos, el hilo principal alcanza a procesar un fotograma entre lotes,
/// así que un `ProgressView` sí puede aparecer y animarse, y la persona sabe
/// que su toque se registró.
///
/// No mueve el trabajo a otro hilo — `ModelContext` no es seguro fuera del
/// principal sin un `ModelActor` dedicado — sólo lo trocea para que el mismo
/// hilo respire entre lotes.
enum Batching {

    @MainActor
    static func run<T>(_ items: [T], chunkSize: Int = 150, body: (T) -> Void) async {
        for (index, item) in items.enumerated() {
            body(item)
            if index % chunkSize == chunkSize - 1 {
                await Task.yield()
            }
        }
    }
}
