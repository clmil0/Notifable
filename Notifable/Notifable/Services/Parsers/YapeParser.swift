import Foundation

struct YapeParser: BankEmailParser {
    
    var bankName: String {
        return "Yape"
    }
    
    var senderEmails: [String] {
        return ["notificaciones@yape.pe"]
    }
    
    func parse(cleanText: String) -> Expense? {
        // Amount
        let amountPattern = "Monto de yapeo[^a-zA-Z0-9]*\\s*S/\\s*([0-9.,]+)"
        guard let amountRegex = try? NSRegularExpression(pattern: amountPattern, options: [.dotMatchesLineSeparators]),
              let amountMatch = amountRegex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)),
              let amountRange = Range(amountMatch.range(at: 1), in: cleanText) else {
            return nil
        }
        let amountStr = String(cleanText[amountRange]).replacingOccurrences(of: ",", with: ".")
        let amount = Double(amountStr) ?? 0
        
        // Merchant
        var merchant = "Desconocido"
        let merchantPattern = "Nombre del Beneficiario\\s*(.*?)\\s*N[°º] de operaci[oó]n"
        if let merchantRegex = try? NSRegularExpression(pattern: merchantPattern, options: [.dotMatchesLineSeparators]),
           let merchantMatch = merchantRegex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)),
           let merchantRange = Range(merchantMatch.range(at: 1), in: cleanText) {
            let extracted = String(cleanText[merchantRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            merchant = "YAPE - \(extracted)"
        }
        
        // Date
        var expenseDate = Date()
        let datePattern = "Fecha y Hora de la operaci[oó]n\\s*(.*?)\\s*Celular del Beneficiario"
        if let dateRegex = try? NSRegularExpression(pattern: datePattern, options: [.dotMatchesLineSeparators]),
           let dateMatch = dateRegex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)),
           let dateRange = Range(dateMatch.range(at: 1), in: cleanText) {
            let dateStr = String(cleanText[dateRange])
            
            var dStr = dateStr.lowercased()
            let months = ["enero": "01", "febrero": "02", "marzo": "03", "abril": "04", "mayo": "05", "junio": "06", "julio": "07", "agosto": "08", "septiembre": "09", "octubre": "10", "noviembre": "11", "diciembre": "12"]
            for (m, num) in months {
                dStr = dStr.replacingOccurrences(of: m, with: num)
            }
            dStr = dStr.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
            
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "ddMMyyyy-hh:mma"
            if let parsed = formatter.date(from: dStr) {
                expenseDate = parsed
            }
        }
        
        return Expense(amount: amount, merchant: merchant, date: expenseDate, category: "Sin Clasificar", currency: "PEN")
    }
}
