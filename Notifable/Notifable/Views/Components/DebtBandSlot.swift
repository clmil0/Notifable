import SwiftUI

/// Lo que la banda "por cobrar" necesita dibujar, ya resuelto en números y
/// texto. Es un valor —no el `Expense`— para que la banda pueda seguir
/// dibujándose mientras se cierra, cuando el gasto ya dejó de ser deuda.
struct DebtBandInfo: Equatable {
    /// Abierta (ámbar, sigue pendiente) o saldada (verde).
    var isOpen: Bool
    var valueText: String
    /// Proporción ya abonada, sólo cuando hay pago parcial. `nil` = sin barra.
    var progress: Double?
}

/// Hueco animado para la banda de deuda bajo una fila de Actividad Reciente.
///
/// Abrir y cerrar no puede ser un `if` con transición: al insertar la banda
/// aparece ya con su alto final, la fila da un salto y las de abajo lo
/// acusan. Aquí la banda está siempre montada y lo que se anima es el **alto
/// del hueco**, anclado arriba y recortado: el icono, el nombre, la
/// categoría, la fecha y el monto no se mueven ni un punto, porque el hueco
/// crece por debajo de ellos.
///
/// Y en dos tiempos, no en uno:
///
/// 1. **Se abre el hueco, vacío.** Sólo baja el borde inferior de la tarjeta.
/// 2. **Ya hecho el sitio, la banda entra con un fundido.** Antes se veía
///    asomar recortada mientras el hueco crecía, y como el contenido se
///    dibujaba pegado arriba parecía subir y bajar al acomodarse.
///
/// Al cerrar, el orden se invierte: primero se va la banda, después se
/// recoge el hueco.
///
/// La separación con el movimiento viaja dentro del hueco (no como `spacing`
/// del `VStack` de la fila) para que también crezca desde cero; si no, la
/// fila saltaría esos puntos de golpe antes de empezar a animar.
struct DebtBandSlot: View {
    /// `nil` = cerrada. El último valor no nulo es el que se sigue dibujando
    /// mientras se cierra, para que el contenido no parpadee al desaparecer.
    let info: DebtBandInfo?
    var topSpacing: CGFloat = 10

    /// Lo que tarda el hueco en abrirse o recogerse.
    private let growth: TimeInterval = 0.28
    /// Fundido de la banda una vez hecho el sitio. Más corto al salir: irse
    /// rápido y dejar que el hueco se recoja se siente más limpio que
    /// desvanecerse con calma sobre un espacio que ya sobra.
    private let fadeIn: TimeInterval = 0.22
    private let fadeOut: TimeInterval = 0.14

    @Environment(\.colorScheme) private var colorScheme
    @State private var lastInfo: DebtBandInfo?
    /// Las dos fases. Separadas a propósito: el alto y la opacidad no van
    /// juntos, van uno detrás del otro.
    @State private var openness: CGFloat = 0
    @State private var showsBand = false

    private var palette: Palette { Palette(colorScheme) }

    /// Sólo para dar alto al hueco cuando todavía no hay banda real que
    /// medir. Nunca se llega a ver.
    private static let measuringSample = DebtBandInfo(isOpen: true, valueText: "0", progress: nil)

    var body: some View {
        // `CollapsingHeight` y no un `.frame(height:)` con la medida tomada a
        // mano: medir con un `GeometryReader` dentro del propio hueco no
        // funciona, porque estando cerrado el hueco mide cero y devuelve cero
        // — el alto de destino sólo se conocía **al abrir**, y por eso el
        // cambio salía de un salto en un solo fotograma en vez de animarse.
        // El `Layout` pregunta siempre por el alto natural de la banda, esté
        // el hueco abierto o cerrado, e interpola el suyo entre 0 y ese.
        CollapsingHeight(openness: openness) {
            band(info ?? lastInfo ?? Self.measuringSample)
                .padding(.top, topSpacing)
                .opacity(showsBand ? 1 : 0)
        }
        .clipped()
        .allowsHitTesting(showsBand)
        .onChange(of: info) { _, new in
            if let new { lastInfo = new }
            setOpen(new != nil)
        }
        .onAppear {
            if let info { lastInfo = info }
            // Sin animación: una fila que entra en pantalla ya abierta se
            // dibuja abierta, no se abre delante del usuario.
            openness = info == nil ? 0 : 1
            showsBand = info != nil
        }
    }

    /// Encadena las dos fases. Sin `withAnimation` en competencia: para
    /// cuando esto corre, el menú contextual ya terminó de cerrarse — quien
    /// dispara el cambio lo espera a propósito.
    private func setOpen(_ open: Bool) {
        guard open != (openness > 0) else { return }

        if open {
            withAnimation(.easeOut(duration: growth)) { openness = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + growth) {
                guard openness > 0 else { return }
                withAnimation(.easeOut(duration: fadeIn)) { showsBand = true }
            }
        } else {
            withAnimation(.easeIn(duration: fadeOut)) { showsBand = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + fadeOut) {
                guard !showsBand else { return }
                withAnimation(.easeInOut(duration: growth)) { openness = 0 }
            }
        }
    }

    @ViewBuilder
    private func band(_ info: DebtBandInfo) -> some View {
        let tint = info.isOpen ? palette.warning : palette.positive

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Por cobrar")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(tint)
                Spacer()
                Text(info.valueText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }

            if let progress = info.progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.warning.opacity(0.18))
                        Capsule().fill(palette.warning)
                            .frame(width: geo.size.width * CGFloat(min(1, max(0, progress))))
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, info.progress != nil ? 8 : 7)
        .background(tint.opacity(colorScheme == .dark ? 0.16 : 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct DebtBandHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Reserva una fracción `openness` del alto natural de su contenido, con el
/// contenido anclado arriba y a su tamaño completo (el recorte lo pone quien
/// la usa). Es `Animatable`, así que la fracción se interpola fotograma a
/// fotograma y el alto del hueco con ella.
private struct CollapsingHeight: Layout, Animatable {
    var openness: CGFloat

    var animatableData: CGFloat {
        get { openness }
        set { openness = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let natural = content.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? natural.width,
                      height: max(0, natural.height * openness))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let content = subviews.first else { return }
        let natural = content.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        content.place(at: CGPoint(x: bounds.minX, y: bounds.minY),
                      anchor: .topLeading,
                      proposal: ProposedViewSize(width: bounds.width, height: natural.height))
    }
}
