import SwiftUI
import SwiftData
import Charts

enum DashboardFilter: String, CaseIterable {
    case hoy = "Hoy"
    case semana = "Semana"
    case mes = "Mes"
    case rango = "Rango"
}

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Binding var scrollOffset: CGFloat
    
    @StateObject private var exchangeRateService = ExchangeRateService.shared
    
    @State private var selectedFilter: DashboardFilter = .mes
    
    @State private var showRangePicker = false
    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate: Date = Date()
    
    var filteredExpenses: [Expense] {
        let calendar = Calendar.current
        let now = Date()
        
        return expenses.filter { expense in
            switch selectedFilter {
            case .hoy:
                return calendar.isDateInToday(expense.date)
            case .semana:
                let startOfWeek = calendar.date(byAdding: .day, value: -7, to: now) ?? now
                return expense.date >= startOfWeek && expense.date <= now
            case .mes:
                let startOfMonth = calendar.date(byAdding: .month, value: -1, to: now) ?? now
                return expense.date >= startOfMonth && expense.date <= now
            case .rango:
                let start = calendar.startOfDay(for: startDate)
                let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate
                return expense.date >= start && expense.date <= end
            }
        }
    }
    
    var totalSpentPEN: Double {
        filteredExpenses.filter { $0.currency == "PEN" }.reduce(0) { $0 + $1.amount }
    }
    
    var totalSpentUSD: Double {
        filteredExpenses.filter { $0.currency == "USD" }.reduce(0) { $0 + $1.amount }
    }
    
    var totalCombinedPEN: Double {
        totalSpentPEN + (totalSpentUSD * exchangeRateService.usdToPenRate)
    }
    
    var expensesByMerchant: [(merchant: String, total: Double)] {
        let grouped = Dictionary(grouping: filteredExpenses, by: { $0.merchant })
        let summed = grouped.map { (merchant, expenses) in
            // Convert all to PEN for the chart
            let total = expenses.reduce(0) { sum, exp in
                if exp.currency == "USD" {
                    return sum + (exp.amount * exchangeRateService.usdToPenRate)
                } else {
                    return sum + exp.amount
                }
            }
            return (merchant: merchant, total: total)
        }
        return Array(summed.sorted { $0.total > $1.total }.prefix(5))
    }

    var body: some View {
        ZStack {
            TrackableScrollView(scrollOffset: $scrollOffset) {
                VStack(spacing: 24) {
                    
                    // Contenedor principal para no tapar el top header
                    VStack(spacing: 20) {
                        
                        // Filtros
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(DashboardFilter.allCases, id: \.self) { filter in
                                    Button {
                                        withAnimation(.spring) {
                                            selectedFilter = filter
                                            if filter == .rango {
                                                showRangePicker = true
                                            }
                                        }
                                    } label: {
                                        Text(filter.rawValue)
                                            .font(.subheadline)
                                            .fontWeight(selectedFilter == filter ? .semibold : .regular)
                                            .foregroundStyle(selectedFilter == filter ? .white : .gray)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 10)
                                            .background(
                                                Capsule()
                                                    .fill(selectedFilter == filter ? Color.purple.opacity(0.8) : Color.white.opacity(0.05))
                                            )
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        
                        // Tarjeta Principal (3 Divs)
                        VStack(spacing: 12) {
                            // 1. Div de Arriba (Total)
                            VStack(spacing: 8) {
                                Text("Total Gastado (Pasado a Soles)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                
                                Text("S/ \(totalCombinedPEN, specifier: "%.2f")")
                                    .font(.system(size: 48, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                            
                            // 2. Fila con 2 Divs de Abajo (Soles y Dólares)
                            HStack(spacing: 12) {
                                // Div Soles
                                VStack(spacing: 8) {
                                    Text("En Soles")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("S/ \(totalSpentPEN, specifier: "%.2f")")
                                        .font(.title3.bold())
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .background(Color.white.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                
                                // Div Dólares
                                VStack(spacing: 8) {
                                    HStack(spacing: 4) {
                                        Text("En Dólares")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("T.C. \(exchangeRateService.usdToPenRate, specifier: "%.2f")")
                                            .font(.caption2)
                                            .foregroundStyle(.purple)
                                    }
                                    Text("$ \(totalSpentUSD, specifier: "%.2f")")
                                        .font(.title3.bold())
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .background(Color.white.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            }
                        }
                        .padding(.horizontal)
                        
                        if !expensesByMerchant.isEmpty {
                            chartCard
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Actividad Reciente")
                                .font(.title3)
                                .fontWeight(.bold)
                                .padding(.horizontal)
                            
                            if filteredExpenses.isEmpty {
                                Text("No hay gastos en este período")
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 10)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            } else {
                                ForEach(filteredExpenses) { expense in
                                    expenseCard(for: expense)
                                }
                            }
                        }
                        .padding(.top, 10)
                    }
                    .padding(.bottom, 100) // Padding extra para la Floating Bar solamente
                }
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
                        Button("Aplicar") {
                            showRangePicker = false
                        }
                    }
                }
                .preferredColorScheme(.dark)
            }
            .presentationDetents([.fraction(0.4)])
            .presentationDragIndicator(.visible)
        }
    }
    
    // MARK: - Subviews
    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Top Comercios")
                .font(.headline)
            
            Chart {
                ForEach(expensesByMerchant, id: \.merchant) { item in
                    BarMark(
                        x: .value("Comercio", item.merchant),
                        y: .value("Total", item.total)
                    )
                    // Diferentes colores basados en el nombre
                    .foregroundStyle(by: .value("Comercio", item.merchant))
                    .cornerRadius(12) // Mayor redondeo, estilo cápsula
                }
            }
            .frame(height: 200)
            .chartYAxis(.hidden)
            .chartXAxis {
                // Personalizamos el label del eje X para que trunque los textos largos
                AxisMarks(position: .bottom) { value in
                    if let merchantName = value.as(String.self) {
                        AxisValueLabel {
                            Text(merchantName)
                                .font(.caption2)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 60)
                        }
                    } else {
                        AxisValueLabel()
                    }
                }
            }
            .chartLegend(.hidden) // Ocultar leyenda extra, ya está en el eje X
            // Paleta de colores fluida y moderna
            .chartForegroundStyleScale(range: [
                Color.purple, Color.blue, Color.pink, 
                Color.indigo, Color.cyan, Color.orange
            ])
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal)
    }
    
    private func expenseCard(for expense: Expense) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(iconColor(for: expense).opacity(0.15))
                    .frame(width: 48, height: 48)
                
                let icon = iconName(for: expense)
                if icon == "plin_icon" {
                    Image(icon)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                } else {
                    Image(systemName: icon)
                        .foregroundStyle(iconColor(for: expense))
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(expense.merchant.replacingOccurrences(of: "PLIN - ", with: ""))
                        .font(.headline)
                        .lineLimit(1)
                    
                    if expense.isSubscription {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                    }
                }
                
                HStack(spacing: 6) {
                    Text(expense.category)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(iconColor(for: expense).opacity(0.2))
                        .foregroundStyle(iconColor(for: expense))
                        .clipShape(Capsule())
                    
                    Text(expense.date.formatted(.dateTime.day().month().hour().minute()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
            
            Spacer()
            
            let currencySymbol = expense.currency == "USD" ? "$" : "S/"
            Text("\(currencySymbol) \(expense.amount, specifier: "%.2f")")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
        .contextMenu {
            Button(role: .destructive) {
                withAnimation {
                    modelContext.delete(expense)
                }
            } label: {
                Label("Eliminar", systemImage: "trash")
            }
        }
    }
    
    // MARK: - Helpers
    private func iconName(for expense: Expense) -> String {
        if expense.category == "Sin Clasificar" && expense.merchant.hasPrefix("PLIN - ") { return "plin_icon" }
        switch expense.category {
        case "Comida": return "fork.knife"
        case "Transporte": return "car.fill"
        case "Entretenimiento": return "play.tv.fill"
        default: return "bag.fill"
        }
    }
    
    private func iconColor(for expense: Expense) -> Color {
        if expense.category == "Sin Clasificar" && expense.merchant.hasPrefix("PLIN - ") { return .purple }
        switch expense.category {
        case "Comida": return .orange
        case "Transporte": return .blue
        case "Entretenimiento": return .purple
        default: return .green
        }
    }
    
}

#Preview {
    DashboardView(scrollOffset: .constant(100))
        .modelContainer(for: Expense.self, inMemory: true)
}
