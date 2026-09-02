import SwiftUI
import SwiftData
import Charts

struct TrendDataPoint: Identifiable {
    let id = UUID()
    let label: String
    let date: Date
    let amount: Double
    let type: String // "Gastos" or "Ingresos"
}

struct TrendsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \Income.date, order: .reverse) private var incomes: [Income]
    @Environment(\.colorScheme) var colorScheme
    
    @Binding var scrollOffset: CGFloat
    @Binding var scrollToTopTrigger: Bool
    
    @StateObject private var exchangeRateService = ExchangeRateService.shared
    
    /// El mismo `Period` que Resumen y Categorías.
    @AppStorage("period") private var period = Period()
    
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.purple.rawValue
    
    var themeColor: Color { AppThemeColor(rawValue: appAccentColor)?.color ?? .purple }
    
    // MARK: - Totales
    //
    // Todo se deriva de `PeriodTotals`, que a su vez se deriva de `Period.days`.
    // Antes los gráficos se construían con `now` en lugar del periodo navegado,
    // así que al retroceder una semana los números de arriba cambiaban pero el
    // gráfico seguía dibujando la semana actual (ACCOUNTING.md §11). Ahora es
    // imposible desincronizarlos: no hay dos fuentes.
    
    var rate: Double { exchangeRateService.usdToPenRate }
    
    var totals: PeriodTotals {
        Accounting.totals(expenses: expenses, incomes: incomes, period: period, usdToPen: rate)
    }
    
    var previousTotals: PeriodTotals {
        Accounting.totals(expenses: expenses, incomes: incomes, period: period.previous, usdToPen: rate)
    }
    
    func dailySpent(for period: Period) -> [PeriodTotals.DayTotal] {
        Accounting.totals(expenses: expenses, incomes: incomes, period: period, usdToPen: rate).dailySpent
    }
    
    var filteredIncomes: [Income] {
        incomes.filter { period.contains($0.date) }
    }
    
    var totalCurrentPEN: Double { totals.spent }
    var totalPreviousPEN: Double { previousTotals.spent }
    /// Sin abonos a deuda: antes esta vista los sumaba como ingreso y Resumen no
    /// (ACCOUNTING.md §3), así que "Gasto/Ingreso" salía inflado.
    var totalCurrentIncomePEN: Double { totals.income }
    
    // MARK: - Chart Data
    
    /// Balance acumulado del periodo. Un punto por día (por hora si el periodo
    /// es un solo día), siempre dentro del periodo navegado.
    var trendData: [TrendDataPoint] {
        period.granularity == .dia ? hourlyBalance : dailyBalance
    }
    
    private var dailyBalance: [TrendDataPoint] {
        let cal = Period.calendar
        let now = Date()
        var incomeByDay: [Date: Int] = [:]
        for income in filteredIncomes where !income.isDebtPayment {
            incomeByDay[cal.startOfDay(for: income.date), default: 0] += Accounting.penCents(income.accountingSnapshot, fallbackRate: rate)
        }
        
        var cumulative = 0
        var points: [TrendDataPoint] = []
        for day in totals.dailySpent {
            if day.date > now { break }
            cumulative += (incomeByDay[day.date] ?? 0) - Money.cents(day.total)
            points.append(TrendDataPoint(label: "\(cal.component(.day, from: day.date))",
                                         date: day.date,
                                         amount: Money.value(cumulative),
                                         type: "Balance"))
        }
        return points
    }
    
    private var hourlyBalance: [TrendDataPoint] {
        let cal = Period.calendar
        let interval = period.interval
        let now = Date()
        let lastHour = period.isCurrent ? cal.component(.hour, from: now) : 23
        
        var expenseByHour: [Int: Int] = [:]
        for expense in expenses where period.contains(expense.date) {
            expenseByHour[cal.component(.hour, from: expense.date), default: 0] += Accounting.penCents(expense.accountingSnapshot, fallbackRate: rate)
        }
        var incomeByHour: [Int: Int] = [:]
        for income in filteredIncomes where !income.isDebtPayment {
            incomeByHour[cal.component(.hour, from: income.date), default: 0] += Accounting.penCents(income.accountingSnapshot, fallbackRate: rate)
        }
        
        var cumulative = 0
        var points: [TrendDataPoint] = []
        for hour in 0...max(0, lastHour) {
            guard let date = cal.date(byAdding: .hour, value: hour, to: interval.start) else { continue }
            cumulative += (incomeByHour[hour] ?? 0) - (expenseByHour[hour] ?? 0)
            points.append(TrendDataPoint(label: "\(hour)h", date: date,
                                         amount: Money.value(cumulative), type: "Balance"))
        }
        return points
    }
    
    // MARK: - Stats
    
    var avgDailyExpense: Double { totals.averagePerDay }
    
    /// El día del periodo con más gasto.
    var peakDay: (label: String, amount: Double)? {
        guard let top = totals.dailySpent.max(by: { Money.cents($0.total) < Money.cents($1.total) }),
              !Money.isZero(top.total) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_PE")
        f.dateFormat = period.granularity == .anio ? "d MMM" : "EEE d"
        return (f.string(from: top.date).capitalizedFirst, top.total)
    }
    
    var largestIncome: Double {
        filteredIncomes
            .filter { !$0.isDebtPayment }
            .map { Accounting.amountInPEN($0, fallbackRate: rate) }
            .max() ?? 0
    }
    
    /// `nil` cuando no hay ingresos: la tarjeta muestra "—" en vez de "nan%".
    var spendingRatio: Double? { Money.percent(totalCurrentPEN, of: totalCurrentIncomePEN) }
    
    var percentageChange: Double? {
        guard period.granularity != .rango else { return nil }
        guard let ratio = Money.ratio(Money.subtract(totalCurrentPEN, totalPreviousPEN), to: totalPreviousPEN) else { return nil }
        return ratio * 100
    }
    
    // MARK: - Body
    
    var body: some View {
        TrackableScrollView(scrollOffset: $scrollOffset, scrollToTopTrigger: $scrollToTopTrigger) {
            VStack(spacing: 24) {
                PeriodHeader(period: $period, dailySpent: dailySpent(for:))
                
                // Gráfica Principal
                trendChartView
                
                // Stats Cards
                statsCardsView
                
                // Comparación con período anterior
                if let change = percentageChange {
                    comparisonView(change: change)
                }
                
                Spacer(minLength: 100)
            }
        }
    }
    
    // MARK: - Chart View
    
    private var trendChartView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Flujo de Dinero")
                    .font(.headline)
                Spacer()
                
                // Legend
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.blue).frame(width: 8, height: 8)
                        Text("Balance Acumulado").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            
            Chart(trendData) { point in
                LineMark(
                    x: .value("Período", point.date),
                    y: .value("Monto", point.amount)
                )
                .foregroundStyle(Color.blue)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                
                AreaMark(
                    x: .value("Período", point.date),
                    y: .value("Monto", point.amount)
                )
                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.3), Color.clear]), startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
            }
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: xAxisDesiredCount)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(xAxisLabel(for: date))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                    AxisValueLabel {
                        if let val = value.as(Double.self) {
                            Text(Money.formatCompact(val))
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 220)
            
            // Current day indicator for weekly view
            if period.granularity == .semana && period.isCurrent {
                let calendar = Calendar.current
                let weekday = calendar.component(.weekday, from: Date())
                let dayNames = ["", "Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"]
                let todayName = dayNames[weekday]
                
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Circle().fill(Color.yellow).frame(width: 6, height: 6)
                        Text("Hoy: \(todayName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal)
    }
    
    private var xAxisDesiredCount: Int {
        switch period.granularity {
        case .dia: return 6
        case .semana: return 7
        case .mes: return 8
        case .anio: return 12
        case .rango: return min(max(2, period.totalDays), 10)
        }
    }
    
    private func xAxisLabel(for date: Date) -> String {
        let cal = Period.calendar
        switch period.granularity {
        case .dia:
            return "\(cal.component(.hour, from: date))h"
        case .semana:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "es_PE")
            formatter.dateFormat = "EEE"
            return String(formatter.string(from: date).prefix(3)).capitalizedFirst
        case .anio:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "es_PE")
            formatter.dateFormat = "MMM"
            return formatter.string(from: date).capitalizedFirst
        case .mes, .rango:
            return "\(cal.component(.day, from: date))"
        }
    }
    
    // MARK: - Stats Cards
    
    private var statsCardsView: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard(
                title: "Promedio Diario",
                value: Money.format(avgDailyExpense),
                icon: "chart.bar.fill",
                color: themeColor
            )
            
            statCard(
                title: "Día Pico",
                value: peakDay.map { "\($0.label): " + Money.formatCompact($0.amount) } ?? "—",
                icon: "flame.fill",
                color: .orange
            )
            
            statCard(
                title: "Mayor Ingreso",
                value: Money.isZero(largestIncome) ? "—" : Money.format(largestIncome),
                icon: "arrow.down.left.circle.fill",
                color: .green
            )
            
            statCard(
                title: "Gasto/Ingreso",
                value: Money.formatPercent(totalCurrentPEN, of: totalCurrentIncomePEN),
                icon: "percent",
                color: (spendingRatio ?? 0) > 100 ? .red : .blue
            )
        }
        .padding(.horizontal)
    }
    
    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.subheadline)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            
            Text(value)
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    // MARK: - Comparison View
    
    private func comparisonView(change: Double) -> some View {
        let isLess = change < 0
        let absChange = abs(change)
        let periodLabel = period.granularity.previousLabel
        
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isLess ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: isLess ? "arrow.down.right" : "arrow.up.right")
                    .font(.title3.bold())
                    .foregroundStyle(isLess ? .green : .red)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(isLess ? "Gastaste menos" : "Gastaste más")
                    .font(.subheadline.bold())
                
                Text(String(format: "%.1f", absChange) + "% \(isLess ? "menos" : "más") que \(periodLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text("\(isLess ? "-" : "+")" + String(format: "%.1f", absChange) + "%")
                .font(.title3.bold())
                .foregroundStyle(isLess ? .green : .red)
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }
}

#Preview {
    TrendsView(scrollOffset: .constant(100), scrollToTopTrigger: .constant(false))
        .modelContainer(for: [Expense.self, Income.self], inMemory: true)
}
