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
    
    @AppStorage("dashboardFilter") private var selectedFilter: DashboardFilter = .mes
    @AppStorage("categoriesFilter") private var categoriesFilter: DashboardFilter = .mes
    @AppStorage("syncFilters") private var syncFilters = true
    
    @State private var showRangePicker = false
    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate: Date = Date()
    
    // MARK: - Filtered Data
    
    var filteredExpenses: [Expense] {
        let calendar = Calendar.current
        let now = Date()
        
        return expenses.filter { expense in
            switch selectedFilter {
            case .hoy:
                return calendar.isDateInToday(expense.date)
            case .semana:
                var cal = Calendar.current
                cal.firstWeekday = 2
                if let interval = cal.dateInterval(of: .weekOfYear, for: now) {
                    return expense.date >= interval.start && expense.date <= interval.end
                }
                return true
            case .mes:
                if let interval = calendar.dateInterval(of: .month, for: now) {
                    return expense.date >= interval.start && expense.date <= interval.end
                }
                return true
            case .rango:
                let start = calendar.startOfDay(for: startDate)
                let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate
                return expense.date >= start && expense.date <= end
            }
        }
    }
    
    var filteredIncomes: [Income] {
        let calendar = Calendar.current
        let now = Date()
        
        return incomes.filter { income in
            switch selectedFilter {
            case .hoy:
                return calendar.isDateInToday(income.date)
            case .semana:
                var cal = Calendar.current
                cal.firstWeekday = 2
                if let interval = cal.dateInterval(of: .weekOfYear, for: now) {
                    return income.date >= interval.start && income.date <= interval.end
                }
                return true
            case .mes:
                if let interval = calendar.dateInterval(of: .month, for: now) {
                    return income.date >= interval.start && income.date <= interval.end
                }
                return true
            case .rango:
                let start = calendar.startOfDay(for: startDate)
                let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate
                return income.date >= start && income.date <= end
            }
        }
    }
    
    // Previous period
    var previousPeriodExpenses: [Expense] {
        let calendar = Calendar.current
        let now = Date()
        
        return expenses.filter { expense in
            switch selectedFilter {
            case .hoy:
                return calendar.isDateInYesterday(expense.date)
            case .semana:
                var cal = Calendar.current
                cal.firstWeekday = 2
                if let currentInterval = cal.dateInterval(of: .weekOfYear, for: now),
                   let prevWeekDate = cal.date(byAdding: .weekOfYear, value: -1, to: currentInterval.start),
                   let prevInterval = cal.dateInterval(of: .weekOfYear, for: prevWeekDate) {
                    return expense.date >= prevInterval.start && expense.date < prevInterval.end
                }
                return false
            case .mes:
                if let currentInterval = calendar.dateInterval(of: .month, for: now),
                   let prevMonthDate = calendar.date(byAdding: .month, value: -1, to: currentInterval.start),
                   let prevInterval = calendar.dateInterval(of: .month, for: prevMonthDate) {
                    return expense.date >= prevInterval.start && expense.date < prevInterval.end
                }
                return false
            case .rango:
                return false
            }
        }
    }
    
    func amountInPEN(_ expense: Expense) -> Double {
        expense.currency == "USD" ? expense.amount * exchangeRateService.usdToPenRate : expense.amount
    }
    
    func incomeInPEN(_ income: Income) -> Double {
        income.currency == "USD" ? income.amount * exchangeRateService.usdToPenRate : income.amount
    }
    
    var totalCurrentPEN: Double {
        filteredExpenses.reduce(0) { $0 + amountInPEN($1) }
    }
    
    var totalPreviousPEN: Double {
        previousPeriodExpenses.reduce(0) { $0 + amountInPEN($1) }
    }
    
    var totalCurrentIncomePEN: Double {
        filteredIncomes.reduce(0) { $0 + incomeInPEN($1) }
    }
    
    // MARK: - Chart Data
    
    var trendData: [TrendDataPoint] {
        let calendar = Calendar.current
        let now = Date()
        
        switch selectedFilter {
        case .hoy:
            return buildHourlyData(calendar: calendar, now: now)
        case .semana:
            return buildWeeklyData(calendar: calendar, now: now)
        case .mes:
            return buildMonthlyData(calendar: calendar, now: now)
        case .rango:
            return buildRangeData(calendar: calendar)
        }
    }
    
    private func buildHourlyData(calendar: Calendar, now: Date) -> [TrendDataPoint] {
        var points: [TrendDataPoint] = []
        let startOfDay = calendar.startOfDay(for: now)
        let currentHour = calendar.component(.hour, from: now)
        
        for hour in 0...currentHour {
            guard let hourDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: startOfDay) else { continue }
            
            let expenseTotal = filteredExpenses
                .filter { calendar.component(.hour, from: $0.date) == hour }
                .reduce(0) { $0 + amountInPEN($1) }
            
            let incomeTotal = filteredIncomes
                .filter { calendar.component(.hour, from: $0.date) == hour }
                .reduce(0) { $0 + incomeInPEN($1) }
            
            let label = "\(hour)h"
            points.append(TrendDataPoint(label: label, date: hourDate, amount: expenseTotal, type: "Gastos"))
            points.append(TrendDataPoint(label: label, date: hourDate, amount: incomeTotal, type: "Ingresos"))
        }
        return points
    }
    
    private func buildWeeklyData(calendar: Calendar, now: Date) -> [TrendDataPoint] {
        var points: [TrendDataPoint] = []
        var cal = Calendar.current
        cal.firstWeekday = 2
        
        guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: now) else { return [] }
        let dayNames = ["Lun", "Mar", "Mié", "Jue", "Vie", "Sáb", "Dom"]
        
        for dayIndex in 0..<7 {
            guard let dayDate = cal.date(byAdding: .day, value: dayIndex, to: weekInterval.start) else { continue }
            let startOfDay = cal.startOfDay(for: dayDate)
            let endOfDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: dayDate) ?? dayDate
            
            let expenseTotal = filteredExpenses
                .filter { $0.date >= startOfDay && $0.date <= endOfDay }
                .reduce(0) { $0 + amountInPEN($1) }
            
            let incomeTotal = filteredIncomes
                .filter { $0.date >= startOfDay && $0.date <= endOfDay }
                .reduce(0) { $0 + incomeInPEN($1) }
            
            let label = dayNames[dayIndex]
            points.append(TrendDataPoint(label: label, date: dayDate, amount: expenseTotal, type: "Gastos"))
            points.append(TrendDataPoint(label: label, date: dayDate, amount: incomeTotal, type: "Ingresos"))
        }
        return points
    }
    
    private func buildMonthlyData(calendar: Calendar, now: Date) -> [TrendDataPoint] {
        var points: [TrendDataPoint] = []
        
        guard let monthInterval = calendar.dateInterval(of: .month, for: now) else { return [] }
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let currentDay = calendar.component(.day, from: now)
        
        for day in 1...daysInMonth {
            guard let dayDate = calendar.date(bySetting: .day, value: day, of: monthInterval.start) else { continue }
            let startOfDay = calendar.startOfDay(for: dayDate)
            guard let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: dayDate) else { continue }
            
            let expenseTotal: Double
            let incomeTotal: Double
            
            if day <= currentDay {
                expenseTotal = filteredExpenses
                    .filter { $0.date >= startOfDay && $0.date <= endOfDay }
                    .reduce(0) { $0 + amountInPEN($1) }
                
                incomeTotal = filteredIncomes
                    .filter { $0.date >= startOfDay && $0.date <= endOfDay }
                    .reduce(0) { $0 + incomeInPEN($1) }
            } else {
                expenseTotal = 0
                incomeTotal = 0
            }
            
            let label = "\(day)"
            points.append(TrendDataPoint(label: label, date: dayDate, amount: expenseTotal, type: "Gastos"))
            points.append(TrendDataPoint(label: label, date: dayDate, amount: incomeTotal, type: "Ingresos"))
        }
        return points
    }
    
    private func buildRangeData(calendar: Calendar) -> [TrendDataPoint] {
        var points: [TrendDataPoint] = []
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        
        var current = start
        while current <= end {
            let startOfDay = current
            let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: current) ?? current
            
            let expenseTotal = filteredExpenses
                .filter { $0.date >= startOfDay && $0.date <= endOfDay }
                .reduce(0) { $0 + amountInPEN($1) }
            
            let incomeTotal = filteredIncomes
                .filter { $0.date >= startOfDay && $0.date <= endOfDay }
                .reduce(0) { $0 + incomeInPEN($1) }
            
            let day = calendar.component(.day, from: current)
            let label = "\(day)"
            points.append(TrendDataPoint(label: label, date: current, amount: expenseTotal, type: "Gastos"))
            points.append(TrendDataPoint(label: label, date: current, amount: incomeTotal, type: "Ingresos"))
            
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current.addingTimeInterval(86400)
        }
        return points
    }
    
    // MARK: - Stats
    
    var avgDailyExpense: Double {
        let calendar = Calendar.current
        let now = Date()
        let days: Int
        switch selectedFilter {
        case .hoy: days = 1
        case .semana:
            let weekday = calendar.component(.weekday, from: now)
            let adjustedDay = (weekday + 5) % 7 + 1 // Monday = 1
            days = adjustedDay
        case .mes:
            days = calendar.component(.day, from: now)
        case .rango:
            days = max(1, calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 1)
        }
        return days > 0 ? totalCurrentPEN / Double(days) : 0
    }
    
    var peakDay: (label: String, amount: Double) {
        let gastos = trendData.filter { $0.type == "Gastos" && $0.amount > 0 }
        guard let peak = gastos.max(by: { $0.amount < $1.amount }) else {
            return ("—", 0)
        }
        return (peak.label, peak.amount)
    }
    
    var largestIncome: Double {
        filteredIncomes.map { incomeInPEN($0) }.max() ?? 0
    }
    
    var spendingRatio: Double {
        guard totalCurrentIncomePEN > 0 else { return 0 }
        return (totalCurrentPEN / totalCurrentIncomePEN) * 100
    }
    
    var percentageChange: Double? {
        guard selectedFilter == .semana || selectedFilter == .mes else { return nil }
        guard totalPreviousPEN > 0 else { return nil }
        return ((totalCurrentPEN - totalPreviousPEN) / totalPreviousPEN) * 100
    }
    
    // MARK: - Body
    
    var body: some View {
        TrackableScrollView(scrollOffset: $scrollOffset, scrollToTopTrigger: $scrollToTopTrigger) {
            VStack(spacing: 24) {
                // Filtros
                HStack(spacing: 8) {
                    ForEach(DashboardFilter.allCases, id: \.self) { filter in
                        Button {
                            withAnimation(.spring) {
                                selectedFilter = filter
                                if syncFilters {
                                    categoriesFilter = filter
                                }
                                if filter == .rango {
                                    showRangePicker = true
                                }
                            }
                        } label: {
                            Text(filter.rawValue)
                                .font(.subheadline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .fontWeight(selectedFilter == filter ? .semibold : .regular)
                                .foregroundStyle(selectedFilter == filter ? .white : (colorScheme == .dark ? .white : .black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(selectedFilter == filter ? Color.purple.opacity(0.8) : Color.primary.opacity(0.05))
                                )
                        }
                    }
                }
                .padding(.horizontal)
                
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
        .sheet(isPresented: $showRangePicker) {
            NavigationStack {
                Form {
                    Section(header: Text("Selecciona el rango de fechas")) {
                        DatePicker("Desde", selection: $startDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                        DatePicker("Hasta", selection: $endDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                    }
                }
                .navigationTitle("Rango de Fechas")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Aplicar") { showRangePicker = false }
                    }
                }
                .preferredColorScheme(.dark)
            }
            .presentationDetents([.fraction(0.4)])
            .presentationDragIndicator(.visible)
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
                        Circle().fill(Color.purple).frame(width: 8, height: 8)
                        Text("Gastos").font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text("Ingresos").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            
            Chart(trendData) { point in
                LineMark(
                    x: .value("Período", point.date),
                    y: .value("Monto", point.amount)
                )
                .foregroundStyle(by: .value("Tipo", point.type))
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                
                AreaMark(
                    x: .value("Período", point.date),
                    y: .value("Monto", point.amount)
                )
                .foregroundStyle(by: .value("Tipo", point.type))
                .interpolationMethod(.catmullRom)
                .opacity(0.1)
            }
            .chartForegroundStyleScale([
                "Gastos": Color.purple,
                "Ingresos": Color.green
            ])
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
                            Text("S/\(val, specifier: "%.0f")")
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 220)
            
            // Current day indicator for weekly view
            if selectedFilter == .semana {
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
        switch selectedFilter {
        case .hoy: return 6
        case .semana: return 7
        case .mes: return 8
        case .rango:
            let calendar = Calendar.current
            let days = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 7
            return min(days, 10)
        }
    }
    
    private func xAxisLabel(for date: Date) -> String {
        let calendar = Calendar.current
        switch selectedFilter {
        case .hoy:
            let hour = calendar.component(.hour, from: date)
            return "\(hour)h"
        case .semana:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "es_PE")
            formatter.dateFormat = "EEE"
            let str = formatter.string(from: date)
            return str.prefix(3).capitalized
        case .mes, .rango:
            let day = calendar.component(.day, from: date)
            return "\(day)"
        }
    }
    
    // MARK: - Stats Cards
    
    private var statsCardsView: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard(
                title: "Promedio Diario",
                value: "S/ " + String(format: "%.2f", avgDailyExpense),
                icon: "chart.bar.fill",
                color: .purple
            )
            
            statCard(
                title: "Día Pico",
                value: peakDay.amount > 0 ? "\(peakDay.label): S/" + String(format: "%.0f", peakDay.amount) : "—",
                icon: "flame.fill",
                color: .orange
            )
            
            statCard(
                title: "Mayor Ingreso",
                value: largestIncome > 0 ? "S/ " + String(format: "%.2f", largestIncome) : "—",
                icon: "arrow.down.left.circle.fill",
                color: .green
            )
            
            statCard(
                title: "Gasto/Ingreso",
                value: totalCurrentIncomePEN > 0 ? String(format: "%.0f", spendingRatio) + "%" : "—",
                icon: "percent",
                color: spendingRatio > 100 ? .red : .blue
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
        let periodLabel = selectedFilter == .semana ? "la semana pasada" : "el mes pasado"
        
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
