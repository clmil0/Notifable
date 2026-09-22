import Foundation

/// Pide ir a un movimiento — p. ej. desde «¿A dónde va?», para ver la deuda a
/// la que abona un ingreso. `ContentView` abre su detalle.
///
/// Es un aviso y no un binding porque quien lo pide vive dentro de hojas
/// presentadas por otras pantallas; esas pantallas cierran sus hojas al
/// recibirlo.
enum ActivityFocus {

    static let notification = Notification.Name("activityFocusRequest")

    struct Request: Equatable {
        let id: UUID
        let date: Date
    }

    static func request(transactionID: UUID, date: Date) {
        NotificationCenter.default.post(name: notification, object: nil,
                                        userInfo: ["id": transactionID, "date": date])
    }

    static func request(from note: Notification) -> Request? {
        guard let id = note.userInfo?["id"] as? UUID,
              let date = note.userInfo?["date"] as? Date else { return nil }
        return Request(id: id, date: date)
    }
}
