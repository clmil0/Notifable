import AppIntents
import SwiftData
import Foundation

struct LogExpenseIntent: AppIntent {
    // Título y descripción visibles en la app "Atajos"
    static var title: LocalizedStringResource = "Log Apple Pay Expense"
    static var description: IntentDescription = "Logs a new expense captured from a transaction notification."
    
    // Los parámetros que Atajos debe pasarle a este Intent
    @Parameter(title: "Amount")
    var amount: Double
    
    @Parameter(title: "Merchant")
    var merchant: String
    
    // Queremos que se ejecute en segundo plano sin abrir la app
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        do {
            // Inicializamos el contenedor de SwiftData para guardar la información
            // En iOS 17+, si el intent está en el target principal, usará la misma base de datos.
            let container = try ModelContainer(for: Expense.self)
            let context = container.mainContext
            
            // Creamos el nuevo gasto y lo guardamos
            let newExpense = Expense(amount: amount, merchant: merchant)
            context.insert(newExpense)
            
            try context.save()
            
            print("Expense saved successfully: $\(amount) at \(merchant)")
            return .result()
        } catch {
            print("Failed to save expense: \(error)")
            throw error
        }
    }
}

// Este proveedor expone automáticamente el Intent a Siri y a la app Atajos
struct NotifableShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: [
                "Log an expense in \(.applicationName)"
            ],
            shortTitle: "Log Expense",
            systemImageName: "dollarsign.circle"
        )
    }
}
