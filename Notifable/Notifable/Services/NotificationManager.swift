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
            
            let timeInterval = UserDefaults.standard.double(forKey: "debtNotificationTimeInterval")
            let date = timeInterval > 0 ? Date(timeIntervalSince1970: timeInterval) : Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!
            
            var dateComponents = Calendar.current.dateComponents([.hour, .minute], from: date)
            
            let frequency = UserDefaults.standard.string(forKey: "debtNotificationFrequency") ?? "Diario"
            if frequency == "Semanal" {
                dateComponents.weekday = Calendar.current.component(.weekday, from: date)
            } else if frequency == "Mensual" {
                dateComponents.day = Calendar.current.component(.day, from: date)
            }
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(identifier: "dailyDebtReminder", content: content, trigger: trigger)
            
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
}
