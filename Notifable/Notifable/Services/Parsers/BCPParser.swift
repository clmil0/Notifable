import Foundation

struct BCPParser: BankEmailParser {
    
    var bankName: String {
        return "BCP"
    }
    
    var senderEmails: [String] {
        return ["notificaciones@notificacionesbcp.com.pe"]
    }
    
    func parse(cleanText: String) -> Expense? {
        // Asegurarnos que es un consumo de tarjeta de débito
        guard cleanText.contains("Consumo Tarjeta de D") || cleanText.contains("Realizaste un consumo") else {
            return nil
        }
        
        // Extraer Monto
        // Buscar: "Total del consumo S/ 42.00" o similar
        let amountPattern = "Total del consumo\\s*S/\\s*([0-9.,]+)"
        guard let amountRegex = try? NSRegularExpression(pattern: amountPattern, options: [.dotMatchesLineSeparators]),
              let amountMatch = amountRegex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)),
              let amountRange = Range(amountMatch.range(at: 1), in: cleanText) else {
            return nil
        }
        let amountStr = String(cleanText[amountRange]).replacingOccurrences(of: ",", with: "")
        let amount = Double(amountStr) ?? 0
        
        // Extraer Empresa
        // Buscar: "Empresa PLIN-DANIELA ADRIANA DO Número de operación"
        var merchant = "Desconocido"
        let merchantPattern = "Empresa\\s*(.*?)\\s*N[uú]mero de operaci[oó]n"
        if let merchantRegex = try? NSRegularExpression(pattern: merchantPattern, options: [.dotMatchesLineSeparators]),
           let merchantMatch = merchantRegex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)),
           let merchantRange = Range(merchantMatch.range(at: 1), in: cleanText) {
            merchant = String(cleanText[merchantRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // Patrón alternativo de empresa ("... con tu Tarjeta de Débito BCP en [EMPRESA]. Por tu...")
            let altMerchantPattern = "en\\s+([^.]+)\\.\\s*Por tu seguridad"
            if let altRegex = try? NSRegularExpression(pattern: altMerchantPattern, options: [.dotMatchesLineSeparators]),
               let altMatch = altRegex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)),
               let altRange = Range(altMatch.range(at: 1), in: cleanText) {
                merchant = String(cleanText[altRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Extraer últimos dígitos de la tarjeta. Cubre débito y crédito: un
        // "Realizaste un consumo... con tu Tarjeta de Crédito BCP" no traía
        // los dígitos porque este regex sólo buscaba "Débito".
        var cardLastDigits: String? = nil
        let cardPattern = "Tarjeta de (?:D[ée]bito|Cr[ée]dito)\\s*\\*+([0-9]{4})"
        if let cardRegex = try? NSRegularExpression(pattern: cardPattern, options: [.dotMatchesLineSeparators]),
           let cardMatch = cardRegex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)),
           let cardRange = Range(cardMatch.range(at: 1), in: cleanText) {
            cardLastDigits = String(cleanText[cardRange])
        }
        
        // Extraer Fecha y Hora
        // Buscar: "Fecha y hora 03 de setiembre de 2026 - 01:14 PM"
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
        
        // Si es un PLIN, rechazamos el parseo aquí para que YapeParser lo capture y lo cuente como Yape.
        let upperMerchant = merchant.uppercased()
        if upperMerchant.hasPrefix("PLIN-") || upperMerchant.hasPrefix("PLIN ") {
            return nil
        }
        
        return Expense(amount: amount, merchant: merchant, date: expenseDate, category: "Sin Clasificar", currency: "PEN", cardLastDigits: cardLastDigits)
    }

    /// "Constancia de recepción de Yapeo a celular BCP": dinero que **entra**,
    /// no un gasto. Es el único correo de BCP que representa un ingreso.
    func parseIncome(cleanText: String) -> Income? {
        guard cleanText.contains("Monto recibido") else {
            return nil
        }

        let amountPattern = "Monto recibido\\s*S/\\s*([0-9.,]+)"
        guard let amountRegex = try? NSRegularExpression(pattern: amountPattern, options: [.dotMatchesLineSeparators]),
              let amountMatch = amountRegex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)),
              let amountRange = Range(amountMatch.range(at: 1), in: cleanText) else {
            return nil
        }
        let amountStr = String(cleanText[amountRange]).replacingOccurrences(of: ",", with: "")
        let amount = Double(amountStr) ?? 0

        var sender = "Desconocido"
        let senderPattern = "Enviado por\\s*(.*?)\\s*¿No reconoces"
        if let senderRegex = try? NSRegularExpression(pattern: senderPattern, options: [.dotMatchesLineSeparators]),
           let senderMatch = senderRegex.firstMatch(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.utf16.count)),
           let senderRange = Range(senderMatch.range(at: 1), in: cleanText) {
            sender = String(cleanText[senderRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var incomeDate = Date()
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
            dStr = dStr.replacingOccurrences(of: " ", with: "")

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "ddMMyyyy-hh:mma"
            if let parsed = formatter.date(from: dStr) {
                incomeDate = parsed
            }
        }

        return Income(amount: amount, currency: "PEN", source: "Yape", title: sender, date: incomeDate)
    }
}
