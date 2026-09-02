import SwiftUI
import SwiftData

@main
struct NotifableApp: App {
    // Configura el contenedor principal de la base de datos de SwiftData
    var sharedModelContainer: ModelContainer = {
        // Migración aditiva: SwiftData crea las tablas nuevas sin tocar las
        // existentes.
        let schema = Schema([
            Expense.self,
            Income.self,
            RecurringExpense.self,
            QuickExpense.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("No se pudo crear el ModelContainer: \(error)")
        }
    }()

    init() {
        // Traduce el `dashboardFilter` guardado por la versión anterior al
        // nuevo `Period` único y borra las claves que ya no existen.
        Period.migrateLegacyFilterIfNeeded()
        // Conserva la elección previa de isDarkMode: quien tenía modo oscuro
        // sigue en oscuro, no pasa a "Automático".
        AppAppearance.migrateIfNeeded()
        // La hora del recordatorio de deuda se guardaba como fecha completa y
        // quedaba anclada al día en que se configuró.
        NotificationSettings.migrateIfNeeded()
    }

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.purple.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(AppThemeColor(rawValue: appAccentColor)?.color ?? .purple)
                .appTextSize()
                .appAppearance()
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
