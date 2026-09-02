import SwiftUI

/// La tarjeta principal de Resumen: el monto grande leído contra el presupuesto.
///
/// El monto solo dice cuánto llevas. La barra con la **marca de ritmo** —la línea
/// blanca en el punto del periodo que ya transcurrió— es lo que lo convierte en
/// un juicio: si el relleno va por delante de la marca, vas rápido.
///
/// Está partida en funciones pequeñas a propósito; una vista SwiftUI se compone
/// en una única expresión y con este número de modificadores el comprobador de
/// tipos deja de terminar en tiempo razonable.
struct BudgetHeroCard: View {

    let period: Period
    let totals: PeriodTotals
    /// Abre los ajustes de presupuesto cuando aún no hay ninguno definido.
    var onDefineBudget: () -> Void

    @Environment(\.colorScheme) private var scheme
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.purple.rawValue
    @AppStorage(BudgetStore.enabledKey) private var budgetEnabled = true
    @AppStorage(BudgetStore.monthlyBudgetKey) private var monthlyBudget: Double = 0

    @State private var isExpandingAmount = false

    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .purple }
    private var palette: Palette { Palette(scheme) }

    private var pace: Pace? {
        BudgetStore.pace(monthlyBudget: monthlyBudget,
                         enabled: budgetEnabled,
                         for: period,
                         spent: totals.spent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            amount

            if let pace {
                progressBar(pace)
                targetLine(pace)
                paceBanner(pace)
                Divider().background(palette.separator)
                footer(pace)
            } else {
                defineBudgetButton
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(palette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Piezas

    private var header: some View {
        HStack {
            Text(period.spentHeadline)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.secondaryLabel)

            Spacer()

            if let remaining = remainingLabel {
                Text(remaining)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
            }
        }
    }

    private var remainingLabel: String? {
        guard period.isCurrent else { return nil }
        let days = period.remainingDays
        guard days > 0 else { return "último día" }
        return days == 1 ? "queda 1 día" : "quedan \(days) días"
    }

    /// El monto debe caber por defecto; la pulsación larga sigue existiendo para
    /// ver la cifra completa cuando es muy larga.
    private var amount: some View {
        Text(Money.format(totals.spent))
            .font(.system(size: 44, weight: .bold, design: .rounded))
            .foregroundStyle(palette.label)
            .lineLimit(isExpandingAmount ? nil : 1)
            .minimumScaleFactor(0.6)
            .onLongPressGesture(minimumDuration: .infinity, perform: {}) { pressing in
                withAnimation(.spring) { isExpandingAmount = pressing }
            }
    }

    private func progressBar(_ pace: Pace) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let filled = min(1, max(0, pace.usedFraction))
            let markX = width * CGFloat(pace.expectedFraction)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.track)

                Capsule()
                    .fill(barColor(pace))
                    .frame(width: width * CGFloat(filled))

                // La marca de ritmo. La sombra del color de la superficie es lo
                // que la separa del relleno cuando cae justo encima.
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2)
                    .shadow(color: palette.surface, radius: 1.5)
                    .offset(x: min(max(markX - 1, 0), width - 2))
            }
        }
        .frame(height: 12)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: pace.usedFraction)
    }

    private func barColor(_ pace: Pace) -> Color {
        switch pace.status {
        case .ok: return accent.color
        case .warning: return palette.warning
        case .over: return palette.negative
        }
    }

    private func targetLine(_ pace: Pace) -> some View {
        HStack {
            Text("de " + Money.format(pace.target) + " · \(pace.usedPercent)%")
                .font(.footnote)
                .foregroundStyle(palette.secondaryLabel)

            Spacer()

            Text("ritmo esperado \(pace.expectedPercent)%")
                .font(.footnote)
                .foregroundStyle(palette.secondaryLabel)
        }
    }

    private func paceBanner(_ pace: Pace) -> some View {
        let tint = bannerTint(pace)

        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: bannerIcon(pace))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)

            Text(pace.message)
                .font(.footnote)
                .foregroundStyle(palette.label)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(scheme == .dark ? 0.18 : 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func bannerTint(_ pace: Pace) -> Color {
        switch pace.status {
        case .ok: return palette.positive
        case .warning: return palette.warning
        case .over: return palette.negative
        }
    }

    private func bannerIcon(_ pace: Pace) -> String {
        switch pace.status {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "chart.line.uptrend.xyaxis"
        case .over: return "exclamationmark.triangle.fill"
        }
    }

    private func footer(_ pace: Pace) -> some View {
        HStack(spacing: 0) {
            statColumn(title: "Promedio diario",
                       value: Money.format(totals.averagePerDay),
                       tint: palette.label)

            Rectangle()
                .fill(palette.separator)
                .frame(width: 0.5, height: 32)

            statColumn(title: "Disponible / día",
                       value: pace.availablePerDay.map { Money.format($0) } ?? "—",
                       tint: pace.isOverPace ? palette.warning : palette.label)
        }
    }

    private func statColumn(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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
        .padding(.leading, 12)
    }

    /// Sin presupuesto no se inventa una meta: se ofrece definirla.
    private var defineBudgetButton: some View {
        Button(action: onDefineBudget) {
            Text("Definir presupuesto mensual")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent.onSurface(scheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(accent.softFill(scheme))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(accent.color.opacity(0.5), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}
