import AppIntents

/// Las frases que Siri reconoce sin configurar nada.
///
/// Reglas de Apple que explican su forma: cada frase lleva el nombre de la app
/// y sólo admite parámetros de lista cerrada (`AppEnum` o `AppEntity`). Por eso
/// "Yape" o "Comida" pueden ir dentro de la frase y el monto no: Siri lo
/// pregunta después. Las traducciones al español viven en `AppShortcuts.xcstrings`.
///
/// `LogExpenseIntent` (la automatización de Wallet) no tiene frase: sigue
/// disponible como acción en Atajos, pero por voz se usa `AddExpenseIntent`.
struct NotifableShortcutsProvider: AppShortcutsProvider {

    static var shortcutTileColor: ShortcutTileColor = .blue

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddIncomeIntent(),
            phrases: [
                "Registra un ingreso de \(\.$source) en \(.applicationName)",
                "Añade un ingreso de \(\.$source) en \(.applicationName)",
                "Anota un ingreso de \(\.$source) en \(.applicationName)",
                "Registra un ingreso en \(.applicationName)",
                "Añade un ingreso en \(.applicationName)"
            ],
            shortTitle: "Registrar ingreso",
            systemImageName: "arrow.down.left.circle.fill"
        )
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Registra un gasto de \(\.$category) en \(.applicationName)",
                "Anota un gasto de \(\.$category) en \(.applicationName)",
                "Registra un gasto en \(.applicationName)",
                "Añade un gasto en \(.applicationName)"
            ],
            shortTitle: "Registrar gasto",
            systemImageName: "arrow.up.right.circle.fill"
        )
        AppShortcut(
            intent: LogQuickExpenseIntent(),
            phrases: [
                "Registra \(\.$quick) en \(.applicationName)",
                "Anota \(\.$quick) en \(.applicationName)",
                "Registra un gasto rápido en \(.applicationName)"
            ],
            shortTitle: "Gasto rápido",
            systemImageName: "bolt.circle.fill"
        )
        AppShortcut(
            intent: MonthSummaryIntent(),
            phrases: [
                "Cuánto llevo gastado en \(.applicationName)",
                "Cuánto gasté este mes en \(.applicationName)",
                "Resumen del mes en \(.applicationName)"
            ],
            shortTitle: "Gasto del mes",
            systemImageName: "chart.bar.fill"
        )
    }
}
