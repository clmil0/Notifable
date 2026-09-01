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
    
    func updateDebtNotification(hasDebts: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        
        if hasDebts {
            let content = UNMutableNotificationContent()
            content.title = "Deuda Pendiente"
            content.body = "Tienes deudas pendientes por cancelar. ¡Revisa tu resumen!"
            content.sound = .default
            
            var dateComponents = DateComponents()
            dateComponents.hour = 10
            dateComponents.minute = 0
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(identifier: "dailyDebtReminder", content: content, trigger: trigger)
            
            center.add(request) { error in
                if let error = error {
                    print("Error programando notificación de deuda: \(error.localizedDescription)")
                } else {
                    print("Notificación de deuda programada con éxito para las 10:00 AM")
                }
            }
        } else {
            print("No hay deudas. Notificaciones canceladas.")
        }
    }
}
