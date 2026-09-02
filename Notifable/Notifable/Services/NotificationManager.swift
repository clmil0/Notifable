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
