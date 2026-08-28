import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    // Consultamos todos los gastos, ordenados del más reciente al más antiguo
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    
    // Calculamos el total gastado
    var totalSpent: Double {
        expenses.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header (Total Spend)
                VStack(spacing: 8) {
                    Text("Total Gastado")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    Text("$\(totalSpent, specifier: "%.2f")")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                .padding(.vertical, 30)
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .padding()
                
                // Lista de Gastos
                List {
                    ForEach(expenses) { expense in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(expense.merchant)
                                    .font(.headline)
                                Text(expense.date, format: .dateTime.month().day().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Text("$\(expense.amount, specifier: "%.2f")")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(.red) // Asumiendo que todo es un gasto
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: deleteExpenses)
                }
                .listStyle(.plain)
            }
            .navigationTitle("Notifable")
            // Botón de prueba para agregar datos sin usar Atajos
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: addMockExpense) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
        }
    }
    
    // Función auxiliar para probar la interfaz
    private func addMockExpense() {
        let mock = Expense(amount: Double.random(in: 10.0...150.0), merchant: "Comercio de Prueba")
        modelContext.insert(mock)
    }

    // Función para borrar deslizando
    private func deleteExpenses(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(expenses[index])
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Expense.self, inMemory: true)
}
