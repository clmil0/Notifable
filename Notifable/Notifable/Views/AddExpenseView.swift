import SwiftUI
import SwiftData

enum TransactionType: String, CaseIterable, Identifiable {
    case gasto = "Gasto"
    case ingreso = "Ingreso"
    
    var id: String { self.rawValue }
}

struct AddExpenseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isDarkMode") private var isDarkMode = true
    
    let transactionType: TransactionType
    
    // Gasto states
    @State private var amountText: String = ""
    @State private var merchant: String = ""
    @State private var category: String = "Otros"
    @State private var isSubscription: Bool = false
    @State private var currency: String = "PEN"
    
    // Ingreso states
    @State private var incomeSource: String = "Plin"
    @State private var incomeTitle: String = ""
    @State private var incomeNotes: String = ""
    @State private var incomeDate: Date = Date()

    
    let categories = ["Comida", "Transporte", "Entretenimiento", "Otros", "Sin Clasificar"]
    let currencies = ["PEN", "USD"]
    let incomeSources = ["Plin", "Yape", "Efectivo", "Transferencia", "Otro"]
    
    var body: some View {
        NavigationStack {
            Form {
                if transactionType == .gasto {
                    Section(header: Text("Detalles del Gasto")) {
                        HStack {
                            Picker("", selection: $currency) {
                                ForEach(currencies, id: \.self) { curr in
                                    Text(curr).tag(curr)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 80)
                            
                            TextField("Monto (ej. 45.50)", text: $amountText)
                                .keyboardType(.decimalPad)
                        }
                        
                        TextField("Comercio / Producto", text: $merchant)
                        
                        Picker("Categoría", selection: $category) {
                            ForEach(categories, id: \.self) { cat in
                                Text(cat).tag(cat)
                            }
                        }
                        
                        Toggle("Es Suscripción", isOn: $isSubscription)
                            .tint(.purple)
                    }
                } else {
                    Section(header: Text("Detalles del Ingreso")) {
                        HStack {
                            Picker("", selection: $currency) {
                                ForEach(currencies, id: \.self) { curr in
                                    Text(curr).tag(curr)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 80)
                            
                            TextField("Monto (ej. 100.00)", text: $amountText)
                                .keyboardType(.decimalPad)
                        }
                        
                        Picker("Tipo de Ingreso", selection: $incomeSource) {
                            ForEach(incomeSources, id: \.self) { source in
                                Text(source).tag(source)
                            }
                        }
                        
                        TextField("Título (Opcional)", text: $incomeTitle)
                        
                        TextField("Descripción (Opcional)", text: $incomeNotes)
                        
                        DatePicker("Fecha y Hora", selection: $incomeDate)
                    }
                }
                
                Section {
                    Button(action: {
                        if transactionType == .gasto {
                            addManualExpense()
                        } else {
                            addManualIncome()
                        }
                    }) {
                        Text("Añadir")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(.white)
                            .padding(.vertical, 4)
                    }
                    .listRowBackground(transactionType == .gasto ? Color.purple : Color.green)
                    
                    if transactionType == .gasto {
                        Button(action: addRandomExpense) {
                            Text("Añadir Rand (Prueba)")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(.white)
                                .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.blue.opacity(0.8))
                    }
                }
            }
            .navigationTitle(transactionType == .gasto ? "Nuevo Gasto" : "Nuevo Ingreso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
            }
            .preferredColorScheme(isDarkMode ? .dark : .light)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
    }
    
    private func addManualExpense() {
        let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0.0
        guard amount > 0, !merchant.isEmpty else { return }
        
        let roundedAmount = (amount * 100).rounded() / 100
        
        let expense = Expense(
            amount: roundedAmount,
            merchant: merchant,
            category: category,
            isSubscription: isSubscription,
            currency: currency
        )
        
        withAnimation {
            modelContext.insert(expense)
        }
        dismiss()
    }
    
    private func addRandomExpense() {
        let options = [
            ("Apple Store", "Entretenimiento"),
            ("Starbucks", "Comida"),
            ("Uber", "Transporte"),
            ("Amazon", "Otros"),
            ("Netflix", "Entretenimiento"),
            ("Oxxo 123", "Sin Clasificar"),
            ("Gasolinera XYZ", "Sin Clasificar")
        ]
        let selected = options.randomElement()!
        
        let randomValue = Double.random(in: 10.0...150.0)
        let roundedAmount = (randomValue * 100).rounded() / 100
        
        let mock = Expense(
            amount: roundedAmount,
            merchant: selected.0,
            category: selected.1,
            isSubscription: selected.0 == "Netflix"
        )
        
        withAnimation {
            modelContext.insert(mock)
        }
        dismiss()
    }
    
    private func addManualIncome() {
        let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0.0
        guard amount > 0 else { return }
        
        let roundedAmount = (amount * 100).rounded() / 100
        
        let income = Income(
            amount: roundedAmount,
            currency: currency,
            source: incomeSource,
            title: incomeTitle.isEmpty ? nil : incomeTitle,
            date: incomeDate,
            notes: incomeNotes.isEmpty ? nil : incomeNotes
        )
        
        withAnimation {
            modelContext.insert(income)
        }
        dismiss()
    }
}

#Preview {
    AddExpenseView(transactionType: .gasto)
}
