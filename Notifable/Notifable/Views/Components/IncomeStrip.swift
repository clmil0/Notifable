import SwiftUI

/// Tira de ingresos: 60 pt con "Ingresos" y "Balance" separados por un divisor.
///
/// Hay usuarios que no quieren registrar ingresos. Con `trackIncome` apagado
/// esta tira se sustituye por una invitación a activarlos, y la pantalla no
/// pierde nada: el presupuesto ya responde "¿voy bien?" por su cuenta.
struct IncomeStrip: View {

    let totals: PeriodTotals
    var onTap: () -> Void
    var onEnableIncome: () -> Void

    @Environment(\.colorScheme) private var scheme
    @AppStorage(BudgetStore.tracksIncomeKey) private var tracksIncome = true

    private var palette: Palette { Palette(scheme) }

    var body: some View {
        Group {
            if tracksIncome {
                strip
            } else {
                invitation
            }
        }
        .padding(.horizontal, 16)
    }

    private var strip: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                column(title: "Ingresos",
                       value: Money.format(totals.income),
                       tint: Money.isZero(totals.income) ? palette.secondaryLabel : palette.positive)

                Rectangle()
                    .fill(palette.separator)
                    .frame(width: 0.5, height: 32)

                column(title: "Balance",
                       value: totals.balance.map { Money.format($0) } ?? "—",
                       tint: balanceTint)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.secondaryLabel)
                    .padding(.trailing, 16)
            }
            .frame(height: 60)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    /// `balance` es `nil` cuando no hay ingresos en el periodo: se muestra "—"
    /// en vez de un "Restante" que sería el gasto en negativo.
    private var balanceTint: Color {
        guard let balance = totals.balance else { return palette.secondaryLabel }
        return Money.cents(balance) < 0 ? palette.negative : palette.label
    }

    private func column(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 16)
    }

    private var invitation: some View {
        Button(action: onEnableIncome) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle")
                    .font(.subheadline)
                VStack(alignment: .leading, spacing: 2) {
                    Text("¿Quieres registrar ingresos?")
                        .font(.subheadline.weight(.semibold))
                    Text("AgruPay usa sólo tu presupuesto mientras esté apagado.")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(palette.label)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(palette.hairline,
                                  style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
        }
        .buttonStyle(.plain)
    }
}
