import SwiftUI

/// El gráfico del dashboard (`2d` de «Resumen Gráficas»): una barra por
/// periodo en degradado del color del gasto, con una línea clara en la
/// superficie. Al entrar cada barra se llena con un rebote corto; en la
/// elegida suben burbujas que, al llegar arriba, revientan en un anillo. Un
/// anillo sólo aparece cuando una burbuja llega: al elegir una barra no hay
/// nada arriba hasta que la primera termina de subir.
///
/// «Semana» son los últimos siete días, uno por barra, terminando hoy. «Mes»
/// son las últimas seis semanas contando la actual, una por barra: treinta
/// barras de un día eran rayas que no se podían tocar.
///
/// Tocar una barra pone su monto encima. Por defecto se ve la última con gasto.
struct SpendBarChart: View {

    enum Mode: String, CaseIterable, Hashable {
        case week = "Semana"
        case month = "Mes"
    }

    struct Column: Identifiable {
        let id: Int
        let label: String
        /// Para VoiceOver: «martes 22», «semana del 15 set».
        let accessibilityLabel: String
        let total: Double
    }

    let columns: [Column]
    @Binding var selected: Int?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var palette: Palette { Palette(scheme) }

    /// Las barras ya llenas; vuelve a `false` para repetir la entrada cuando
    /// cambian los periodos (Semana ↔ Mes, otro mes).
    @State private var filled = false
    /// Cuándo empezó la última entrada: las burbujas esperan a que la barra
    /// se asiente.
    @State private var entrance = Date.distantPast
    /// Cuándo se eligió la barra actual: las burbujas cuentan desde aquí.
    @State private var selectedAt = Date.distantPast

    private static let barArea: CGFloat = 112
    private static let labelRoom: CGFloat = 22
    private static let settle: TimeInterval = 1.1
    private static let stagger: TimeInterval = 0.07

    private var maximum: Double { columns.map(\.total).max() ?? 0 }

    /// Identifica el juego de periodos, no sus montos: un gasto nuevo no
    /// repite la entrada.
    private var periodsKey: String { columns.map(\.label).joined(separator: "|") }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(columns) { column in
                columnView(column)
            }
        }
        .frame(height: Self.barArea + Self.labelRoom + 18, alignment: .bottom)
        .onChange(of: selected) { _, _ in selectedAt = Date() }
        .task(id: periodsKey) {
            guard !reduceMotion else { filled = true; return }
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { filled = false }
            entrance = Date()
            try? await Task.sleep(for: .milliseconds(16))
            filled = true
        }
    }

    private func columnView(_ column: Column) -> some View {
        let isSelected = selected == column.id
        let hasSpend = Money.cents(column.total) > 0
        let barHeight = height(column.total)
        let index = columns.firstIndex { $0.id == column.id } ?? 0

        return VStack(spacing: 7) {
            ZStack(alignment: .bottom) {
                Color.clear.frame(height: Self.barArea)

                bar(hasSpend: hasSpend, isSelected: isSelected, height: barHeight)
                    .overlay(alignment: .bottom) {
                        if isSelected && hasSpend && barHeight >= 10 && !reduceMotion {
                            BubbleBurst(seed: column.id,
                                        barHeight: barHeight,
                                        ring: palette.expense.mixed(with: .white, amount: 0.3, scheme: scheme),
                                        start: max(selectedAt, entrance + Self.settle + Double(index) * Self.stagger))
                                .frame(height: barHeight + BubbleBurst.headroom)
                                .allowsHitTesting(false)
                        }
                    }
                    .scaleEffect(x: 1, y: filled ? 1 : 0, anchor: .bottom)
                    .animation(filled ? .spring(response: 0.6, dampingFraction: 0.55)
                                            .delay(Double(index) * Self.stagger) : nil,
                               value: filled)
            }
            .overlay(alignment: .top) {
                if isSelected {
                    Text(Money.formatCompact(column.total))
                        .font(.system(size: 14, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(palette.duoText ?? palette.expense)
                        .fixedSize()
                        .offset(y: -Self.labelRoom + max(0, Self.barArea - barHeight) - 4)
                        .transition(.opacity)
                }
            }

            Text(column.label)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? palette.expenseText : palette.secondaryLabel)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.18)) { selected = column.id }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(column.accessibilityLabel)
        .accessibilityValue(Money.format(column.total))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Degradado del gasto (más claro arriba) con la línea de la superficie;
    /// las no elegidas al 55 %.
    private func bar(hasSpend: Bool, isSelected: Bool, height: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        let top = palette.expense.mixed(with: .white, amount: 0.28, scheme: scheme)

        return shape
            .fill(hasSpend
                  ? AnyShapeStyle(LinearGradient(colors: [palette.expense, top], startPoint: .bottom, endPoint: .top))
                  : AnyShapeStyle(palette.track))
            .overlay(alignment: .top) {
                if hasSpend {
                    Rectangle().fill(.white.opacity(0.6)).frame(height: 1.5)
                }
            }
            .clipShape(shape)
            .frame(height: height)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(palette.expense.opacity(isSelected && hasSpend ? 0.35 : 0), lineWidth: 2)
                    .padding(-2)
            )
            .opacity(!hasSpend || isSelected ? 1 : 0.55)
    }

    /// Nunca cero del todo: un periodo sin gasto se ve como una raya, no como
    /// un hueco que parezca un error de dibujo.
    private func height(_ value: Double) -> CGFloat {
        guard maximum > 0 else { return 4 }
        return max(4, Self.barArea * CGFloat(value / maximum))
    }
}

/// Las burbujas de la barra elegida: suben desde el fondo y, al tocar la
/// superficie, revientan en un anillo que se abre. El tiempo cuenta desde que
/// la barra fue elegida (o desde que terminó de asentarse), así que nada se
/// dibuja arriba antes de que una burbuja llegue.
private struct BubbleBurst: View {
    /// Lugar sobre la barra para que el anillo se abra fuera de ella.
    static let headroom: CGFloat = 14

    let seed: Int
    let barHeight: CGFloat
    let ring: Color
    let start: Date

    private static let count = 4
    /// Parte del ciclo en que la burbuja sube; el resto es el anillo.
    private static let riseShare = 0.86

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                draw(in: &context, size: size, elapsed: timeline.date.timeIntervalSince(start))
            }
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        guard elapsed > 0 else { return }
        let top = Self.headroom
        let barRect = CGRect(x: 0, y: top, width: size.width, height: barHeight)

        for n in 0..<Self.count {
            // En barras bajas las burbujas son más chicas y suben más rápido.
            let diameter = min(4 + Self.random(seed, n) * 3, max(3, barHeight * 0.35))
            let x = size.width * (0.12 + Self.random(seed, n + 9) * 0.64) + diameter / 2
            let duration = (1.8 + Self.random(seed, n + 3) * 1.8) * max(0.5, (barHeight / 112).squareRoot())
            // Salidas escalonadas: la primera parte en cuanto se elige la
            // barra, así siempre se ven burbujas desde el primer momento.
            let offset = (Double(n) + Self.random(seed, n + 5) * 0.5) / Double(Self.count) * duration
            let local = elapsed - offset
            guard local >= 0 else { continue }   // esta burbuja aún no sale
            let phase = local.truncatingRemainder(dividingBy: duration) / duration

            if phase < Self.riseShare {
                // Sube con aceleración, desde el fondo de la barra hasta que su centro toca la superficie.
                let q = phase / Self.riseShare
                let eased = q * q
                let y = barRect.maxY - diameter / 2 - (barHeight - diameter / 2) * eased
                let wobble = sin(q * .pi) * (Self.random(seed, n + 7) - 0.5) * 5
                let opacity = 0.85 * min(1, q / 0.14)
                let rect = CGRect(x: x + wobble - diameter / 2, y: y - diameter / 2,
                                  width: diameter, height: diameter)

                context.drawLayer { layer in
                    layer.clip(to: Path(roundedRect: barRect, cornerRadius: 6, style: .continuous))
                    layer.opacity = opacity
                    let circle = Path(ellipseIn: rect)
                    layer.fill(circle, with: .radialGradient(
                        Gradient(stops: [.init(color: .white.opacity(0.95), location: 0),
                                         .init(color: .white.opacity(0.95), location: 0.16),
                                         .init(color: .white.opacity(0.28), location: 0.38),
                                         .init(color: .white.opacity(0.08), location: 0.72)]),
                        center: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.minY + rect.height * 0.30),
                        startRadius: 0, endRadius: diameter * 0.75))
                    layer.stroke(circle, with: .color(.white.opacity(0.6)), lineWidth: 0.75)
                }
            } else {
                // Revienta: un anillo que se abre y se apaga sobre la superficie.
                let q = (phase - Self.riseShare) / (1 - Self.riseShare)
                let scale = 0.4 + 1.4 * q
                let side = (diameter + 6) * scale
                let opacity = 0.9 * (q < 0.2 ? q / 0.2 : (1 - q) / 0.8)
                let rect = CGRect(x: x - side / 2, y: top - side / 2, width: side, height: side)
                context.stroke(Path(ellipseIn: rect), with: .color(ring.opacity(opacity)), lineWidth: 1)
            }
        }
    }

    /// Pseudoaleatorio fijo por barra y burbuja, como en el diseño.
    private static func random(_ i: Int, _ n: Int) -> Double {
        let x = sin(Double(n) * 127.1 + Double(i) * 311.7) * 43758.5453
        return x - floor(x)
    }
}

/// «Semana · Mes»: el conmutador chico, sobre el fondo, del gráfico.
struct CompactSegment<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let label: (Item) -> String

    @Environment(\.colorScheme) private var scheme
    private var palette: Palette { Palette(scheme) }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                let isOn = selection == item
                Button {
                    guard !isOn else { return }
                    withAnimation(.easeInOut(duration: 0.2)) { selection = item }
                } label: {
                    Text(label(item))
                        .font(.system(size: 12, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? palette.label : palette.secondaryLabel)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background {
                            if isOn { Capsule().fill(palette.selectedFill) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(3)
        .background(palette.background, in: Capsule())
        .overlay(Capsule().stroke(palette.hairline, lineWidth: 0.5))
    }
}
