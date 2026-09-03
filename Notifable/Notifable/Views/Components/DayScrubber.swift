import SwiftUI

/// Gráfico y navegación a la vez: una barra por día del periodo, con altura
/// proporcional al gasto de ese día.
///
/// Tocar un día lleva el periodo a `.dia`; volver a tocarlo regresa a la
/// granularidad anterior. En granularidad Semana se muestra como 7 celdas con
/// la inicial del día y su número.
struct DayScrubber: View {

    @Binding var period: Period
    /// Granularidad desde la que se entró al día, para poder volver.
    @Binding var returnGranularity: PeriodGranularity?
    let dailySpent: [PeriodTotals.DayTotal]

    @Environment(\.colorScheme) private var scheme
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue

    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .purple }
    private var palette: Palette { Palette(scheme) }

    private let barHeight: CGFloat = 34
    private let cellHeight: CGFloat = 56
    private let minimumFraction: CGFloat = 0.06

    private var cal: Calendar { Period.calendar }
    private var maxTotal: Double { dailySpent.map(\.total).max() ?? 0 }

    /// En Semana el scrubber son 7 celdas, no barras. Vale también cuando se ha
    /// entrado a un día desde la semana: se sigue viendo la semana.
    private var isWeekly: Bool {
        period.granularity == .semana
            || (period.granularity == .dia && returnGranularity == .semana)
    }

    var body: some View {
        Group {
            if isWeekly {
                weekCells
            } else {
                bars
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Barras (Mes / Año / Rango)

    private var bars: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(dailySpent) { day in
                let isFuture = cal.startOfDay(for: day.date) > cal.startOfDay(for: Date())
                let fraction = height(for: day, isFuture: isFuture)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(fill(for: day, isFuture: isFuture))
                    .frame(height: max(2, barHeight * fraction))
                    .frame(maxWidth: .infinity)
                    .frame(height: barHeight, alignment: .bottom)
                    // El área táctil llega a 44 pt aunque la barra mida 34.
                    .contentShape(Rectangle().inset(by: -5))
                    .onTapGesture { toggleDay(day.date) }
                    .accessibilityLabel(accessibilityLabel(for: day))
            }
        }
        .frame(height: barHeight)
        .frame(minHeight: 44)
    }

    private func height(for day: PeriodTotals.DayTotal, isFuture: Bool) -> CGFloat {
        guard !isFuture else { return minimumFraction }
        guard let ratio = Money.ratio(day.total, to: maxTotal) else { return minimumFraction }
        return max(minimumFraction, CGFloat(ratio))
    }

    private func fill(for day: PeriodTotals.DayTotal, isFuture: Bool) -> Color {
        if isSelected(day.date) { return accent.color }
        if isFuture { return palette.track }
        if cal.isDateInToday(day.date) { return accent.color.opacity(0.55) }
        return palette.track
    }

    // MARK: - Celdas (Semana)

    private var weekCells: some View {
        HStack(spacing: 6) {
            ForEach(dailySpent) { day in
                let isFuture = cal.startOfDay(for: day.date) > cal.startOfDay(for: Date())
                let selected = isSelected(day.date)

                VStack(spacing: 4) {
                    Text(initial(for: day.date))
                        .font(.caption2.weight(.semibold))
                    Text("\(cal.component(.day, from: day.date))")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(selected ? Color.white : palette.label)
                .frame(maxWidth: .infinity)
                .frame(height: cellHeight)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selected ? accent.color : palette.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(selected ? Color.clear : palette.hairline, lineWidth: 0.5)
                        )
                )
                .opacity(isFuture ? 0.35 : 1)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isFuture else { return }
                    toggleDay(day.date)
                }
                .accessibilityLabel(accessibilityLabel(for: day))
            }
        }
        .frame(height: cellHeight)
    }

    private func initial(for date: Date) -> String {
        let names = ["L", "M", "X", "J", "V", "S", "D"]
        // weekday: 1 = domingo en el calendario gregoriano.
        let weekday = cal.component(.weekday, from: date)
        let index = (weekday + 5) % 7
        return names[index]
    }

    // MARK: - Selección

    private func isSelected(_ date: Date) -> Bool {
        period.granularity == .dia && cal.isDate(period.reference, inSameDayAs: date)
    }

    private func toggleDay(_ date: Date) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if isSelected(date) {
                period.granularity = returnGranularity ?? .mes
                returnGranularity = nil
            } else {
                if period.granularity != .dia {
                    returnGranularity = period.granularity
                }
                period.granularity = .dia
                period.reference = date
            }
        }
    }

    private func accessibilityLabel(for day: PeriodTotals.DayTotal) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_PE")
        f.dateFormat = "d 'de' MMMM"
        return f.string(from: day.date) + ", " + Money.format(day.total)
    }
}
