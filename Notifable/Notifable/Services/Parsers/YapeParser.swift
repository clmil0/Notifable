import Foundation

struct YapeParser: BankEmailParser {
    
    var bankName: String {
        return "Yape"
    }
    
    var senderEmails: [String] {
        return ["notificaciones@yape.pe", "notificaciones@notificacionesbcp.com.pe"]
    }
    
    func parse(cleanText: String) -> Expense? {
        if let yapeExpense = parseStandardYape(cleanText: cleanText) {
            return yapeExpense
        }
        
        if let bcpPlinExpense = parseBCPPlin(cleanText: cleanText) {
            return bcpPlinExpense
        }
        
        return nil
    }
    
    private func parseStandardYape(cleanText: String) -> Expense? {
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

    private func parseBCPPlin(cleanText: String) -> Expense? {
        guard cleanText.contains("Consumo Tarjeta de D") || cleanText.contains("Realizaste un consumo") else {
            return nil
        }
        
        var merchant = "Desconocido"
        let merchantPattern = "Empresa\\s*(.*?)\\s*N[uú]mero de operaci[oó]n"
        if let merchantRegex = try? NSRegularExpression(pattern: merchantPattern, options: [.dotMatchesLineSeparators]),
           let merchantMatch = merchantRegex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)),
           let merchantRange = Range(merchantMatch.range(at: 1), in: cleanText) {
            merchant = String(cleanText[merchantRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let altMerchantPattern = "en\\s+([^.]+)\\.\\s*Por tu seguridad"
            if let altRegex = try? NSRegularExpression(pattern: altMerchantPattern, options: [.dotMatchesLineSeparators]),
               let altMatch = altRegex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)),
               let altRange = Range(altMatch.range(at: 1), in: cleanText) {
                merchant = String(cleanText[altRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        let upperMerchant = merchant.uppercased()
        guard upperMerchant.hasPrefix("PLIN-") || upperMerchant.hasPrefix("PLIN ") else {
            return nil
        }
        
        let amountPattern = "Total del consumo\\s*S/\\s*([0-9.,]+)"
        guard let amountRegex = try? NSRegularExpression(pattern: amountPattern, options: [.dotMatchesLineSeparators]),
              let amountMatch = amountRegex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)),
              let amountRange = Range(amountMatch.range(at: 1), in: cleanText) else {
            return nil
        }
        let amountStr = String(cleanText[amountRange]).replacingOccurrences(of: ",", with: "")
        let amount = Double(amountStr) ?? 0
        
        var cardLastDigits: String? = nil
        let cardPattern = "Tarjeta de D[ée]bito\\s*\\*+([0-9]{4})"
        if let cardRegex = try? NSRegularExpression(pattern: cardPattern, options: [.dotMatchesLineSeparators]),
           let cardMatch = cardRegex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)),
           let cardRange = Range(cardMatch.range(at: 1), in: cleanText) {
            cardLastDigits = String(cleanText[cardRange])
        }
        
        var expenseDate = Date()
        let datePattern = "Fecha y hora\\s*([0-9]{2}\\s*de\\s*[a-zA-Z]+\\s*de\\s*[0-9]{4}\\s*-\\s*[0-9]{2}:[0-9]{2}\\s*[APM]{2})"
        if let dateRegex = try? NSRegularExpression(pattern: datePattern, options: [.dotMatchesLineSeparators]),
           let dateMatch = dateRegex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)),
           let dateRange = Range(dateMatch.range(at: 1), in: cleanText) {
            let dateStr = String(cleanText[dateRange])
            
            var dStr = dateStr.lowercased()
            let months = ["enero": "01", "febrero": "02", "marzo": "03", "abril": "04", "mayo": "05", "junio": "06", "julio": "07", "agosto": "08", "septiembre": "09", "setiembre": "09", "octubre": "10", "noviembre": "11", "diciembre": "12"]
            for (m, num) in months {
                dStr = dStr.replacingOccurrences(of: m, with: num)
            }
            dStr = dStr.replacingOccurrences(of: " de ", with: "")
            dStr = dStr.replacingOccurrences(of: " - ", with: "-")
            dStr = dStr.replacingOccurrences(of: " ", with: "") // e.g. 03092026-01:14pm
            
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "ddMMyyyy-hh:mma"
            if let parsed = formatter.date(from: dStr) {
                expenseDate = parsed
            }
        }
        
        let extracted = merchant.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
        let finalMerchant = "YAPE - \(extracted)"
        
        return Expense(amount: amount, merchant: finalMerchant, date: expenseDate, category: "Sin Clasificar", currency: "PEN", cardLastDigits: cardLastDigits)
    }
}
