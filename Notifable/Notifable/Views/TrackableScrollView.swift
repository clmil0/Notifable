import SwiftUI

/// El `ScrollView` de las cuatro pestañas, con "volver arriba" al tocar de
/// nuevo la pestaña que ya está abierta.
///
/// **Antes también publicaba el desplazamiento** en un `@Binding` que subía
/// hasta un `@State` de `ContentView`. Nadie lo leía —ni la cabecera ni la
/// barra de pestañas reaccionaban al scroll—, pero escribirlo invalidaba el
/// cuerpo de `ContentView` entero en cada fotograma del desplazamiento: la
/// cabecera, la barra flotante y la pestaña visible se reevaluaban a 120 Hz, y
/// con ellas `Accounting.totals` sobre todo el historial. Era la causa de que
/// la app se sintiera pesada justo al desplazarse, que es cuando más se nota.
///
/// Si algún día la cabecera tiene que reaccionar al scroll, el sitio es
/// `.onScrollGeometryChange` sobre esta vista, nunca un `@State` de la raíz.
struct TrackableScrollView<Content: View>: View {
    let content: () -> Content
    @Binding var scrollToTopTrigger: Bool

    init(scrollToTopTrigger: Binding<Bool> = .constant(false),
         @ViewBuilder content: @escaping () -> Content) {
        self._scrollToTopTrigger = scrollToTopTrigger
        self.content = content
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 0).id("top")
                    content()
                }
            }
            .onChange(of: scrollToTopTrigger) { _, _ in
                withAnimation {
                    proxy.scrollTo("top", anchor: .top)
                }
            }
        }
    }
}
