import SwiftUI
import SwiftData

/// Notificaciones. Cada toggle dice **cuándo** llega el aviso, no sólo qué
/// activa: un interruptor que no dice cuándo suena no se puede decidir.
struct NotificationSettingsView: View {

    @Query private var expenses: [Expense]
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.purple.rawValue

    @AppStorage(NotificationSettings.budgetKey) private var notificationsEnabled = true
    @AppStorage(NotificationSettings.recurringKey) private var remindRecurring = true
    @AppStorage(NotificationSettings.debtEnabledKey) private var debtReminderEnabled = true
    @AppStorage(NotificationSettings.debtHourKey) private var debtHour = 10
    @AppStorage(NotificationSettings.debtMinuteKey) private var debtMinute = 0
    @AppStorage("debtNotificationFrequency") private var debtFrequency = "Diario"
    @AppStorage(NotificationManager.categoryLimitEnabledKey) private var limitAlertsEnabled = true

    private var tint: Color { AppThemeColor(rawValue: appAccentColor)?.color ?? .purple }

    var body: some View {
        Form {
            Section {
                Toggle("Presupuesto", isOn: $notificationsEnabled)
                    .tint(tint)
            } header: {
                Text("Avisos")
            } footer: {
                Text("Cuando pases el 80% de tu meta o el ritmo esperado.")
            }

            Section {
                Toggle("Límites por categoría", isOn: $limitAlertsEnabled)
                    .tint(tint)
            } footer: {
                Text("Una vez por ciclo: al llegar al umbral que pusiste en cada categoría y al pasarte de su límite.")
            }

            Section {
                Toggle("Gastos recurrentes", isOn: $remindRecurring)
                    .tint(tint)
            } footer: {
                Text("El día que hay gastos programados esperando confirmación.")
            }

            Section {
                Toggle("Recordatorio de deuda", isOn: $debtReminderEnabled)
                    .tint(tint)

                if debtReminderEnabled {
                    // Sólo hora y minuto: guardar un `timeIntervalSince1970`
                    // completo dejaba el recordatorio anclado al día en que se
                    // configuró.
                    DatePicker("Hora", selection: timeBinding, displayedComponents: .hourAndMinute)

                    Picker("Frecuencia", selection: frequencyBinding) {
                        Text("Diario").tag("Diario")
                        Text("Semanal").tag("Semanal")
                        Text("Mensual").tag("Mensual")
                    }
                }
            } footer: {
                Text(debtReminderEnabled
                     ? "A las \(NotificationSettings.timeLabel(hour: debtHour, minute: debtMinute)), mientras tengas deudas activas."
                     : "Sin aviso de deudas pendientes.")
            }
        }
        .navigationTitle("Notificaciones")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: debtReminderEnabled) { _, _ in refresh() }
    }

    /// El `DatePicker` necesita una `Date`; se compone y se descompone en el
    /// momento, y lo que se guarda son dos enteros.
    private var timeBinding: Binding<Date> {
        Binding(
            get: { NotificationSettings.date(hour: debtHour, minute: debtMinute) },
            set: { newValue in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                debtHour = comps.hour ?? 10
                debtMinute = comps.minute ?? 0
                refresh()
            }
        )
    }

    private var frequencyBinding: Binding<String> {
        Binding(
            get: { debtFrequency },
            set: { debtFrequency = $0; refresh() }
        )
    }

    private func refresh() {
        let hasDebts = expenses.contains { $0.isDebt }
        NotificationManager.shared.updateDebtNotification(hasDebts: hasDebts && debtReminderEnabled)
    }
}

/// Claves y formato del bloque de notificaciones, en un solo sitio para que la
/// pantalla y `NotificationManager` no interpreten lo mismo de dos maneras.
enum NotificationSettings {

    static let budgetKey = "notificationsEnabled"
    static let recurringKey = "remindRecurring"
    static let debtEnabledKey = "debtReminderEnabled"
    static let debtHourKey = "debtReminderHour"
    static let debtMinuteKey = "debtReminderMinute"

    /// Migración del `timeIntervalSince1970` anterior: se conserva la hora que
    /// el usuario había elegido y se descarta la fecha, que era el problema.
    static func migrateIfNeeded(defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: debtHourKey) == nil else { return }
        let legacy = defaults.double(forKey: "debtNotificationTimeInterval")
        let date = legacy > 0 ? Date(timeIntervalSince1970: legacy) : nil
        let comps = date.map { Calendar.current.dateComponents([.hour, .minute], from: $0) }
        defaults.set(comps?.hour ?? 10, forKey: debtHourKey)
        defaults.set(comps?.minute ?? 0, forKey: debtMinuteKey)
        defaults.removeObject(forKey: "debtNotificationTimeInterval")
    }

    static func hour(_ defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: debtHourKey) as? Int ?? 10
    }

    static func minute(_ defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: debtMinuteKey) as? Int ?? 0
    }

    static func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    static func timeLabel(hour: Int, minute: Int) -> String {
        String(format: "%d:%02d", hour, minute)
    }

    /// Cuántos avisos hay encendidos, para la fila de la raíz.
    static func activeCount(_ defaults: UserDefaults = .standard) -> Int {
        var count = 0
        if defaults.object(forKey: budgetKey) as? Bool ?? true { count += 1 }
        if defaults.object(forKey: recurringKey) as? Bool ?? true { count += 1 }
        if defaults.object(forKey: debtEnabledKey) as? Bool ?? true { count += 1 }
        return count
    }
}
