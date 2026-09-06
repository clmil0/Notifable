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
        // Rebrand: el tema pasa a "Azul" (el azul del ícono), una sola vez.
        AppThemeColor.migrateToBrandBlueIfNeeded()
        // Quien ya venía usando la app no tiene por qué ver el onboarding: si
        // hay correo conectado o correos ya procesados, se da por visto.
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "hasSeenOnboarding") == nil {
            let yaUsaba = defaults.string(forKey: "GmailAccessToken") != nil
                || defaults.string(forKey: "GmailRefreshToken") != nil
                || !(defaults.stringArray(forKey: "processedEmailIDs") ?? []).isEmpty
            defaults.set(yaUsaba, forKey: "hasSeenOnboarding")
        }
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var backupManager = ConfigBackupManager.shared
    /// Primera apertura: el carrusel y la pantalla de login. Lo pone en `true`
    /// la propia `OnboardingView` al terminar.
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(AppThemeColor(rawValue: appAccentColor)?.color ?? .purple)
                .appTextSize()
                .appAppearance()
                .task {
                    // A partir de aquí la sincronización se dispara sola con
                    // cada guardado; ninguna vista tiene que avisarle de nada.
                    backupManager.configure(container: sharedModelContainer)
                }
                // Presentación en cadena: primero el onboarding y sólo después,
                // si esa cuenta ya tenía respaldo, la oferta de restaurarlo. Dos
                // `fullScreenCover` a la vez no se pueden mostrar, y el orden
                // importa: la oferta no significa nada antes de conectar Gmail.
                .fullScreenCover(isPresented: .init(get: { !hasSeenOnboarding },
                                                    set: { hasSeenOnboarding = !$0 })) {
                    OnboardingView()
                }
                // Celular nuevo: la cuenta que acaba de conectar ya tenía un
                // respaldo. Se pregunta una sola vez.
                .fullScreenCover(item: $backupManager.foundBackup) { header in
                    BackupFoundView(header: header) {
                        Task { await backupManager.acceptFoundBackup() }
                    } onSkip: {
                        backupManager.dismissBackupOffer()
                    }
                }
        }
        .modelContainer(sharedModelContainer) // Inyecta la BD a todas las vistas
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                if GmailAuthService.shared.isAuthenticated {
                    GmailSyncService.shared.modelContext = sharedModelContainer.mainContext
                    GmailSyncService.shared.syncEmails()
                }
                Task { await ConfigBackupManager.shared.checkForExistingBackup() }
            }
        }
    }

}
