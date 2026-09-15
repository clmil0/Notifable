import SwiftData

/// El único `ModelContainer` del proceso.
///
/// Lo comparten la app y los intents de Siri. Antes `LogExpenseIntent` abría
/// el suyo con `ModelContainer(for: Expense.self)`: un esquema con un solo
/// modelo sobre el mismo archivo que la app abre con seis. Los cambios de un
/// contenedor no llegaban a las vistas del otro, y abrir el archivo con un
/// esquema parcial se arriesga a un error de migración.
///
/// El archivo sigue en el contenedor privado de la app — **no** en el App
/// Group. Los widgets sólo ven `WidgetSnapshot`.
enum AppModelContainer {

    static let schema = Schema([
        Expense.self,
        Income.self,
        RecurringExpense.self,
        QuickExpense.self,
        CachedFriend.self,
        CachedFriendShare.self
    ])

    static let shared: ModelContainer = {
        // Migración aditiva: SwiftData crea las tablas nuevas sin tocar las
        // existentes.
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("No se pudo crear el ModelContainer: \(error)")
        }
    }()
}
