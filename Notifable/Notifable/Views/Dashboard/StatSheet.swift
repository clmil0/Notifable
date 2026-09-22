import SwiftUI

/// Lo que dice una tira de stats al tocarla (`1b`): la cifra en grande, qué
/// significa en una frase, y las dos cifras de las que sale.
///
/// Las tiras del dashboard son finas a propósito —etiqueta y número— y el
/// detalle (ritmo esperado, presupuesto, ingresos) vive aquí, sin sacar al
/// usuario del dashboard.
struct StatDetail: Identifiable {
    enum Kind: String { case net, pace, perDay, biggest, topMerchant }

    let kind: Kind
    let title: String
    let amount: String
    var amountColor: Color?
    let detail: String
    let tiles: [(label: String, value: String)]
    /// Lo que dice la tira del dashboard, si no es la cifra de arriba recortada.
    var strip: String?
    /// Sólo en Ritmo: la barra con la marca de dónde deberías ir.
    var pace: Pace?

    var id: String { kind.rawValue }
}

struct StatSheet: View {
    let stat: StatDetail

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var palette: Palette { Palette(scheme) }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.label)
                        .frame(width: 34, height: 34)
                        .background(palette.selectedFill, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cerrar")
            }
            .overlay {
                Text(stat.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.label)
            }

            VStack(spacing: 10) {
                Text(stat.amount)
                    .font(.system(size: 40, weight: .bold))
                    .tracking(-1.4)
                    .monospacedDigit()
                    .foregroundStyle(stat.amountColor ?? palette.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(stat.detail)
                    .font(.system(size: 14))
                    .foregroundStyle(palette.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)

            if let pace = stat.pace {
                PaceBar(fraction: pace.usedFraction,
                        expected: pace.expectedFraction,
                        status: pace.status,
                        height: 8)
                    .padding(.horizontal, 4)
            }

            HStack(spacing: 10) {
                ForEach(stat.tiles, id: \.label) { tile in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(tile.label)
                            .font(.system(size: 12.5))
                            .foregroundStyle(palette.tertiaryLabel)
                        Text(tile.value)
                            .font(.system(size: 20, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(palette.label)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 13)
                    .background(palette.selectedFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .presentationDetents([.height(stat.pace == nil ? 340 : 372)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(palette.surfaceElevated)
    }
}
