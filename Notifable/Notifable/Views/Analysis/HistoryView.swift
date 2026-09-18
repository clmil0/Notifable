import SwiftUI
import SwiftData

/// Análisis › Historial (`2f`): **el único sitio de la app con periodo**.
///
/// El selector Día · Semana · Mes · Año que antes vivía arriba de Resumen, de
/// Categorías y de Ritmo —tres barras distintas para un mismo ajuste global—
/// se retira de todas y aterriza aquí. El resto de la app habla siempre del
/// mes en curso; quien quiera mirar atrás, entra.
///
/// Las barras no son los días del periodo: son **los últimos periodos**. Con
/// «Mes» se ven los últimos siete meses, y la barra de la derecha es el mes
/// actual. Es lo que convierte la pantalla en un historial y no en otro
/// gráfico del mes que ya estás viendo en Categorías.
struct HistoryView: View {
    @Binding var scrollToTopTrigger: Bool
    let progress: ScrollProgress

    @Environment(\.colorScheme) private var scheme
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @StateObject private var rates = ExchangeRateService.shared

    /// Local a esta vista, no `@AppStorage("period")`: el periodo dejó de ser
    /// un ajuste global. Nadie más lo lee.
    @State private var granularity: PeriodGranularity = .mes
    @State private var offset = 0

    private var palette: Palette { Palette(scheme) }
    private var accent: AppThemeColor { .current }
    private var rate: Double { rates.usdToPenRate }

    private static let selectable: [PeriodGranularity] = [.dia, .semana, .mes, .anio]

    /// Cuántas barras dibujar por granularidad. Más de esto y las barras se
    /// vuelven rayas que no se pueden tocar.
    private var bucketCount: Int {
        switch granularity {
        case .dia:    return 14
        case .semana: return 10
        case .mes:    return 7
        case .anio:   return 5
        case .rango:  return 7
        }
    }

    /// Los periodos a dibujar, del más antiguo al más reciente. El último es
    /// el seleccionado.
    private var periods: [Period] {
        var result: [Period] = []
        var cursor = Period(granularity: granularity, reference: Date())
        for _ in 0..<offset { cursor = cursor.previous }
        for _ in 0..<bucketCount {
            result.append(cursor)
            cursor = cursor.previous
        }
        return result.reversed()
    }

    private func totals(for period: Period) -> PeriodTotals {
        Accounting.totals(expenses: expenses, incomes: incomes, period: period, usdToPen: rate)
    }

    var body: some View {
        let periods = self.periods
        let series = periods.map { (period: $0, total: totals(for: $0).spent) }
        let current = periods.last ?? Period(granularity: granularity, reference: Date())
        let currentTotals = totals(for: current)
        let previousTotals = totals(for: current.previous)
        let rhythm = Rhythm(period: current, current: currentTotals, previous: previousTotals)

        TrackableScrollView(scrollToTopTrigger: $scrollToTopTrigger) {
            VStack(spacing: 18) {
                ShellSegment(items: Self.selectable, selection: $granularity) { $0.rawValue }

                chartCard(series: series)

                headline(period: current, totals: currentTotals, rhythm: rhythm, series: series)

                if !rhythm.categoryChanges.isEmpty {
                    changesSection(rhythm: rhythm, previous: current.previous)
                }

                let subscriptions = detectedSubscriptions(in: current)
                if !subscriptions.isEmpty {
                    subscriptionsSection(subscriptions)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, ShellMetrics.contentTopInset)
            .padding(.bottom, ShellMetrics.contentBottomInset)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            progress.update(offset)
        }
        .onChange(of: granularity) { _, _ in offset = 0 }
    }

    // MARK: - Gráfico

    private func chartCard(series: [(period: Period, total: Double)]) -> some View {
        let maximum = series.map(\.total).max() ?? 0

        return ShellCard(padding: 16) {
            VStack(spacing: 10) {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(series.enumerated()), id: \.offset) { index, item in
                        let isCurrent = index == series.count - 1
                        let fraction = maximum > 0 ? item.total / maximum : 0

                        VStack(spacing: 6) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.clear)
                                    .frame(height: 110)

                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(isCurrent ? accent.color : palette.track)
                                    .frame(height: max(3, 110 * fraction))
                            }

                            Text(axisLabel(for: item.period))
                                .font(.system(size: 10, weight: isCurrent ? .bold : .regular))
                                .foregroundStyle(isCurrent ? accent.onSurface(scheme) : palette.tertiaryLabel)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Tocar una barra mueve la ventana hasta ella: el
                            // pasado se navega tocando, no con flechas.
                            withAnimation(.easeInOut(duration: 0.25)) {
                                offset += (series.count - 1 - index)
                            }
                        }
                    }
                }

                if offset > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { offset = 0 }
                    } label: {
                        Text("Volver a " + (granularity == .anio ? "este año" : "hoy"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(accent.onSurface(scheme))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func axisLabel(for period: Period) -> String {
        let date = period.interval.start
        switch granularity {
        case .dia:
            return date.formatted(.dateTime.day().locale(Locale(identifier: "es_PE")))
        case .semana:
            return date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "es_PE")))
        case .mes, .rango:
            return Period.spanishMonthName(for: date, abbreviated: true)
        case .anio:
            return date.formatted(.dateTime.year())
        }
    }

    // MARK: - Titular y comparativas

    /// Las comparativas van **en texto, no en más gráficos**. Un segundo
    /// gráfico para decir «S/ 340 menos que en agosto» obliga a leer dos ejes
    /// para sacar una frase.
    private func headline(period: Period,
                          totals: PeriodTotals,
                          rhythm: Rhythm,
                          series: [(period: Period, total: Double)]) -> some View {
        let previous = series.count >= 2 ? series[series.count - 2].total : 0
        let delta = Money.subtract(totals.spent, previous)
        let isUp = Money.cents(delta) > 0
        let average = Money.sum(series.map(\.total)) / Double(max(1, series.count))

        let hasComparison = !Money.isZero(previous) && !Money.isZero(delta)

        return ShellCard {
            VStack(alignment: .leading, spacing: 8) {
                headlineRow(title: periodTitle(period),
                            total: totals.spent,
                            delta: hasComparison ? delta : nil,
                            isUp: isUp)

                if hasComparison {
                    secondaryLine("Gastaste " + Money.format(abs(delta))
                                  + (isUp ? " más" : " menos") + " que " + previousLabel() + ".")
                }

                secondaryLine(averageLabel() + ": " + Money.format(average) + ".")
            }
        }
    }

    /// Partido en su propia vista: el comprobador de tipos de Swift se rinde
    /// con un `HStack` que mezcla ternarios de color, concatenaciones de
    /// cadena y vistas condicionales en la misma expresión.
    private func headlineRow(title: String, total: Double, delta: Double?, isUp: Bool) -> some View {
        // El periodo, pequeño, encima del monto; el delta a la derecha, a la
        // altura del monto (`2f`).
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.secondaryLabel)

                Text(Money.format(total))
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.8)
                    .foregroundStyle(palette.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            Spacer(minLength: 8)

            if let delta {
                deltaBadge(delta, isUp: isUp)
            }
        }
        .padding(.bottom, 4)
    }

    private func deltaBadge(_ delta: Double, isUp: Bool) -> some View {
        let tint: Color = isUp ? palette.negative : palette.positive

        return HStack(spacing: 2) {
            Image(systemName: isUp ? "arrow.up" : "arrow.down")
                .font(.system(size: 12, weight: .bold))
            Text(Money.format(abs(delta)))
                .font(.system(size: 13.5, weight: .semibold))
        }
        .foregroundStyle(tint)
    }

    private func secondaryLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(palette.secondaryLabel)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func periodTitle(_ period: Period) -> String {
        let date = period.interval.start
        switch granularity {
        case .dia:
            return TodayView.dayLabel(for: date)
        case .semana:
            return "Semana del " + date.formatted(.dateTime.day().month(.abbreviated)
                .locale(Locale(identifier: "es_PE")))
        case .mes, .rango:
            return Period.spanishMonthName(for: date)
        case .anio:
            return date.formatted(.dateTime.year())
        }
    }

    private func previousLabel() -> String {
        switch granularity {
        case .dia:    return "el día anterior"
        case .semana: return "la semana pasada"
        case .mes:    return "el mes pasado"
        case .anio:   return "el año pasado"
        case .rango:  return "el periodo anterior"
        }
    }

    private func averageLabel() -> String {
        switch granularity {
        case .dia:    return "Promedio diario de los últimos \(bucketCount) días"
        case .semana: return "Promedio semanal de las últimas \(bucketCount) semanas"
        case .mes:    return "Promedio mensual de los últimos \(bucketCount) meses"
        case .anio:   return "Promedio anual de los últimos \(bucketCount) años"
        case .rango:  return "Promedio del rango"
        }
    }

    // MARK: - Qué cambió

    private func changesSection(rhythm: Rhythm, previous: Period) -> some View {
        let changes = Array(rhythm.categoryChanges.prefix(5))

        return VStack(spacing: 8) {
            ShellSectionHeader(title: "Qué cambió vs. " + periodTitle(previous).lowercased())

            MovementCard {
                ForEach(Array(changes.enumerated()), id: \.element.id) { index, change in
                    let isUp = Money.cents(change.delta) > 0

                    HStack(spacing: 12) {
                        MovementIcon(icon: CategoryStyle.icon(for: change.category),
                                     color: CategoryStyle.color(for: change.category, accent: accent.color),
                                     size: 38)

                        Text(change.category)
                            .font(.system(size: 15.5, weight: .semibold))
                            .foregroundStyle(palette.label)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        HStack(spacing: 3) {
                            Image(systemName: isUp ? "arrow.up" : "arrow.down")
                                .font(.system(size: 11, weight: .bold))
                            Text(Money.format(abs(change.delta)))
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(isUp ? palette.negative : palette.positive)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)

                    if index < changes.count - 1 { MovementSeparator() }
                }
            }
        }
    }

    // MARK: - Suscripciones

    private func detectedSubscriptions(in period: Period) -> [DetectedSubscription] {
        let calendar = Period.calendar
        let range = period.interval
        var grouped: [String: [Expense]] = [:]
        for expense in expenses
        where expense.isSubscription && expense.date >= range.start && expense.date < range.end {
            grouped[expense.merchant, default: []].append(expense)
        }
        return grouped.compactMap { merchant, items -> DetectedSubscription? in
            guard let last = items.max(by: { $0.date < $1.date }) else { return nil }
            return DetectedSubscription(merchant: merchant,
                                        amount: Accounting.amountInPEN(last, fallbackRate: rate),
                                        dayOfMonth: calendar.component(.day, from: last.date))
        }
        .sorted { Money.cents($0.amount) > Money.cents($1.amount) }
    }

    private func subscriptionsSection(_ subscriptions: [DetectedSubscription]) -> some View {
        let total = Money.sum(subscriptions) { $0.amount }

        return VStack(spacing: 8) {
            ShellSectionHeader(title: "Suscripciones detectadas",
                               trailing: Money.format(total) + "/mes")

            MovementCard {
                ForEach(Array(subscriptions.enumerated()), id: \.element.id) { index, subscription in
                    HStack(spacing: 12) {
                        MovementIcon(icon: "arrow.triangle.2.circlepath", color: accent.color, size: 38)

                        Text(Accounting.displayName(subscription.merchant))
                            .font(.system(size: 15.5, weight: .semibold))
                            .foregroundStyle(palette.label)
                            .lineLimit(1)

                        Text("· día \(subscription.dayOfMonth)")
                            .font(.system(size: 12.5))
                            .foregroundStyle(palette.secondaryLabel)

                        Spacer(minLength: 6)

                        Text(Money.format(subscription.amount))
                            .font(.system(size: 15.5, weight: .semibold))
                            .foregroundStyle(palette.label)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)

                    if index < subscriptions.count - 1 { MovementSeparator() }
                }
            }
        }
    }
}
