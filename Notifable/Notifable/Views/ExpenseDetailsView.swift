import SwiftUI
import SwiftData

struct ExpenseDetailsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage("isDarkMode") private var isDarkMode = true
    
    @Bindable var expense: Expense
    
    // Para obtener todas las categorías existentes
    @Query private var allExpenses: [Expense]
    
    @State private var showingCategoryPicker = false
    @State private var showingCancelDebtConfirmation = false
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.purple.rawValue
    
    var themeColor: Color { AppThemeColor(rawValue: appAccentColor)?.color ?? .purple }
    
    var allCategories: [String] {
        let defaults = ["Comida", "Transporte", "Entretenimiento", "Supermercado", "Otros"]
        let existing = Set(allExpenses.map { $0.category }.filter { $0 != "Sin Clasificar" })
        return Array(existing.union(defaults)).sorted()
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header con Monto
                    VStack(spacing: 8) {
                        let currencySymbol = expense.currency == "USD" ? "$" : "S/"
                        Text("\(currencySymbol) \(expense.amount, specifier: "%.2f")")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        
                        Text(expense.merchant)
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 32)
                    
                    // Tarjeta de Detalles
                    VStack(spacing: 0) {
                        detailRow(title: "Fecha", value: expense.date.formatted(date: .abbreviated, time: .shortened))
                        
                        Divider().padding(.leading, 16)
                        
                        detailRow(title: "Moneda", value: expense.currency == "PEN" ? "Soles (PEN)" : "Dólares (USD)")
                        
                        Divider().padding(.leading, 16)
                        
                        if let card = expense.cardLastDigits {
                            detailRow(title: "Tarjeta", value: "*\(card)")
                            
                            Divider().padding(.leading, 16)
                        }
                        
                        Button {
                            showingCategoryPicker = true
                        } label: {
                            HStack {
                                Text("Categoría")
                                    .foregroundStyle(.primary)
                                Spacer()
                                HStack(spacing: 6) {
                                    Text(expense.category)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(themeColor)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding()
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal)
                    
                    if expense.isDebt || !(expense.payments ?? []).isEmpty {
                        paymentsSection
                    }
                    
                    Button {
                        withAnimation {
                            expense.isDebt.toggle()
                            try? modelContext.save()
                        }
                    } label: {
                        Text(expense.isDebt ? "Marcar como Deuda Saldada" : "Marcar como Deuda Activa")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(expense.isDebt ? Color.green : Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    Spacer()
                }
            }
            .navigationTitle("Detalles de Transacción")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingCategoryPicker) {
                AssignCategoryView(merchant: expense.merchant, existingCategories: allCategories) { newCategory in
                    expense.category = newCategory
                    try? modelContext.save()
                }
                .presentationDetents([.fraction(0.8)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
            }
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }
    
    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
    
    @ViewBuilder
    private var paymentsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Estado de la Deuda")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            let paid = (expense.payments ?? []).reduce(0) { $0 + $1.amount }
            let total = expense.amount
            let ratio = total > 0 ? min(paid / total, 1.0) : 0
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("S/ \(paid, specifier: "%.2f") pagado")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                    Spacer()
                    Text("S/ \(total, specifier: "%.2f") total")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.1))
                            .frame(height: 8)
                        
                        Capsule()
                            .fill(Color.green)
                            .frame(width: geo.size.width * CGFloat(ratio), height: 8)
                    }
                }
                .frame(height: 8)
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal)
            
            if let payments = expense.payments, !payments.isEmpty {
                VStack(spacing: 0) {
                    ForEach(payments.sorted(by: { $0.date > $1.date })) { payment in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(payment.source)
                                    .fontWeight(.medium)
                                Text(payment.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("+S/ \(payment.amount, specifier: "%.2f")")
                                .fontWeight(.bold)
                                .foregroundStyle(.green)
                        }
                        .padding()
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button(role: .destructive) {
                                withAnimation {
                                    payment.debtReference = nil
                                    payment.isFinalDebtPayment = false
                                    try? modelContext.save()
                                }
                            } label: {
                                Label("Desvincular de la deuda", systemImage: "link.badge.minus")
                            }
                        }
                        
                        if payment.id != payments.sorted(by: { $0.date > $1.date }).last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)
            } else {
                Text("Aún no hay pagos registrados.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
    }
}
