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
                                        .foregroundStyle(.purple)
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
}
