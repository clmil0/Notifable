import Foundation

/// Pide a Resumen que lleve a un movimiento de Actividad Reciente y lo
/// resalte — p. ej. desde «¿A dónde va?», para ver la deuda a la que abona un
/// ingreso.
///
/// Es un aviso y no un binding porque quien lo pide vive dentro de hojas
/// presentadas por Resumen; Resumen cierra esas hojas al recibirlo.
enum ActivityFocus {

    static let notification = Notification.Name("activityFocusRequest")

    static func request(transactionID: UUID, date: Date) {
        NotificationCenter.default.post(name: notification, object: nil,
                                        userInfo: ["id": transactionID, "date": date])
    }
}
