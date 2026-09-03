import Foundation
import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()
    
    private init() {}
    
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notificaciones permitidas")
            } else if let error = error {
                print("Error pidiendo permiso de notificaciones: \(error.localizedDescription)")
            }
        }
    }
    
    static let debtReminderID = "dailyDebtReminder"
    static let recurringReminderID = "recurringPendingReminder"

    func updateDebtNotification(hasDebts: Bool) {
        let center = UNUserNotificationCenter.current()
        // Sólo el suyo: `removeAllPendingNotificationRequests` borraba también
        // el recordatorio de recurrentes.
        center.removePendingNotificationRequests(withIdentifiers: [NotificationManager.debtReminderID])
        
        if hasDebts {
            let content = UNMutableNotificationContent()
            content.title = "Deuda Pendiente"
            content.body = "Tienes deudas pendientes por cancelar. ¡Revisa tu resumen!"
            content.sound = .default
            
            // Hora y minuto, no una fecha completa: antes se guardaba un
            // `timeIntervalSince1970` y el recordatorio quedaba anclado al día
            // en que se configuró.
            var dateComponents = DateComponents()
            dateComponents.hour = NotificationSettings.hour()
            dateComponents.minute = NotificationSettings.minute()
            let date = NotificationSettings.date(hour: NotificationSettings.hour(),
                                                 minute: NotificationSettings.minute())
            
            let frequency = UserDefaults.standard.string(forKey: "debtNotificationFrequency") ?? "Diario"
            if frequency == "Semanal" {
                dateComponents.weekday = Calendar.current.component(.weekday, from: date)
            } else if frequency == "Mensual" {
                dateComponents.day = Calendar.current.component(.day, from: date)
            }
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(identifier: NotificationManager.debtReminderID, content: content, trigger: trigger)
            
            center.add(request) { error in
                if let error = error {
                    print("Error programando notificación de deuda: \(error.localizedDescription)")
                } else {
                    print("Notificación de deuda programada para: \(dateComponents) (\(frequency))")
                }
            }
        } else {
            print("No hay deudas. Notificaciones canceladas.")
        }
    }

    // MARK: - Límites por categoría

    static let categoryLimitEnabledKey = "categoryLimitAlerts"
    private static let categoryLimitStateKey = "categoryLimitNoticeState"
    private static func categoryLimitID(_ category: String) -> String { "categoryLimit-" + category }

    /// Aviso del límite de una categoría.
    ///
    /// El color de la lista ya cuenta la historia cuando la app está abierta;
    /// esto es para cuando no lo está. Se manda **una vez por ciclo y por
    /// estado**: al cruzar el umbral y al pasarse. Repetirlo cada vez que se
    /// registra un gasto convertiría el aviso en ruido, y un aviso que se
    /// ignora es peor que ninguno.
    func updateCategoryLimitNotices(_ statuses: [CategoryLimitStatus],
                                    enabled: Bool,
                                    defaults: UserDefaults = .standard) {
        let center = UNUserNotificationCenter.current()

        guard enabled else {
            let ids = statuses.map { NotificationManager.categoryLimitID($0.category) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            defaults.removeObject(forKey: NotificationManager.categoryLimitStateKey)
            return
        }

        var state = defaults.dictionary(forKey: NotificationManager.categoryLimitStateKey) as? [String: String] ?? [:]

        for status in statuses where status.hasLimit {
            let level = status.level
            guard level == .cerca || level == .pasado else {
                state[status.category] = nil
                continue
            }

            // La marca lleva el inicio del ciclo: el mes siguiente vuelve a
            // avisar aunque el estado sea el mismo.
            let stamp = String(Int(status.cycleStart.timeIntervalSince1970)) + "|" + (level == .pasado ? "pasado" : "cerca")
            guard state[status.category] != stamp else { continue }
            state[status.category] = stamp

            let content = UNMutableNotificationContent()
            if level == .pasado {
                content.title = status.category + " pasó su límite"
                content.body = Money.formatCompact(status.overBy) + " arriba de "
                    + Money.formatCompact(status.limit) + ". El límite avisa, no bloquea: puedes seguir registrando."
            } else {
                content.title = status.category + " va por " + Money.formatPercent(status.spent, of: status.limit)
                content.body = "Quedan " + Money.formatCompact(status.remaining)
                    + " para el resto del ciclo (" + status.daysLeftLabel + ")."
            }
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: NotificationManager.categoryLimitID(status.category),
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            )
            center.add(request) { error in
                if let error { print("Error programando aviso de límite: \(error.localizedDescription)") }
            }
        }

        defaults.set(state, forKey: NotificationManager.categoryLimitStateKey)
    }

    /// Recordatorio de gastos recurrentes vencidos.
    ///
    /// Sin esto las pendientes se acumulan sin que nadie las vea, y el mes se ve
    /// más barato de lo que es: no cuentan en ningún total hasta confirmarlas.
    func updateRecurringReminder(count: Int, total: Double, merchant: String?, enabled: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [NotificationManager.recurringReminderID])
        guard enabled, count > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Gastos programados para hoy"
        if count == 1, let merchant {
            content.body = merchant + " " + Money.format(total)
                + " programado para hoy. Confirma o ajusta el monto."
        } else {
            content.body = "\(count) gastos por " + Money.format(total)
                + " esperan tu confirmación. No cuentan en tu mes hasta que los aceptes."
        }
        content.sound = .default

        // A media mañana del mismo día; si ya pasó la hora, en un minuto.
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 10
        comps.minute = 0
        let fireDate = cal.date(from: comps) ?? Date()
        let interval = max(60, fireDate.timeIntervalSinceNow)

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: NotificationManager.recurringReminderID,
                                            content: content, trigger: trigger)
        center.add(request) { error in
            if let error { print("Error programando recordatorio de recurrentes: \(error.localizedDescription)") }
        }
    }
}
