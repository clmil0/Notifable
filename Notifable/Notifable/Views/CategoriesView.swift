import SwiftUI
import SwiftData
import Charts

enum CategoryTab: String, CaseIterable {
    case misCategorias = "Mis Categorías"
    case inbox = "Bandeja (Sin Clasificar)"
}

struct MerchantWrapper: Identifiable {
    let id: String
}

struct CategoriesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var expenses: [Expense]
    @Binding var scrollOffset: CGFloat
    
    @StateObject private var exchangeRateService = ExchangeRateService.shared
    
    @State private var selectedFilter: DashboardFilter = .mes
    @State private var showRangePicker = false
    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate: Date = Date()
    
    @State private var selectedTab: CategoryTab = .misCategorias
    @State private var selectedMerchantToCategorize: MerchantWrapper?
    @State private var expandedMerchants: Set<String> = []
    @State private var expandedCategories: Set<String> = []
    @Namespace private var animation
    
    // Filtrar los gastos según el filtro de tiempo
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
    
    // Categorías válidas (para no mostrar "Sin Clasificar" en los gráficos normales)
    var validExpenses: [Expense] {
        filteredExpenses.filter { $0.category != "Sin Clasificar" }
    }
    
    var allCategories: [String] {
        let defaults = ["Comida", "Transporte", "Entretenimiento", "Supermercado", "Otros"]
        let existing = Set(expenses.map { $0.category }.filter { $0 != "Sin Clasificar" })
        return Array(existing.union(defaults)).sorted()
    }
    
    // Gastos no clasificados agrupados por comercio
    var inboxGroups: [(merchant: String, expenses: [Expense], combinedTotal: Double)] {
        let uncategorized = filteredExpenses.filter { $0.category == "Sin Clasificar" }
        let grouped = Dictionary(grouping: uncategorized, by: { $0.merchant })
        return grouped.map { (merchant, expenses) in
            let pen = expenses.filter { $0.currency == "PEN" }.reduce(0) { $0 + $1.amount }
            let usd = expenses.filter { $0.currency == "USD" }.reduce(0) { $0 + $1.amount }
            let combined = pen + (usd * exchangeRateService.usdToPenRate)
            return (merchant: merchant, expenses: expenses.sorted { $0.date > $1.date }, combinedTotal: combined)
        }.sorted { 
            if $0.expenses.count == $1.expenses.count {
                return $0.merchant < $1.merchant
            }
            return $0.expenses.count > $1.expenses.count 
        }
    }
    
    var categoryTotals: [(category: String, totalPEN: Double, totalUSD: Double, combinedTotal: Double, merchants: [(merchant: String, combinedTotal: Double)])] {
        let grouped = Dictionary(grouping: validExpenses, by: { $0.category })
        let summed = grouped.map { (category, expenses) -> (category: String, totalPEN: Double, totalUSD: Double, combinedTotal: Double, merchants: [(merchant: String, combinedTotal: Double)]) in
            let pen = expenses.filter { $0.currency == "PEN" }.reduce(0) { $0 + $1.amount }
            let usd = expenses.filter { $0.currency == "USD" }.reduce(0) { $0 + $1.amount }
            let combined = pen + (usd * exchangeRateService.usdToPenRate)
            
            let merchantGroup = Dictionary(grouping: expenses, by: { $0.merchant })
            let merchants = merchantGroup.map { (merchant, mExpenses) -> (merchant: String, combinedTotal: Double) in
                let mPen = mExpenses.filter { $0.currency == "PEN" }.reduce(0) { $0 + $1.amount }
                let mUsd = mExpenses.filter { $0.currency == "USD" }.reduce(0) { $0 + $1.amount }
                let mCombined = mPen + (mUsd * exchangeRateService.usdToPenRate)
                return (merchant: merchant, combinedTotal: mCombined)
            }.sorted {
                if $0.combinedTotal == $1.combinedTotal {
                    return $0.merchant < $1.merchant
                }
                return $0.combinedTotal > $1.combinedTotal 
            }
            
            return (category: category, totalPEN: pen, totalUSD: usd, combinedTotal: combined, merchants: merchants)
        }
        return summed.sorted { 
            if $0.combinedTotal == $1.combinedTotal {
                return $0.category < $1.category
            }
            return $0.combinedTotal > $1.combinedTotal 
        }
    }
    
    var body: some View {
        ZStack {
            TrackableScrollView(scrollOffset: $scrollOffset) {
                VStack(spacing: 24) {
                    // 1. Filtros de Tiempo
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
                    
                    // 2. Gráfico de Dona (sólo si estamos en Mis Categorías y hay datos)
                    if selectedTab == .misCategorias && !categoryTotals.isEmpty {
                        donutChartView
                    }
                    
                    // 3. Segmented Picker (Mis Categorías vs Bandeja)
                    HStack(spacing: 0) {
                        ForEach([CategoryTab.misCategorias, CategoryTab.inbox], id: \.self) { tab in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedTab = tab
                                }
                            } label: {
                                Text(tab.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(selectedTab == tab ? .semibold : .regular)
                                    .foregroundStyle(selectedTab == tab ? .white : .gray)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        ZStack {
                                            if selectedTab == tab {
                                                Capsule()
                                                    .fill(Color.purple.opacity(0.8))
                                                    .shadow(color: .purple.opacity(0.3), radius: 8, x: 0, y: 4)
                                                    .matchedGeometryEffect(id: "TAB", in: animation)
                                            }
                                        }
                                    )
                            }
                        }
                    }
                    .background(Color.white.opacity(0.05))
                    .clipShape(Capsule())
                    .padding(.horizontal)
                    .padding(.bottom, -12) // Reduce the 24 spacing to 12
                    
                    // 4. Lista de Categorías o Bandeja
                    if selectedTab == .misCategorias {
                        misCategoriasListView
                    } else {
                        inboxView
                    }
                }
                .padding(.bottom, 100)
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
        .sheet(item: $selectedMerchantToCategorize) { wrapper in
            AssignCategoryView(merchant: wrapper.id, existingCategories: allCategories) { newCategory in
                let uncategorized = expenses.filter { $0.merchant == wrapper.id && $0.category == "Sin Clasificar" }
                for expense in uncategorized {
                    expense.category = newCategory
                }
                try? modelContext.save()
            }
            .presentationDetents([.fraction(0.8)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
        }
    }
    
    // MARK: - Mis Categorías
    private var donutChartView: some View {
        Chart(categoryTotals, id: \.category) { item in
            SectorMark(
                angle: .value("Total", item.combinedTotal),
                innerRadius: .ratio(0.6),
                angularInset: 2.0
            )
            .cornerRadius(4)
            .foregroundStyle(by: .value("Category", item.category))
            .annotation(position: .overlay) {
                Text("S/\(item.combinedTotal, specifier: "%.0f")")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }
        }
        .chartLegend(position: .bottom, alignment: .center, spacing: 32)
        .frame(height: 250)
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal)
    }
    
    private var misCategoriasListView: some View {
        Group {
            if categoryTotals.isEmpty {
                ContentUnavailableView("No hay gastos", systemImage: "tray.fill", description: Text("Los gastos clasificados aparecerán aquí."))
            } else {
                VStack(spacing: 12) {
                    ForEach(categoryTotals, id: \.category) { item in
                        VStack(spacing: 0) {
                            HStack {
                                ZStack {
                                    Circle()
                                        .fill(iconColor(for: item.category).opacity(0.2))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: iconName(for: item.category))
                                        .foregroundStyle(iconColor(for: item.category))
                                }
                                
                                Text(item.category)
                                    .font(.headline)
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 2) {
                                    if item.totalPEN > 0 {
                                        Text("S/ \(item.totalPEN, specifier: "%.2f")")
                                            .font(.subheadline)
                                            .foregroundStyle(item.totalUSD > 0 ? .secondary : .primary)
                                    }
                                    if item.totalUSD > 0 {
                                        Text("$ \(item.totalUSD, specifier: "%.2f")")
                                            .font(.subheadline)
                                            .foregroundStyle(item.totalPEN > 0 ? .secondary : .primary)
                                    }
                                    if item.totalPEN > 0 && item.totalUSD > 0 {
                                        Text("Total S/ \(item.combinedTotal, specifier: "%.2f")")
                                            .font(.caption)
                                            .bold()
                                            .foregroundStyle(.primary)
                                            .padding(.top, 2)
                                    }
                                }
                                
                                Image(systemName: "chevron.down")
                                    .rotationEffect(.degrees(expandedCategories.contains(item.category) ? 180 : 0))
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 8)
                            }
                            .padding()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring) {
                                    if expandedCategories.contains(item.category) {
                                        expandedCategories.remove(item.category)
                                    } else {
                                        expandedCategories.insert(item.category)
                                    }
                                }
                            }
                            .onLongPressGesture(minimumDuration: 0.5) {
                                withAnimation(.spring) {
                                    if expandedCategories.contains(item.category) {
                                        expandedCategories.remove(item.category)
                                    } else {
                                        expandedCategories.insert(item.category)
                                    }
                                }
                            }
                            
                            if expandedCategories.contains(item.category) {
                                VStack(spacing: 8) {
                                    Divider().background(Color.white.opacity(0.1))
                                    
                                    ForEach(item.merchants, id: \.merchant) { merchantItem in
                                        HStack {
                                            Text(merchantItem.merchant)
                                                .font(.caption)
                                                .foregroundStyle(.primary)
                                            
                                            Spacer()
                                            
                                            Text("S/ \(merchantItem.combinedTotal, specifier: "%.2f")")
                                                .font(.caption).bold()
                                                .padding(.trailing, 8)
                                            
                                            Button(action: {
                                                uncategorize(merchant: merchantItem.merchant, from: item.category)
                                            }) {
                                                Image(systemName: "xmark")
                                                    .font(.caption2)
                                                    .bold()
                                                    .foregroundStyle(.white)
                                                    .padding(6)
                                                    .background(Color.red)
                                                    .clipShape(Circle())
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.bottom)
                            }
                        }
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal)
                    }
                }
            }
        }
    }
    
    // MARK: - Bandeja (Inbox)
    private var inboxView: some View {
        Group {
            if inboxGroups.isEmpty {
                ContentUnavailableView("Bandeja Vacía", systemImage: "checkmark.circle.fill", description: Text("Todos tus gastos están clasificados."))
            } else {
                VStack(spacing: 12) {
                    ForEach(inboxGroups, id: \.merchant) { group in
                        VStack(spacing: 0) {
                            HStack {
                                ZStack {
                                    Circle()
                                        .fill(group.merchant.hasPrefix("PLIN - ") ? Color.white : Color.gray.opacity(0.15))
                                        .frame(width: 40, height: 40)
                                        .shadow(color: group.merchant.hasPrefix("PLIN - ") ? Color.black.opacity(0.05) : .clear, radius: 2)
                                    
                                    if group.merchant.hasPrefix("PLIN - ") {
                                        Image("plin_icon")
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 26, height: 26)
                                            .clipShape(Circle())
                                    } else {
                                        Image(systemName: "tray.fill")
                                            .foregroundStyle(.gray)
                                    }
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(group.merchant.replacingOccurrences(of: "PLIN - ", with: ""))
                                        .font(.headline)
                                    Text("\(group.expenses.count) transacciones")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Text("S/ \(group.combinedTotal, specifier: "%.2f")")
                                    .font(.subheadline).bold()
                                    .padding(.trailing, 8)
                                
                                Button {
                                    selectedMerchantToCategorize = MerchantWrapper(id: group.merchant)
                                } label: {
                                    Text("Asignar")
                                        .font(.caption).bold()
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.blue)
                                        .foregroundStyle(.white)
                                        .clipShape(Capsule())
                                }
                                
                                Image(systemName: "chevron.down")
                                    .rotationEffect(.degrees(expandedMerchants.contains(group.merchant) ? 180 : 0))
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 8)
                            }
                            .padding()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring) {
                                    if expandedMerchants.contains(group.merchant) {
                                        expandedMerchants.remove(group.merchant)
                                    } else {
                                        expandedMerchants.insert(group.merchant)
                                    }
                                }
                            }
                            
                            if expandedMerchants.contains(group.merchant) {
                                VStack(spacing: 8) {
                                    Divider().background(Color.white.opacity(0.1))
                                    
                                    ForEach(group.expenses) { expense in
                                        HStack {
                                            Text(expense.date, style: .date)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            if expense.currency == "PEN" {
                                                Text("S/ \(expense.amount, specifier: "%.2f")")
                                                    .font(.caption).bold()
                                            } else {
                                                Text("$ \(expense.amount, specifier: "%.2f")")
                                                    .font(.caption).bold()
                                                    .foregroundStyle(.green)
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.bottom)
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal)
                    }
                }
                .padding(.top)
            }
        }
    }
    
    // MARK: - Helpers
    private func iconName(for category: String) -> String {
        switch category {
        case "Comida": return "fork.knife"
        case "Transporte": return "car.fill"
        case "Entretenimiento": return "play.tv.fill"
        default: return "bag.fill"
        }
    }
    private func iconColor(for category: String) -> Color {
        switch category {
        case "Comida": return .orange
        case "Transporte": return .blue
        case "Entretenimiento": return .purple
        default: return .green
        }
    }
    
    private func uncategorize(merchant: String, from category: String) {
        let expensesToUpdate = expenses.filter { $0.category == category && $0.merchant == merchant }
        for expense in expensesToUpdate {
            expense.category = "Sin Clasificar"
        }
        try? modelContext.save()
    }
}

// Subvista para asignar la categoría
struct AssignCategoryView: View {
    let merchant: String
    let existingCategories: [String]
    var onAssign: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var isCreatingNew = false
    @State private var newCategoryName = ""
    
    var filteredCategories: [String] {
        if searchText.isEmpty {
            return existingCategories
        } else {
            return existingCategories.filter { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    @ViewBuilder
    private var contentList: some View {
        List {
            if isCreatingNew {
                Section(header: Text("Nueva Categoría")) {
                    TextField("Nombre de la categoría", text: $newCategoryName)
                    Button("Crear y Asignar") {
                        let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            onAssign(trimmed)
                            dismiss()
                        }
                    }
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .foregroundStyle(.blue)
                }
            } else {
                Section(header: Text("Crear")) {
                    Button {
                        withAnimation {
                            isCreatingNew = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Crear nueva categoría")
                        }
                    }
                }
                
                Section(header: Text("Asignar a \(merchant)")) {
                    ForEach(filteredCategories, id: \.self) { cat in
                        Button(cat) {
                            onAssign(cat)
                            dismiss()
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if existingCategories.count > 10 {
                    contentList
                        .searchable(text: $searchText, prompt: "Buscar categoría")
                } else {
                    contentList
                }
            }
            .navigationTitle(isCreatingNew ? "Nueva Categoría" : "Seleccionar Categoría")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        if isCreatingNew {
                            withAnimation {
                                isCreatingNew = false
                                newCategoryName = ""
                            }
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

#Preview {
    CategoriesView(scrollOffset: .constant(100))
        .modelContainer(for: Expense.self, inMemory: true)
}
