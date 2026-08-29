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
    @Environment(\.colorScheme) var colorScheme
    
    @Binding var scrollOffset: CGFloat
    
    @StateObject private var exchangeRateService = ExchangeRateService.shared
    
    @State private var selectedFilter: DashboardFilter = .mes
    
    @State private var showRangePicker = false
    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate: Date = Date()
    
    @State private var searchText: String = ""
    
    @State private var isPressingTotalCombined = false
    @State private var isPressingTotalPEN = false
    @State private var isPressingTotalUSD = false
    
    var filteredExpenses: [Expense] {
        let calendar = Calendar.current
        let now = Date()
        
        return expenses.filter { expense in
            switch selectedFilter {
            case .hoy:
                return calendar.isDateInToday(expense.date)
            case .semana:
                var calendar = Calendar.current
                calendar.firstWeekday = 2 // Lunes
                if let interval = calendar.dateInterval(of: .weekOfYear, for: now) {
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
        return summed.sorted {
            if $0.total == $1.total {
                return $0.merchant < $1.merchant
            }
            return $0.total > $1.total
        }.prefix(5).map { $0 }
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
                                            .foregroundStyle(selectedFilter == filter ? .white : (colorScheme == .dark ? .white : .black))
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 10)
                                            .background(
                                                Capsule()
                                                    .fill(selectedFilter == filter ? Color.purple.opacity(0.8) : Color.primary.opacity(0.05))
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
                                    .foregroundStyle(.primary.opacity(0.7))
                                    .textCase(.uppercase)
                                
                                Text("S/ \(totalCombinedPEN, specifier: "%.2f")")
                                    .font(.system(size: 48, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .lineLimit(isPressingTotalCombined ? nil : 1)
                                    .minimumScaleFactor(0.6)
                                    .truncationMode(.tail)
                                    .onLongPressGesture(minimumDuration: .infinity, perform: {}) { isPressing in
                                        withAnimation(.spring) {
                                            isPressingTotalCombined = isPressing
                                        }
                                    }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                            .padding(.horizontal, 16)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                            
                            // 2. Fila con 2 Divs de Abajo (Soles y Dólares)
                            HStack(spacing: 12) {
                                // Div Soles
                                VStack(spacing: 8) {
                                    Text("En Soles")
                                        .font(.caption)
                                        .foregroundStyle(.primary.opacity(0.7))
                                    Text("S/ \(totalSpentPEN, specifier: "%.2f")")
                                        .font(.title3.bold())
                                        .lineLimit(isPressingTotalPEN ? nil : 1)
                                        .minimumScaleFactor(0.6)
                                        .truncationMode(.tail)
                                        .onLongPressGesture(minimumDuration: .infinity, perform: {}) { isPressing in
                                            withAnimation(.spring) {
                                                isPressingTotalPEN = isPressing
                                            }
                                        }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .padding(.horizontal, 12)
                                .background(Color.primary.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                
                                // Div Dólares
                                VStack(spacing: 8) {
                                    HStack(spacing: 4) {
                                        Text("En Dólares")
                                            .font(.caption)
                                            .foregroundStyle(.primary.opacity(0.7))
                                        Text("T.C. \(exchangeRateService.usdToPenRate, specifier: "%.2f")")
                                            .font(.caption2)
                                            .foregroundStyle(.purple)
                                    }
                                    Text("$ \(totalSpentUSD, specifier: "%.2f")")
                                        .font(.title3.bold())
                                        .lineLimit(isPressingTotalUSD ? nil : 1)
                                        .minimumScaleFactor(0.6)
                                        .truncationMode(.tail)
                                        .onLongPressGesture(minimumDuration: .infinity, perform: {}) { isPressing in
                                            withAnimation(.spring) {
                                                isPressingTotalUSD = isPressing
                                            }
                                        }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .padding(.horizontal, 12)
                                .background(Color.primary.opacity(0.05))
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
                            
                            // Barra de búsqueda por proximidad
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                TextField("Buscar por comercio...", text: $searchText)
                                    .disableAutocorrection(true)
                                
                                if !searchText.isEmpty {
                                    Button {
                                        withAnimation {
                                            searchText = ""
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(10)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                            .padding(.horizontal)
                            
                            let searchedExpenses = searchText.isEmpty ? filteredExpenses : filteredExpenses.filter {
                                $0.merchant.localizedCaseInsensitiveContains(searchText) ||
                                $0.category.localizedCaseInsensitiveContains(searchText)
                            }
                            
                            if searchedExpenses.isEmpty {
                                Text(searchText.isEmpty ? "No hay gastos en este período" : "No se encontraron resultados")
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 10)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            } else {
                                ForEach(searchedExpenses) { expense in
                                    expenseCard(for: expense)
                                }
                            }
                            
                            // Forzar espacio extra si hay pocos elementos (o 0) para que el teclado no los tape
                            if searchedExpenses.count < 6 {
                                Color.clear
                                    .frame(height: CGFloat(6 - searchedExpenses.count) * 85)
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
        VStack(alignment: .leading, spacing: 20) {
            Text("Top Comercios")
                .font(.headline)
            
            let maxTotal = expensesByMerchant.map { $0.total }.max() ?? 1.0
            
            VStack(spacing: 16) {
                ForEach(expensesByMerchant, id: \.merchant) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        let displayName = item.merchant.replacingOccurrences(of: "PLIN - ", with: "").replacingOccurrences(of: "YAPE - ", with: "")
                        
                        Button {
                            withAnimation {
                                searchText = displayName
                            }
                        } label: {
                            Text(displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.accentColor)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        
                        GeometryReader { geo in
                            HStack(spacing: 12) {
                                // Barra horizontal delgada
                                let ratio = maxTotal > 0 ? (item.total / maxTotal) : 0
                                let width = ratio * (geo.size.width - 80) // 80pt reservados para el texto
                                
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.accentColor.opacity(0.8))
                                    .frame(width: max(width, 4), height: 6) // Barra delgada
                                
                                // Valor a la derecha
                                Text(String(format: "S/ %.2f", item.total))
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                    .frame(width: 70, alignment: .leading)
                            }
                        }
                        .frame(height: 12)
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal)
    }
    
    private func expenseCard(for expense: Expense) -> some View {
        HStack(spacing: 16) {
            ZStack {
                let baseColor = iconColor(for: expense)
                
                Circle()
                    .fill(colorScheme == .light ? baseColor : baseColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                
                let icon = iconName(for: expense)
                if icon == "plin_icon" || icon == "yape_icon" {
                    Image(icon)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                } else {
                    Image(systemName: icon)
                        .foregroundStyle(colorScheme == .light ? .white : baseColor)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    let displayName = expense.merchant.replacingOccurrences(of: "PLIN - ", with: "").replacingOccurrences(of: "YAPE - ", with: "")
                    
                    Button {
                        withAnimation {
                            searchText = displayName
                        }
                    } label: {
                        Text(displayName)
                            .font(.headline)
                            .lineLimit(1)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    
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
                        .background(colorScheme == .light ? iconColor(for: expense) : iconColor(for: expense).opacity(0.2))
                        .foregroundStyle(colorScheme == .light ? .white : iconColor(for: expense))
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
        .background(Color.primary.opacity(0.05))
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
        if expense.category == "Sin Clasificar" {
            if expense.merchant.hasPrefix("PLIN - ") { return "plin_icon" }
            if expense.merchant.hasPrefix("YAPE - ") { return "yape_icon" }
        }
        switch expense.category {
        case "Comida": return "fork.knife"
        case "Transporte": return "car.fill"
        case "Entretenimiento": return "play.tv.fill"
        default: return "bag.fill"
        }
    }
    
    private func iconColor(for expense: Expense) -> Color {
        if expense.category == "Sin Clasificar" {
            if expense.merchant.hasPrefix("PLIN - ") { return Color(red: 0, green: 0.7, blue: 0.9) } // Celeste Plin
            if expense.merchant.hasPrefix("YAPE - ") { return Color(red: 0.5, green: 0, blue: 0.5) } // Magenta/Purple
        }
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
