import Foundation

struct BBVAParser: BankEmailParser {
    
    var bankName: String {
        return "BBVA"
    }
    
    var senderEmails: [String] {
        return ["procesos@bbva.com.pe"]
    }
    
    func parse(cleanText: String) -> Expense? {
        if let expense = parsePlinSent(cleanText) { return expense }
        if let expense = parseBBVATransfer(cleanText) { return expense }
        if let expense = parseBBVAAutomaticPayment(cleanText) { return expense }
        if let expense = parseBBVAStandard(cleanText) { return expense }
        return nil
    }
    
    private func parsePlinSent(_ cleanText: String) -> Expense? {
        let plinPattern = "Plineaste\\s+(S/|\\$|PEN|USD)\\s*([0-9.,]+)\\s+a\\s+(.*?)\\s+(?:Detalles|Celular|Destino)"
        guard let plinRegex = try? NSRegularExpression(pattern: plinPattern, options: []),
              let match = plinRegex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)) else {
            return nil
        }
        
        var currency = "PEN"
        var amount: Double = 0
        var merchant = "Desconocido"
        var expenseDate = Date()
        
        if let curRange = Range(match.range(at: 1), in: cleanText) {
            let curStr = String(cleanText[curRange])
            currency = (curStr == "$" || curStr == "USD") ? "USD" : "PEN"
        }
        if let amtRange = Range(match.range(at: 2), in: cleanText) {
            let amtStr = String(cleanText[amtRange]).replacingOccurrences(of: ",", with: ".")
            amount = Double(amtStr) ?? 0
        }
        if let merRange = Range(match.range(at: 3), in: cleanText) {
            let extracted = String(cleanText[merRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            merchant = "PLIN - \(extracted)"
        }
        
        let plinDatePattern = "Fecha y hora:\\s*([0-9]{1,2}\\s+de\\s+[a-zA-Z]+,\\s*[0-9]{4}\\s+[0-9]{2}:[0-9]{2})"
        if let dateRegex = try? NSRegularExpression(pattern: plinDatePattern, options: []),
           let dateMatch = dateRegex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)) {
            if let dateRange = Range(dateMatch.range(at: 1), in: cleanText) {
                let dateStr = String(cleanText[dateRange])
                let formatter = DateFormatter()
                formatter.dateFormat = "dd 'de' MMMM, yyyy HH:mm"
                formatter.locale = Locale(identifier: "es_PE")
                if let parsed = formatter.date(from: dateStr.lowercased()) {
                    expenseDate = parsed
                }
            }
        }
        
        return Expense(amount: amount, merchant: merchant, date: expenseDate, category: "Sin Clasificar", currency: currency)
    }
    
    private func parseBBVATransfer(_ cleanText: String) -> Expense? {
        guard cleanText.contains("Transferir a terceros BBVA") || cleanText.contains("TRANSF. A CTAS. TERCEROS") else {
            return nil
        }
        
        var amount: Double = 0
        let amountPattern = "Importe cargado\\s*S/\\s*([0-9.,]+)"
        if let amountRegex = try? NSRegularExpression(pattern: amountPattern, options: []),
           let amtMatch = amountRegex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)),
           let range = Range(amtMatch.range(at: 1), in: cleanText) {
            let amountStr = String(cleanText[range]).replacingOccurrences(of: ",", with: "")
            amount = Double(amountStr) ?? 0
        } else {
            let altAmountPattern = "Importe transferido\\s*S/\\s*([0-9.,]+)"
            if let altRegex = try? NSRegularExpression(pattern: altAmountPattern, options: []),
               let amtMatch = altRegex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)),
               let range = Range(amtMatch.range(at: 1), in: cleanText) {
                let amountStr = String(cleanText[range]).replacingOccurrences(of: ",", with: "")
                amount = Double(amountStr) ?? 0
            } else {
                return nil
            }
        }
        
        var merchant = "BBVA - Transferencia a terceros"
        let merchantPattern = "Nombre del beneficiario\\s*(.*?)\\s*Concepto"
        if let merchantRegex = try? NSRegularExpression(pattern: merchantPattern, options: []),
           let match = merchantRegex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)),
           let range = Range(match.range(at: 1), in: cleanText) {
            let extracted = String(cleanText[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            merchant = "BBVA - \(extracted)"
        }
        
        var expenseDate = Date()
        let datePattern = "Fecha y hora de la operaci[oó]n\\s*([0-9]{1,2}\\s+[a-zA-Z]+,\\s*[0-9]{4}\\s+[0-9]{2}:[0-9]{2})"
        if let dateRegex = try? NSRegularExpression(pattern: datePattern, options: []),
           let dateMatch = dateRegex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)),
           let dateRange = Range(dateMatch.range(at: 1), in: cleanText) {
            
            var dateStr = String(cleanText[dateRange])
            dateStr = dateStr.lowercased().replacingOccurrences(of: "setiembre", with: "septiembre")
            
            let formatter = DateFormatter()
            formatter.dateFormat = "dd MMMM, yyyy HH:mm"
            formatter.locale = Locale(identifier: "es_PE")
            if let parsed = formatter.date(from: dateStr) {
                expenseDate = parsed
            }
        }
        
        var cardLastDigits: String? = nil
        let cardPattern = "Cuenta de origen\\s*(?:•\\s*)?([0-9]{4})"
        if let cardRegex = try? NSRegularExpression(pattern: cardPattern, options: []),
           let cMatch = cardRegex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)),
           let range = Range(cMatch.range(at: 1), in: cleanText) {
            cardLastDigits = String(cleanText[range])
        }
        
        return Expense(amount: amount, merchant: merchant, date: expenseDate, category: "Sin Clasificar", currency: "PEN", cardLastDigits: cardLastDigits)
    }
    
    private func parseBBVAStandard(_ cleanText: String) -> Expense? {
        let merchantPattern = "Comercio:\\s*(.*?)(?=\\s+Monto:)"
        guard let merchantRegex = try? NSRegularExpression(pattern: merchantPattern, options: []),
              let match = merchantRegex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)) else {
            return nil
        }
        
        var merchant = "Desconocido"
        if let range = Range(match.range(at: 1), in: cleanText) {
            merchant = String(cleanText[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        var amount: Double = 0
        let amountPattern = "Monto:\\s*([0-9.,]+)"
        if let amountRegex = try? NSRegularExpression(pattern: amountPattern, options: []),
           let amtMatch = amountRegex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)) {
            if let range = Range(amtMatch.range(at: 1), in: cleanText) {
                let amountStr = String(cleanText[range]).replacingOccurrences(of: ",", with: ".")
                amount = Double(amountStr) ?? 0
            }
        }
        
        var currency = "PEN"
        let currencyPattern = "Moneda:\\s*([A-Za-z]+)"
        if let currencyRegex = try? NSRegularExpression(pattern: currencyPattern, options: []),
           let curMatch = currencyRegex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)) {
            if let range = Range(curMatch.range(at: 1), in: cleanText) {
                currency = String(cleanText[range]).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            }
        }
        
        var expenseDate = Date()
        let datePattern = "Fecha:\\s*([0-9]{2}/[0-9]{2}/[0-9]{4})"
        let timePattern = "Hora:\\s*([0-9]{2}:[0-9]{2}:[0-9]{2})"
        var dateString = ""
        var timeString = ""
        
        if let dateRegex = try? NSRegularExpression(pattern: datePattern, options: []),
           let dMatch = dateRegex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)) {
            if let range = Range(dMatch.range(at: 1), in: cleanText) {
                dateString = String(cleanText[range])
            }
        }
        if let timeRegex = try? NSRegularExpression(pattern: timePattern, options: []),
           let tMatch = timeRegex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)) {
            if let range = Range(tMatch.range(at: 1), in: cleanText) {
                timeString = String(cleanText[range])
            }
        }
        
        if !dateString.isEmpty && !timeString.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "dd/MM/yyyy HH:mm:ss"
            formatter.timeZone = TimeZone.current
            if let parsedDate = formatter.date(from: "\(dateString) \(timeString)") {
                expenseDate = parsedDate
            }
        }
        
        var cardLastDigits: String? = nil
        let cardPattern = "tarjeta terminada en\\s*\\*?([0-9]{4})"
        if let cardRegex = try? NSRegularExpression(pattern: cardPattern, options: []),
           let cMatch = cardRegex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)) {
            if let range = Range(cMatch.range(at: 1), in: cleanText) {
                cardLastDigits = String(cleanText[range])
            }
        }
        
        return Expense(amount: amount, merchant: merchant, date: expenseDate, category: "Sin Clasificar", currency: currency, cardLastDigits: cardLastDigits)
    }
    
    private func parseBBVAAutomaticPayment(_ cleanText: String) -> Expense? {
        if !cleanText.contains("Pago autom") {
            return nil
        }
        
        var amount: Double = 0
        var currency = "PEN"
        let amountPattern = "Importe cargado\\s+(S/\\.|\\$|PEN|USD)\\s*([0-9.,]+)"
        if let regex = try? NSRegularExpression(pattern: amountPattern, options: []),
           let match = regex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)) {
            let curRange = Range(match.range(at: 1), in: cleanText)!
            let curStr = String(cleanText[curRange])
            currency = (curStr == "$" || curStr == "USD") ? "USD" : "PEN"
            
            let amtRange = Range(match.range(at: 2), in: cleanText)!
            amount = Double(String(cleanText[amtRange]).replacingOccurrences(of: ",", with: ".")) ?? 0
        } else {
            return nil
        }
        
        var merchant = "Pago automático"
        let merchantPattern = "Nombre de servicio\\s+(.*?)(?=\\s+(?:Dato|Descripci|Fecha))"
        if let regex = try? NSRegularExpression(pattern: merchantPattern, options: []),
           let match = regex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)) {
            let merRange = Range(match.range(at: 1), in: cleanText)!
            merchant = String(cleanText[merRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        var expenseDate = Date()
        let datePattern = "Fecha y hora de la operaci.*?n\\s*([0-9]{1,2}\\s+[a-zA-Z]+\\s+[0-9]{4}\\s+[0-9]{2}:[0-9]{2})"
        if let regex = try? NSRegularExpression(pattern: datePattern, options: []),
           let match = regex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)) {
            let dateRange = Range(match.range(at: 1), in: cleanText)!
            // Limpiar múltiples espacios que puedan haberse generado
            var dateStr = String(cleanText[dateRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let regexSpace = try? NSRegularExpression(pattern: "\\s+", options: []) {
                dateStr = regexSpace.stringByReplacingMatches(in: dateStr, options: [], range: NSRange(location: 0, length: dateStr.utf16.count), withTemplate: " ")
            }
            
            let formatter = DateFormatter()
            formatter.dateFormat = "dd MMMM yyyy HH:mm"
            formatter.locale = Locale(identifier: "es_PE")
            if let parsedDate = formatter.date(from: dateStr.lowercased()) {
                expenseDate = parsedDate
            }
        }
        
        var cardLastDigits: String? = nil
        let cardPattern = "Cargo en tarjeta\\s*(?:•\\s*)?([0-9]{4})"
        if let regex = try? NSRegularExpression(pattern: cardPattern, options: []),
           let match = regex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)) {
            let cardRange = Range(match.range(at: 1), in: cleanText)!
            cardLastDigits = String(cleanText[cardRange])
        }
        
        // As it's an automatic payment, maybe mark it as subscription by default?
        return Expense(amount: amount, merchant: merchant, date: expenseDate, category: "Sin Clasificar", isSubscription: true, currency: currency, cardLastDigits: cardLastDigits)
    }
}
