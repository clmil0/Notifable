import SwiftUI

/// El donut de distribución de Categorías (`1b`).
///
/// Dibujado a mano y no con Swift Charts: el gráfico necesita el monto del
/// periodo centrado dentro del anillo, y los colores tienen que salir de
/// `CategoryStyle` —el mismo que pinta los íconos de cada fila— para que la
/// porción y el cuadradito de la lista de abajo sean del mismo color. Un
/// `SectorMark` con su propia escala de color rompería justo eso.
struct CategoryDonut: View {
    struct Slice: Identifiable {
        let category: String
        let total: Double
        let color: Color
        var id: String { category }
    }

    let slices: [Slice]
    /// Igual que en `DonutLegend`: a partir de aquí el resto se junta en una
    /// sola porción gris, para que el anillo se lea de un vistazo.
    var maxSlices: Int = 6

    var lineWidth: CGFloat = 26
    var size: CGFloat = 136

    @Environment(\.colorScheme) private var scheme
    private var palette: Palette { Palette(scheme) }

    private var total: Double { Money.sum(slices) { $0.total } }

    /// Las primeras `maxSlices` y, si sobran, «Otras» con el resto.
    private var visibleSlices: [Slice] {
        guard slices.count > maxSlices else { return slices }
        let rest = slices.dropFirst(maxSlices)
        return Array(slices.prefix(maxSlices)) + [
            Slice(category: "Otras",
                  total: Money.sum(Array(rest)) { $0.total },
                  color: palette.tertiaryLabel)
        ]
    }

    /// Inicio y fin de cada arco, en fracciones de vuelta.
    private var arcs: [(slice: Slice, start: Double, end: Double)] {
        guard Money.cents(total) > 0 else { return [] }
        var cursor = 0.0
        return visibleSlices.map { slice in
            let fraction = max(0, slice.total / total)
            let arc = (slice, cursor, cursor + fraction)
            cursor += fraction
            return arc
        }
    }

    var body: some View {
        ZStack {
            // `inset` mete el anillo dentro del marco: con `stroke` a secas la
            // mitad del grosor se salía y el donut ocupaba más de lo que medía.
            Circle()
                .inset(by: lineWidth / 2)
                .stroke(palette.track, lineWidth: lineWidth)

            ForEach(arcs, id: \.slice.id) { arc in
                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: arc.start, to: max(arc.start, arc.end - 0.004))
                    .stroke(arc.slice.color,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            }
        }
        // El primer arco arranca arriba, no a las tres en punto.
        .rotationEffect(.degrees(-90))
        .frame(width: size, height: size)
    }
}

/// La leyenda del donut: nombre y porcentaje, con el punto del color de la
/// porción. Hace de resumen; el detalle está en la lista de abajo.
struct DonutLegend: View {
    let slices: [CategoryDonut.Slice]
    let total: Double
    /// A partir de aquí el resto se agrupa en «Otras N».
    var maxRows: Int = 6

    @Environment(\.colorScheme) private var scheme
    private var palette: Palette { Palette(scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(slices.prefix(maxRows)) { slice in
                row(color: slice.color,
                    name: slice.category,
                    percent: Money.formatPercent(slice.total, of: total))
            }

            if slices.count > maxRows {
                let rest = slices.dropFirst(maxRows)
                let restTotal = Money.sum(Array(rest)) { $0.total }
                row(color: palette.tertiaryLabel,
                    name: "Otras \(rest.count)",
                    percent: Money.formatPercent(restTotal, of: total),
                    muted: true)
            }
        }
    }

    private func row(color: Color, name: String, percent: String, muted: Bool = false) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(muted ? palette.secondaryLabel : palette.label)
                .lineLimit(1)

            Spacer(minLength: 6)

            Text(percent)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(palette.secondaryLabel)
        }
    }
}

extension CategoryDonut {
    /// La rampa del gasto (`1b`): del ámbar al óxido, siempre en el naranja
    /// del gasto sea cual sea el tema. La porción más grande va en el tono
    /// más claro, y el punto de cada fila de la lista usa el mismo.
    static let expenseRamp: [Color] = [
        Color(red: 1.000, green: 0.690, blue: 0.227),   // #FFB03A
        Color(red: 1.000, green: 0.541, blue: 0.239),   // #FF8A3D
        Color(red: 1.000, green: 0.341, blue: 0.133),   // #FF5722
        Color(red: 0.902, green: 0.290, blue: 0.098),   // #E64A19
        Color(red: 0.757, green: 0.267, blue: 0.102),   // #C1441A
        Color(red: 0.541, green: 0.227, blue: 0.125),   // #8A3A20
    ]

    static func rampColor(at index: Int) -> Color {
        expenseRamp[min(index, expenseRamp.count - 1)]
    }
}
