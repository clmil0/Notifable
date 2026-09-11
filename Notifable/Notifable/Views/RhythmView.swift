import SwiftUI
import SwiftData

/// Ritmo. Sustituye a Tendencias.
///
/// Tendencias dibujaba un balance acumulado que nadie sabía leer, y además lo
/// dibujaba con `now` en vez del periodo navegado, así que al retroceder una
/// semana los números de arriba cambiaban y el gráfico no. Aquí todo sale de
/// `PeriodTotals`, y lo primero que se lee es una frase, no un eje.
/// Envoltorio: sólo lee el periodo guardado y se lo pasa al contenido.
///
/// Existe porque `@Query` se construye en el `init` y `@AppStorage` no se puede
/// leer desde ahí. Partir la vista en dos es lo que permite que la consulta a
/// la base esté **acotada al periodo visible** en lugar de traerse el historial
/// entero: al cambiar de periodo, `RhythmContent` se reconstruye con otro
/// descriptor y SwiftData recarga sólo ese tramo.
struct RhythmView: View {

    @Binding var scrollToTopTrigger: Bool
    @AppStorage("period") private var period = Period()

    var body: some View {
        RhythmContent(period: $period, scrollToTopTrigger: $scrollToTopTrigger)
    }
}

private struct RhythmContent: View {

    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @Environment(\.colorScheme) private var colorScheme

    @Binding var period: Period
    @Binding var scrollToTopTrigger: Bool

    @StateObject private var exchangeRateService = ExchangeRateService.shared
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue

    /// La ventana incluye el periodo anterior: `Rhythm` lo compara siempre, y
    /// sin él el titular diría "no hay con qué comparar" en vez de la frase.
    init(period: Binding<Period>, scrollToTopTrigger: Binding<Bool>) {
        self._period = period
        self._scrollToTopTrigger = scrollToTopTrigger

        // La tarjeta "Acumulado del mes" (2a/2b/2c) ancla siempre al mes
        // calendario completo, aunque el periodo visible sea una semana o un
        // día — así que la consulta tiene que traer ese mes entero, no sólo
        // lo que `dataWindow` acota para el periodo navegado.
        let period0 = period.wrappedValue
        let month = Period(granularity: .mes, reference: period0.reference).interval
        let window = period0.dataWindow(includingPrevious: true)
        let start = min(window.start, month.start)
        let end = max(window.end, month.end)
        _expenses = Query(filter: #Predicate<Expense> { $0.date >= start && $0.date < end },
                          sort: \Expense.date, order: .reverse)
        _incomes = Query(filter: #Predicate<Income> { $0.date >= start && $0.date < end },
                         sort: \Income.date, order: .reverse)
    }

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
                                           period: period.previous, usdToPen: rate),
               monthDailySpent: monthDailySpent)
    }

    /// Sólo se calcula para Día: es lo único que lo necesita, y evita el
    /// costo de armar `PeriodTotals` del mes entero en las demás vistas.
    /// `dataWindow(includingPrevious:)` ya carga ese mes para Día (lo
    /// necesita el scrubber), así que `expenses`/`incomes` ya lo traen.
    private var monthDailySpent: [PeriodTotals.DayTotal] {
        guard period.granularity == .dia else { return [] }
        let monthPeriod = Period(granularity: .mes, reference: period.reference)
        return Accounting.totals(expenses: expenses, incomes: incomes,
                                 period: monthPeriod, usdToPen: rate).dailySpent
    }

    private func dailySpent(for period: Period) -> [PeriodTotals.DayTotal] {
        Accounting.totals(expenses: expenses, incomes: incomes, period: period, usdToPen: rate).dailySpent
    }

    /// Suscripciones del periodo, una fila por comercio.
    private var subscriptions: [DetectedSubscription] {
        let cal = Period.calendar
        let range = period.interval
        var grouped: [String: [Expense]] = [:]
        for expense in expenses
        where expense.isSubscription && expense.date >= range.start && expense.date < range.end {
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
        TrackableScrollView(scrollToTopTrigger: $scrollToTopTrigger) {
            VStack(spacing: 16) {
                PeriodHeader(period: $period, dailySpent: dailySpent(for:))

                headline

                RhythmBarsChart(buckets: rhythm.chartBuckets,
                                average: rhythm.averagePerBucket,
                                grouping: rhythm.grouping,
                                granularity: period.granularity,
                                accent: accent.color,
                                todayColor: accent.isDuotone ? accent.secondaryColor : accent.color.opacity(0.55))

                twoCards

                if !rhythm.categoryChanges.isEmpty {
                    categoryChanges
                }

                if !subscriptions.isEmpty {
                    subscriptionsCard
                }

                Spacer(minLength: 100)
            }
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

    /// Sólo Día cambia la tarjeta derecha a "Acumulado del mes": un solo día
    /// no tiene "días sin gastar" que digan nada (0 de 1, o 1 de 1), así que
    /// ahí el acumulado del mes da más contexto. Semana y Mes sí tienen
    /// suficientes días propios para que "Días sin gastar" siga siendo la
    /// pregunta correcta, del periodo que se está viendo — así que se quedan
    /// con la tarjeta de siempre.
    private var usesMonthAccumulatedCard: Bool {
        period.granularity == .dia
    }

    private var twoCards: some View {
        HStack(spacing: 12) {
            firstCard
            if usesMonthAccumulatedCard {
                smallCard(title: "Acumulado del mes",
                          value: Money.format(monthToDateTotal),
                          detail: "desde el 1 de " + Period.spanishMonthName(for: period.reference, abbreviated: true).lowercased(),
                          icon: "chart.line.uptrend.xyaxis",
                          tint: palette.positive)
            } else {
                smallCard(title: "Días sin gastar",
                          value: "\(rhythm.daysWithoutSpending) de \(max(1, rhythm.elapsedDays.count))",
                          detail: comparisonDetail,
                          icon: "moon.zzz.fill",
                          tint: palette.positive)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var firstCard: some View {
        if period.granularity == .dia, let average = rhythm.sameWeekdayAverage {
            let percent = rhythm.sameWeekdayPercentDelta ?? 0
            let isMore = percent > 0
            smallCard(title: "Tu promedio los " + weekdayPluralName(period.reference),
                      value: Money.format(average),
                      detail: "\(abs(Int(percent.rounded())))% " + (isMore ? "más" : "menos") + " gastado",
                      icon: "flame.fill",
                      tint: palette.warning,
                      detailColor: isMore ? palette.negative : palette.positive)
        } else {
            smallCard(title: "Tu día más caro",
                      value: rhythm.busiestWeekday?.name ?? "—",
                      detail: rhythm.busiestWeekday.map { Money.format($0.average) + " de media" } ?? "Sin datos",
                      icon: "flame.fill",
                      tint: palette.warning)
        }
    }

    /// "Miércoles" → "miércoles"; domingo y sábado son los únicos que
    /// pluralizan con una "s" ("los domingos") — el resto ya sirve igual
    /// en singular y en plural ("los lunes", "los martes"…).
    private func weekdayPluralName(_ date: Date) -> String {
        let weekday = Period.calendar.component(.weekday, from: date)
        let name = Rhythm.weekdayName(weekday).lowercased()
        return (weekday == 1 || weekday == 7) ? name + "s" : name
    }

    /// Sólo se calcula para Mes/Semana/Día: es lo único que la usa. Sale del
    /// mes calendario que contiene el periodo visible, no del periodo en sí
    /// — por eso el mismo número se ve igual en Mes, Semana y Día.
    private var monthToDateTotal: Double {
        let monthPeriod = Period(granularity: .mes, reference: period.reference)
        return Accounting.totals(expenses: expenses, incomes: incomes,
                                 period: monthPeriod, usdToPen: rate).spent
    }

    private var comparisonDetail: String {
        let previous = rhythm.previousDaysWithoutSpending
        guard previous > 0 || rhythm.daysWithoutSpending > 0 else { return "Sin datos" }
        let diff = rhythm.daysWithoutSpending - previous
        if diff == 0 { return "igual que antes" }
        return diff > 0 ? "\(diff) más que antes" : "\(-diff) menos que antes"
    }

    private func smallCard(title: String, value: String, detail: String, icon: String, tint: Color,
                           detailColor: Color? = nil) -> some View {
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
                .foregroundStyle(detailColor ?? palette.secondaryLabel)
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
                                 palette: palette,
                                 downColor: accent.isDuotone ? accent.secondaryColor : palette.positive)
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
                        .foregroundStyle(accent.secondaryOnSurface(colorScheme))
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
    let granularity: PeriodGranularity
    let accent: Color
    let todayColor: Color

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

    /// Sólo Día y Semana: con 30 barras de Mes, un monto encima de cada una
    /// no cabe y sólo ensucia el gráfico.
    private var showsAmountLabels: Bool { granularity == .dia || granularity == .semana }

    /// Con etiqueta, la barra deja de llegar a 140 para que el monto no se
    /// recorte arriba — el `.clipped()` de `bars` corta lo que se pase de
    /// `chartHeight`.
    private var chartHeight: CGFloat { 140 }
    private var barMaxHeight: CGFloat { showsAmountLabels ? chartHeight - 18 : chartHeight }

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
                dayAxis
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
                    VStack(spacing: 3) {
                        if showsAmountLabels, !Money.isZero(bucket.total) {
                            Text(Money.formatCompact(bucket.total))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(labelColor(bucket))
                                .lineLimit(1)
                                .fixedSize()
                        }
                        RoundedRectangle(cornerRadius: barCorner, style: .continuous)
                            .fill(color(for: bucket))
                            .frame(height: max(2, barMaxHeight * fraction(for: bucket)))
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
            .frame(maxWidth: .infinity, alignment: .bottom)
            .frame(height: chartHeight, alignment: .bottom)

            if !Money.isZero(average), !Money.isZero(maxTotal) {
                let ratio = Money.ratio(average, to: maxTotal) ?? 0
                Rectangle()
                    .fill(palette.secondaryLabel.opacity(0.6))
                    .frame(height: 1)
                    .offset(y: -barMaxHeight * CGFloat(min(1, ratio)))
            }
        }
        .frame(height: chartHeight)
        .clipped()
    }

    private func fraction(for bucket: Rhythm.Bucket) -> CGFloat {
        guard let ratio = Money.ratio(bucket.total, to: maxTotal) else { return 0 }
        return CGFloat(min(1, ratio))
    }

    private func color(for bucket: Rhythm.Bucket) -> Color {
        if bucket.containsToday { return todayColor }
        return Money.isGreater(bucket.total, than: average) ? accent : palette.track
    }

    /// Cuatro referencias como mucho: primera, una intermedia, la actual y la
    /// última. Suficiente para orientarse sin llenar el eje de números. Sigue
    /// así para Año y Rango largo — Mes, Semana y Día tienen su propio eje
    /// (ver `dayAxis`), con un número por barra en vez de cuatro sueltos.
    private var sparseAxis: some View {
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

    // MARK: - Eje de Mes / Semana / Día

    @ViewBuilder
    private var dayAxis: some View {
        switch granularity {
        case .mes: monthAxis
        case .semana: weekAxis
        case .dia: dayOfWeekAxis
        case .anio, .rango: sparseAxis
        }
    }

    private func labelColor(_ bucket: Rhythm.Bucket) -> Color {
        if bucket.containsToday { return todayColor }
        if bucket.isFuture { return palette.secondaryLabel.opacity(0.4) }
        return palette.secondaryLabel
    }

    /// Un número por día, 1 al 30 — pero 30 números uno al lado del otro se
    /// pisan, así que se reparten en dos filas alternadas (impares arriba,
    /// pares abajo), igual que se leería un calendario de dos semanas.
    private var monthAxis: some View {
        VStack(spacing: 2) {
            HStack(spacing: spacing) {
                ForEach(Array(buckets.enumerated()), id: \.offset) { index, bucket in
                    monthDayLabel(bucket).opacity(index.isMultiple(of: 2) ? 1 : 0)
                }
            }
            HStack(spacing: spacing) {
                ForEach(Array(buckets.enumerated()), id: \.offset) { index, bucket in
                    monthDayLabel(bucket).opacity(index.isMultiple(of: 2) ? 0 : 1)
                }
            }
        }
    }

    private func monthDayLabel(_ bucket: Rhythm.Bucket) -> some View {
        Text(bucket.label)
            .font(.system(size: 10, weight: bucket.containsToday ? .bold : .regular, design: .monospaced))
            .foregroundStyle(labelColor(bucket))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity)
    }

    /// Número del día + inicial (L M X J V S D), como el resto de la app ya
    /// nombra los días de la semana (ver `DayScrubber`).
    private var weekAxis: some View {
        HStack(spacing: spacing) {
            ForEach(buckets) { bucket in
                VStack(spacing: 1) {
                    Text(bucket.label)
                        .font(.system(size: 11, weight: bucket.containsToday ? .bold : .regular))
                    Text(weekdayInitial(bucket.date))
                        .font(.system(size: 9))
                }
                .foregroundStyle(labelColor(bucket))
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// Número del día + nombre corto ("lun", "mar"), y "hoy" en vez del
    /// nombre para la barra de hoy — son sólo 2 o 3 barras, hay espacio de
    /// sobra para deletrearlo.
    private var dayOfWeekAxis: some View {
        HStack(spacing: spacing) {
            ForEach(buckets) { bucket in
                VStack(spacing: 1) {
                    Text(bucket.label)
                        .font(.system(size: 11, weight: bucket.containsToday ? .bold : .regular))
                    Text(bucket.containsToday ? "hoy" : weekdayShortName(bucket.date))
                        .font(.system(size: 9))
                }
                .foregroundStyle(labelColor(bucket))
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func weekdayInitial(_ date: Date) -> String {
        let names = ["L", "M", "X", "J", "V", "S", "D"]
        let weekday = Period.calendar.component(.weekday, from: date)
        return names[(weekday + 5) % 7]
    }

    private func weekdayShortName(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_PE")
        f.dateFormat = "EEE"
        return f.string(from: date).lowercased()
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
    /// Color de las categorías que bajaron (Acento 2 en temas pastel; el
    /// verde semántico de siempre en los demás). Las que suben se quedan en
    /// rojo siempre, para que "el gasto subió" se lea igual en cualquier tema.
    let downColor: Color

    private var isUp: Bool { Money.cents(change.delta) > 0 }
    private var fraction: CGFloat {
        guard let ratio = Money.ratio(abs(change.delta), to: largest) else { return 0 }
        return CGFloat(min(1, ratio))
    }
    private var color: Color { isUp ? palette.negative : downColor }

    var body: some View {
        HStack(spacing: 10) {
            Text(change.category)
                .font(.footnote)
                .foregroundStyle(palette.label)
                .lineLimit(1)
                .frame(width: 80, alignment: .leading)

            // Pista fija: todas las barras crecen hacia la derecha desde el
            // mismo cero, así ninguna se sale de la pantalla y siguen siendo
            // proporcionales entre sí — sólo el color dice si subió o bajó.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.track)
                    Capsule()
                        .fill(color)
                        .frame(width: max(2, geo.size.width * fraction))
                }
            }
            .frame(height: 10)

            Text((isUp ? "+" : "−") + Money.format(abs(change.delta)))
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 66, alignment: .trailing)
        }
    }
}
