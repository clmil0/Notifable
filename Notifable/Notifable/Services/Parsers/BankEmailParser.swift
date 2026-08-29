import Foundation

protocol BankEmailParser {
    var bankName: String { get }
    
    /// Devuelve las direcciones de correo electrónico que envía este banco (ej. procesos@bbva.com.pe)
    var senderEmails: [String] { get }
    
    /// Analiza el texto limpio de un correo y devuelve un `Expense` si logra interpretarlo
    func parse(cleanText: String) -> Expense?
}
