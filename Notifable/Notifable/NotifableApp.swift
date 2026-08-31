import SwiftUI
import SwiftData

@main
struct NotifableApp: App {
    // Configura el contenedor principal de la base de datos de SwiftData
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Expense.self,
            Income.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("No se pudo crear el ModelContainer: \(error)")
        }
    }()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer) // Inyecta la BD a todas las vistas
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                if GmailAuthService.shared.isAuthenticated {
                    GmailSyncService.shared.modelContext = sharedModelContainer.mainContext
                    GmailSyncService.shared.syncEmails()
                }
            }
        }
    }
}
