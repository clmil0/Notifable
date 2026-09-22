import SwiftUI

/// El gráfico del dashboard (`1b`): una barra por periodo, en el naranja del
/// gasto, sin comparar contra nada.
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
    private var palette: Palette { Palette(scheme) }

    private static let barArea: CGFloat = 112
    private static let labelRoom: CGFloat = 22

    private var maximum: Double { columns.map(\.total).max() ?? 0 }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(columns) { column in
                columnView(column)
            }
        }
        .frame(height: Self.barArea + Self.labelRoom + 18, alignment: .bottom)
    }

    private func columnView(_ column: Column) -> some View {
        let isSelected = selected == column.id

        return VStack(spacing: 7) {
            ZStack(alignment: .bottom) {
                Color.clear.frame(height: Self.barArea)

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Money.cents(column.total) > 0
                          ? AnyShapeStyle(LinearGradient(colors: [palette.expenseLight, palette.expense],
                                                         startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(palette.track))
                    .frame(height: height(column.total))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(palette.expense.opacity(isSelected ? 0.3 : 0), lineWidth: 2)
                            .padding(-2)
                    )
            }
            .overlay(alignment: .top) {
                if isSelected {
                    Text(Money.formatCompact(column.total))
                        .font(.system(size: 14, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(palette.expense)
                        .fixedSize()
                        .offset(y: -Self.labelRoom + max(0, Self.barArea - height(column.total)) - 4)
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

    /// Nunca cero del todo: un periodo sin gasto se ve como una raya, no como
    /// un hueco que parezca un error de dibujo.
    private func height(_ value: Double) -> CGFloat {
        guard maximum > 0 else { return 4 }
        return max(4, Self.barArea * CGFloat(value / maximum))
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
