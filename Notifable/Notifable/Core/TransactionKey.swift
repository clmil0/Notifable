import Foundation
import CryptoKit

/// Huella estable de un movimiento, para poder volver a encontrarlo después de
/// que la app se rearme releyendo el correo.
///
/// El problema: los gastos e ingresos NO se respaldan (se reconstruyen solos
/// desde Gmail), pero lo que el usuario decidió sobre ellos sí —"esto es una
/// deuda", "esto va en Salud"— y eso no está en ningún correo. Guardar esas
/// decisiones exige una llave que sobreviva a que el `Expense` se borre y se
/// vuelva a crear con otro `UUID`.
///
/// - `emailID` cuando existe: es el id del mensaje de Gmail, idéntico en
///   cualquier dispositivo y en cualquier relectura.
/// - Si no hay correo (movimiento creado a mano), una huella de
///   comercio + céntimos + día + moneda. Dos gastos idénticos el mismo día en
///   el mismo comercio colisionan a propósito: para lo que se guarda aquí
///   (deuda / categoría) tratarlos como uno es el comportamiento correcto.
enum TransactionKey {

    static func key(emailID: String?, merchant: String, amount: Double, currency: String, date: Date) -> String {
        if let emailID, !emailID.isEmpty { return "mail:" + emailID }
        return "fp:" + fingerprint(merchant: merchant, amount: amount, currency: currency, date: date)
    }

    static func key(for expense: Expense) -> String {
        key(emailID: expense.emailID,
            merchant: expense.merchant,
            amount: expense.amount,
            currency: expense.currency,
            date: expense.date)
    }

    private static func fingerprint(merchant: String, amount: Double, currency: String, date: Date) -> String {
        let day = dayFormatter.string(from: date)
        let name = merchant
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = "\(name)|\(Money.cents(amount))|\(day)|\(currency.uppercased())"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(24).description
    }

    /// Día del movimiento en UTC: la llave tiene que ser la misma aunque el
    /// teléfono cambie de zona horaria al viajar.
    nonisolated(unsafe) static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
