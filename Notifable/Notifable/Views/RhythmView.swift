import SwiftUI
import SwiftData

/// Ritmo. Sustituye a Tendencias.
///
/// Tendencias dibujaba un balance acumulado que nadie sabía leer, y además lo
/// dibujaba con `now` en vez del periodo navegado, así que al retroceder una
/// semana los números de arriba cambiaban y el gráfico no. Aquí todo sale de
/// `PeriodTotals`, y lo primero que se lee es una frase, no un eje.
struct RhythmView: View {

    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \Income.date, order: .reverse) private var incomes: [Income]
    @Environment(\.colorScheme) private var colorScheme

    @Binding var scrollOffset: CGFloat
    @Binding var scrollToTopTrigger: Bool

    @StateObject private var exchangeRateService = ExchangeRateService.shared
    @AppStorage("period") private var period = Period()
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue

    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .purple }
    private var palette: Palette { Palette(colorScheme) }
    private var rate: Double { exchangeRateService.usdToPenRate }

    // MARK: - Datos

    private var totals: PeriodTotals {
        Accounting.totals(expenses: expenses, incomes: incomes, period: period, usdToPen: rate)
    }

    private var rhythm: Rhythm {
        Rhythm(period: period,
               current: totals,
               previous: Accounting.totals(expenses: expenses, incomes: incomes,
                                           period: period.previous, usdToPen: rate))
    }

    private func dailySpent(for period: Period) -> [PeriodTotals.DayTotal] {
        Accounting.totals(expenses: expenses, incomes: incomes, period: period, usdToPen: rate).dailySpent
    }

    /// Suscripciones del periodo, una fila por comercio.
    private var subscriptions: [DetectedSubscription] {
        let cal = Period.calendar
        var grouped: [String: [Expense]] = [:]
        for expense in expenses where expense.isSubscription && period.contains(expense.date) {
            grouped[expense.merchant, default: []].append(expense)
        }
        return grouped
            .compactMap { merchant, items -> DetectedSubscription? in
                guard let last = items.max(by: { $0.date < $1.date }) else { return nil }
                return DetectedSubscription(
                    merchant: merchant,
                    amount: Accounting.amountInPEN(last, fallbackRate: rate),
                    dayOfMonth: cal.component(.day, from: last.date)
                )
            }
            .sorted {
                Money.cents($0.amount) == Money.cents($1.amount)
                    ? $0.merchant < $1.merchant
                    : Money.cents($0.amount) > Money.cents($1.amount)
            }
    }

    // MARK: - Cuerpo

    var body: some View {
        TrackableScrollView(scrollOffset: $scrollOffset, scrollToTopTrigger: $scrollToTopTrigger) {
            VStack(spacing: 16) {
                PeriodHeader(period: $period, dailySpent: dailySpent(for:))

                headline

                RhythmBarsChart(buckets: rhythm.chartBuckets,
                                average: rhythm.averagePerBucket,
                                grouping: rhythm.grouping,
                                accent: accent.color)

                twoCards

                if !rhythm.categoryChanges.isEmpty {
                    categoryChanges
                }

                if !subscriptions.isEmpty {
                    subscriptionsCard
                }

                Spacer(minLength: 100)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Titular

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(rhythm.headline)
                .font(.title2.bold())
                .foregroundStyle(palette.label)
                .fixedSize(horizontal: false, vertical: true)

            if let support = rhythm.supportLine {
                Text(support)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    // MARK: - Dos tarjetas

    private var twoCards: some View {
        HStack(spacing: 12) {
            smallCard(title: "Tu día más caro",
                      value: rhythm.busiestWeekday?.name ?? "—",
                      detail: rhythm.busiestWeekday.map { Money.format($0.average) + " de media" } ?? "Sin datos",
                      icon: "flame.fill",
                      tint: palette.warning)

            smallCard(title: "Días sin gastar",
                      value: "\(rhythm.daysWithoutSpending) de \(max(1, rhythm.elapsedDays.count))",
                      detail: comparisonDetail,
                      icon: "moon.zzz.fill",
                      tint: palette.positive)
        }
        .padding(.horizontal, 16)
    }

    private var comparisonDetail: String {
        let previous = rhythm.previousDaysWithoutSpending
        guard previous > 0 || rhythm.daysWithoutSpending > 0 else { return "Sin datos" }
        let diff = rhythm.daysWithoutSpending - previous
        if diff == 0 { return "igual que antes" }
        return diff > 0 ? "\(diff) más que antes" : "\(-diff) menos que antes"
    }

    private func smallCard(title: String, value: String, detail: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.footnote)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
            }
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(palette.label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(radius: 16)
    }

    // MARK: - Qué cambió

    private var categoryChanges: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Qué cambió vs. " + period.granularity.previousLabel)
                .font(.headline)
                .foregroundStyle(palette.label)

            ForEach(rhythm.categoryChanges.prefix(6)) { change in
                CategoryDeltaRow(change: change,
                                 largest: rhythm.largestChange,
                                 palette: palette)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(radius: 20)
        .padding(.horizontal, 16)
    }

    // MARK: - Suscripciones

    private var subscriptionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suscripciones detectadas")
                .font(.headline)
                .foregroundStyle(palette.label)

            ForEach(subscriptions) { subscription in
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.footnote)
                        .foregroundStyle(accent.onSurface(colorScheme))
                    Text(Accounting.displayName(subscription.merchant))
                        .font(.subheadline)
                        .foregroundStyle(palette.label)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("día \(subscription.dayOfMonth)")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                    Text(Money.format(subscription.amount))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.label)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(radius: 20)
        .padding(.horizontal, 16)
    }
}

// MARK: - Gráfico de barras

/// Barras con la línea de promedio. Las que superan el promedio van en acento
/// pleno; el resto, apagadas. Es la lectura que se busca: cuáles se salieron.
///
/// La unidad de cada barra la decide `Rhythm.grouping`: un día en el mes, un mes
/// en el año. Dibujar 365 barras de ancho fijo no cabe en la pantalla —ése era
/// el desbordamiento al filtrar por año— y además no se lee.
struct RhythmBarsChart: View {

    let buckets: [Rhythm.Bucket]
    let average: Double
    let grouping: Rhythm.Grouping
    let accent: Color

    @Environment(\.colorScheme) private var scheme
    private var palette: Palette { Palette(scheme) }

    private var maxTotal: Double { buckets.map(\.total).max() ?? 0 }

    /// Con muchas barras la separación se encoge; si no, la suma de huecos
    /// arrastra la fila más allá del ancho disponible.
    private var spacing: CGFloat {
        switch buckets.count {
        case ..<16: return 4
        case ..<32: return 3
        case ..<60: return 2
        default: return 1
        }
    }

    private var barCorner: CGFloat { buckets.count > 40 ? 1 : 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(grouping.unitTitle)
                    .font(.headline)
                    .foregroundStyle(palette.label)
                Spacer()
                Text(grouping.averageLabel + " " + Money.format(average))
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            if buckets.isEmpty {
                Text("Aún no hay nada que dibujar en este periodo.")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                bars
                axis
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(radius: 20)
        .padding(.horizontal, 16)
    }

    private var bars: some View {
        ZStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(buckets) { bucket in
                    RoundedRectangle(cornerRadius: barCorner, style: .continuous)
                        .fill(color(for: bucket))
                        .frame(height: max(2, 140 * fraction(for: bucket)))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .bottom)
            .frame(height: 140, alignment: .bottom)

            if !Money.isZero(average), !Money.isZero(maxTotal) {
                let ratio = Money.ratio(average, to: maxTotal) ?? 0
                Rectangle()
                    .fill(palette.secondaryLabel.opacity(0.6))
                    .frame(height: 1)
                    .offset(y: -140 * CGFloat(min(1, ratio)))
            }
        }
        .frame(height: 140)
        .clipped()
    }

    private func fraction(for bucket: Rhythm.Bucket) -> CGFloat {
        guard let ratio = Money.ratio(bucket.total, to: maxTotal) else { return 0 }
        return CGFloat(min(1, ratio))
    }

    private func color(for bucket: Rhythm.Bucket) -> Color {
        if bucket.containsToday { return accent.opacity(0.55) }
        return Money.isGreater(bucket.total, than: average) ? accent : palette.track
    }

    /// Cuatro referencias como mucho: primera, una intermedia, la actual y la
    /// última. Suficiente para orientarse sin llenar el eje de números.
    private var axis: some View {
        HStack(spacing: 0) {
            ForEach(axisLabels, id: \.self) { label in
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryLabel)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var axisLabels: [String] {
        guard let first = buckets.first, let last = buckets.last else { return [] }
        var labels: [String] = [first.label]
        if buckets.count > 6 {
            labels.append(buckets[buckets.count / 2].label)
        }
        if let today = buckets.first(where: { $0.containsToday }) {
            labels.append(today.label + " (hoy)")
        }
        if buckets.count > 1 { labels.append(last.label) }

        var seen: Set<String> = []
        return labels.filter { seen.insert($0).inserted }
    }
}

// MARK: - Fila de cambio por categoría

/// Barra centrada en cero: crece a la derecha en rojo si la categoría subió, a
/// la izquierda en verde si bajó. El cero compartido es lo que deja comparar de
/// un vistazo sin leer los números.
struct CategoryDeltaRow: View {

    let change: Rhythm.CategoryChange
    let largest: Double
    let palette: Palette

    private var isUp: Bool { Money.cents(change.delta) > 0 }
    private var fraction: CGFloat {
        guard let ratio = Money.ratio(abs(change.delta), to: largest) else { return 0 }
        return CGFloat(min(1, ratio))
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(change.category)
                .font(.footnote)
                .foregroundStyle(palette.label)
                .lineLimit(1)
                .frame(width: 88, alignment: .leading)

            GeometryReader { geo in
                let half = geo.size.width / 2
                ZStack(alignment: .center) {
                    Rectangle()
                        .fill(palette.separator)
                        .frame(width: 1)

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(isUp ? palette.negative : palette.positive)
                        .frame(width: max(2, half * fraction), height: 10)
                        .offset(x: offset(half: half))
                }
                .frame(height: 14)
            }
            .frame(height: 14)

            Text((isUp ? "+" : "−") + Money.format(abs(change.delta)))
                .font(.caption.weight(.semibold))
                .foregroundStyle(isUp ? palette.negative : palette.positive)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 66, alignment: .trailing)
        }
    }

    private func offset(half: CGFloat) -> CGFloat {
        let width = max(2, half * fraction)
        return isUp ? width / 2 : -width / 2
    }
}
