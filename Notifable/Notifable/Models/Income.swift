import Foundation
import SwiftData

@Model
final class Income {
    var id: UUID
    var amount: Double
    var currency: String
    var source: String // Ej: "Plin", "Yape", "Efectivo", "Transferencia"
    var title: String? // Título opcional, ej: "Sueldo", "Venta de laptop"
    var date: Date
    var notes: String?
    
    init(amount: Double, currency: String = "PEN", source: String, title: String? = nil, date: Date = Date(), notes: String? = nil) {
        self.id = UUID()
        self.amount = (amount * 100).rounded() / 100
        self.currency = currency
        self.source = source
        self.title = title
        self.date = date
        self.notes = notes
    }
}
