import Foundation
import SwiftData

class GmailSyncService: ObservableObject {
    
    static let shared = GmailSyncService()
    
    @Published var isSyncing: Bool = false
    @Published var lastSyncError: String?
    
    // Progress tracking
    @Published var totalEmailsToProcess: Int = 0
    @Published var emailsProcessed: Int = 0
    @Published var expensesFoundByBank: [String: Int] = [:]
    
    // Throttling
    @Published var lastSyncDate: Date? {
        didSet {
            if let date = lastSyncDate {
                UserDefaults.standard.set(date, forKey: "lastSyncDate")
            }
        }
    }
    @Published var diagnosticResult: String = ""
    @Published var showDiagnostic: Bool = false
    
    private let baseURL = "https://gmail.googleapis.com/gmail/v1/users/me"
    
    // Lista de parsers modulares de cada banco
    private let parsers: [BankEmailParser] = [
        BBVAParser(),
        BCPParser(),
        YapeParser(),
        InterbankParser(),
        ScotiabankParser()
    ]
    
    // Configura el ModelContext desde el lugar donde se llame
    var modelContext: ModelContext?
    
    init() {
        self.lastSyncDate = UserDefaults.standard.object(forKey: "lastSyncDate") as? Date
    }
    
    func syncEmails(force: Bool = false, startDate: Date? = nil, endDate: Date? = nil) {
        // Throttling: Solo sincronizar si ha pasado más de 1 min o si es forzado
        if !force, let lastSync = lastSyncDate, Date().timeIntervalSince(lastSync) < 1 * 60 {
            print("Sync throttled. Last sync was \(Int(Date().timeIntervalSince(lastSync)/60)) minutes ago.")
            return
        }
        
        DispatchQueue.main.async {
            self.isSyncing = true
            self.lastSyncError = nil
            self.totalEmailsToProcess = 0
            self.emailsProcessed = 0
            self.expensesFoundByBank = [:]
        }
        
        guard let token = GmailAuthService.shared.getAccessToken() else {
            DispatchQueue.main.async {
                self.isSyncing = false
                self.lastSyncError = "No access token"
            }
            return
        }
        
        fetchMessageList(token: token, startDate: startDate, endDate: endDate) { [weak self] result in
            switch result {
            case .success(let messages):
                self?.processMessages(messages, token: token)
            case .failure(let error):
                // Token might be expired, try to refresh
                print("Failed to fetch messages: \(error). Trying to refresh token...")
                GmailAuthService.shared.refreshAccessToken { newToken in
                    if let newToken = newToken {
                        self?.fetchMessageList(token: newToken, startDate: startDate, endDate: endDate) { result in
                            switch result {
                            case .success(let msgs):
                                self?.processMessages(msgs, token: newToken)
                            case .failure(let err):
                                DispatchQueue.main.async {
                                    self?.isSyncing = false
                                    self?.lastSyncError = err.localizedDescription
                                }
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            self?.isSyncing = false
                            self?.lastSyncError = "Token refresh failed"
                        }
                    }
                }
            }
        }
    }
    
    private func fetchMessageList(token: String, startDate: Date? = nil, endDate: Date? = nil, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        // Buscar correos dinámicamente según los bancos soportados
        let allEmails = parsers.flatMap { $0.senderEmails }
        var query = allEmails.isEmpty ? "" : allEmails.map { "from:\($0)" }.joined(separator: " OR ")
        
        if let start = startDate {
            let startEpoch = Int(start.timeIntervalSince1970)
            query = "(\(query)) AND after:\(startEpoch)"
        } else if let lastSync = lastSyncDate {
            let safeEpoch = Int(lastSync.timeIntervalSince1970) - 3600 // 1 hr margen
            query = "(\(query)) AND after:\(safeEpoch)"
        } else {
            if let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date()) {
                let startEpoch = Int(oneMonthAgo.timeIntervalSince1970)
                query = "(\(query)) AND after:\(startEpoch)"
            }
        }
        
        if let end = endDate {
            // Set end to the end of the day to include the selected date fully
            let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: end) ?? end
            let endEpoch = Int(endOfDay.timeIntervalSince1970)
            query = "\(query) AND before:\(endEpoch)"
        }
        
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        
        let urlString = "\(baseURL)/messages?q=\(encodedQuery)&maxResults=500"
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                completion(.failure(NSError(domain: "Auth", code: 401, userInfo: nil)))
                return
            }
            guard let data = data else { return }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let messages = json["messages"] as? [[String: Any]] {
                    completion(.success(messages))
                } else {
                    completion(.success([]))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    private func processMessages(_ messages: [[String: Any]], token: String) {
        let processedIDs = UserDefaults.standard.stringArray(forKey: "processedEmailIDs") ?? []
        let newMessages = messages.filter { msg in
            guard let id = msg["id"] as? String else { return false }
            return !processedIDs.contains(id)
        }
        
        DispatchQueue.main.async {
            self.totalEmailsToProcess = newMessages.count
            self.emailsProcessed = 0
            self.expensesFoundByBank = [:]
            for parser in self.parsers {
                self.expensesFoundByBank[parser.bankName] = 0
            }
        }
        
        var newIDs = processedIDs
        let queue = DispatchQueue(label: "com.notifable.syncQueue") // Para evitar race conditions
        
        let group = DispatchGroup()
        var newExpensesFound = 0
        let semaphore = DispatchSemaphore(value: 5) // Maximum 5 concurrent requests
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for message in newMessages {
                guard let id = message["id"] as? String else { continue }
                
                semaphore.wait()
                group.enter()
                self?.fetchMessageDetails(id: id, token: token) { body in
                    defer {
                        semaphore.signal()
                        group.leave()
                    }
                    
                    var foundBankName: String? = nil
                    
                    if let body = body {
                        if let expenseData = self?.parseEmailBody(body) {
                            foundBankName = expenseData.bankName
                            DispatchQueue.main.sync {
                                if let context = self?.modelContext {
                                    expenseData.expense.emailID = id
                                    context.insert(expenseData.expense)
                                    try? context.save()
                                    newExpensesFound += 1
                                }
                            }
                        }
                        // Only add to processed if we successfully fetched it (prevents skipping on network failure)
                        queue.async {
                            if !newIDs.contains(id) {
                                newIDs.append(id)
                            }
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self?.emailsProcessed += 1
                        if let bankName = foundBankName {
                            self?.expensesFoundByBank[bankName, default: 0] += 1
                        }
                    }
                }
            }
            
            group.wait()
            DispatchQueue.main.async {
                queue.sync {
                    UserDefaults.standard.set(newIDs, forKey: "processedEmailIDs")
                }
                self?.lastSyncDate = Date()
                self?.isSyncing = false
                print("Sync complete. Found \(newExpensesFound) new expenses.")
            }
        }
    }
    
    func recoverExpenses(ids: [String]) {
        guard let token = GmailAuthService.shared.getAccessToken() else { return }
        
        DispatchQueue.main.async {
            self.isSyncing = true
            self.lastSyncError = nil
            self.totalEmailsToProcess = ids.count
            self.emailsProcessed = 0
            self.expensesFoundByBank = [:]
        }
        
        var processedIDs = UserDefaults.standard.stringArray(forKey: "processedEmailIDs") ?? []
        let queue = DispatchQueue(label: "com.notifable.syncQueue")
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: 5)
        var newExpensesFound = 0
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for id in ids {
                semaphore.wait()
                group.enter()
                self?.fetchMessageDetails(id: id, token: token) { body in
                    defer {
                        semaphore.signal()
                        group.leave()
                    }
                    
                    var foundBankName: String? = nil
                    if let body = body {
                        if let expenseData = self?.parseEmailBody(body) {
                            foundBankName = expenseData.bankName
                            DispatchQueue.main.sync {
                                if let context = self?.modelContext {
                                    expenseData.expense.emailID = id
                                    context.insert(expenseData.expense)
                                    try? context.save()
                                    newExpensesFound += 1
                                }
                            }
                        }
                        
                        queue.async {
                            if !processedIDs.contains(id) {
                                processedIDs.append(id)
                            }
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self?.emailsProcessed += 1
                        if let bankName = foundBankName {
                            self?.expensesFoundByBank[bankName, default: 0] += 1
                        }
                    }
                }
            }
            
            group.wait()
            DispatchQueue.main.async {
                queue.sync {
                    UserDefaults.standard.set(processedIDs, forKey: "processedEmailIDs")
                    // Limpiamos la papelera
                    UserDefaults.standard.removeObject(forKey: "pendingRecoveryIDs")
                }
                self?.isSyncing = false
                print("Recovery complete. Restored \(newExpensesFound) expenses.")
            }
        }
    }
    
    func resetSyncState() {
        UserDefaults.standard.removeObject(forKey: "processedEmailIDs")
        UserDefaults.standard.removeObject(forKey: "lastSyncDate")
        DispatchQueue.main.async {
            self.lastSyncDate = nil
        }
    }
    
    func diagnosticBBVA() {
        guard let token = GmailAuthService.shared.getAccessToken() else {
            DispatchQueue.main.async { self.diagnosticResult = "No token"; self.showDiagnostic = true }
            return
        }
        DispatchQueue.main.async { self.diagnosticResult = "Buscando..."; self.showDiagnostic = true }
        
        let query = "from:procesos@bbva.com.pe pago"
        guard let url = URL(string: "\(baseURL)/messages?q=\(query)&maxResults=1") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data else { return }
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let messages = json["messages"] as? [[String: Any]],
                   let firstMessage = messages.first,
                   let id = firstMessage["id"] as? String {
                    self.fetchDiagnosticDetails(id: id, token: token)
                } else {
                    let raw = String(data: data, encoding: .utf8) ?? ""
                    DispatchQueue.main.async { self.diagnosticResult = "No se encontraron correos de BBVA Pago. \n\n\(raw)" }
                }
            } catch {}
        }.resume()
    }
    
    private func fetchDiagnosticDetails(id: String, token: String) {
        guard let url = URL(string: "\(baseURL)/messages/\(id)?format=full") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data else { return }
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    let bodyText = self.extractFullText(from: json)
                    let parser = YapeParser()
                    let result = parser.parse(cleanText: bodyText)
                    
                    let finalStr = """
                    --- RAW JSON ---
                    Snippet: \(json["snippet"] as? String ?? "")
                    
                    --- TEXTO EXTRAÍDO ---
                    \(bodyText)
                    
                    --- RESULTADO PARSER ---
                    Monto: \(result != nil ? String(result!.amount) : "NIL")
                    Merchant: \(result != nil ? result!.merchant : "NIL")
                    """
                    DispatchQueue.main.async { self.diagnosticResult = finalStr }
                }
            } catch {}
        }.resume()
    }
    
    private func fetchMessageDetails(id: String, token: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/messages/\(id)?format=full") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    let bodyText = self.extractFullText(from: json)
                    
                    // DEBUG: Guardar el texto si es de BBVA
                    if bodyText.lowercased().contains("pago autom") {
                        try? bodyText.write(to: URL(fileURLWithPath: "/Users/josephmt/Downloads/bbva_body.txt"), atomically: true, encoding: .utf8)
                    }
                    
                    completion(bodyText)
                } else {
                    completion(nil)
                }
            } catch {
                completion(nil)
            }
        }.resume()
    }
    
    private func extractFullText(from json: [String: Any]) -> String {
        guard let payload = json["payload"] as? [String: Any] else {
            return json["snippet"] as? String ?? ""
        }
        
        var plainText = ""
        var htmlText = ""
        
        func traverseParts(_ parts: [[String: Any]]) {
            for part in parts {
                if let mimeType = part["mimeType"] as? String {
                    if mimeType == "text/plain", let body = part["body"] as? [String: Any], let data = body["data"] as? String, let decoded = self.decodeBase64Url(data) {
                        plainText += self.decodeQuotedPrintable(decoded) + " "
                    } else if mimeType == "text/html", let body = part["body"] as? [String: Any], let data = body["data"] as? String, let decoded = self.decodeBase64Url(data) {
                        htmlText += self.decodeQuotedPrintable(decoded) + " "
                    }
                }
                if let subParts = part["parts"] as? [[String: Any]] {
                    traverseParts(subParts)
                }
            }
        }
        
        if let parts = payload["parts"] as? [[String: Any]] {
            traverseParts(parts)
        } else if let mimeType = payload["mimeType"] as? String, let body = payload["body"] as? [String: Any], let data = body["data"] as? String, let decoded = self.decodeBase64Url(data) {
            if mimeType == "text/plain" { plainText = self.decodeQuotedPrintable(decoded) }
            if mimeType == "text/html" { htmlText = self.decodeQuotedPrintable(decoded) }
        }
        
        if !plainText.isEmpty {
            return plainText
        } else if !htmlText.isEmpty {
            // Strip HTML tags roughly by replacing them with spaces
            var stripped = htmlText.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression, range: nil)
            stripped = stripped.replacingOccurrences(of: "&nbsp;", with: " ")
            stripped = stripped.replacingOccurrences(of: "&aacute;", with: "á")
            stripped = stripped.replacingOccurrences(of: "&eacute;", with: "é")
            stripped = stripped.replacingOccurrences(of: "&iacute;", with: "í")
            stripped = stripped.replacingOccurrences(of: "&oacute;", with: "ó")
            stripped = stripped.replacingOccurrences(of: "&uacute;", with: "ú")
            stripped = stripped.replacingOccurrences(of: "&ntilde;", with: "ñ")
            stripped = stripped.replacingOccurrences(of: "&bull;", with: "")
            return stripped
        }
        
        return json["snippet"] as? String ?? ""
    }
    
    private func parseEmailBody(_ text: String) -> (expense: Expense, bankName: String)? {
        let cleanText = text.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        
        for parser in parsers {
            if let expense = parser.parse(cleanText: cleanText) {
                return (applyAutoCategorization(to: expense), parser.bankName)
            }
        }
        
        return nil
    }
    
    // MARK: - Autocategorización Global
    
    private func applyAutoCategorization(to expense: Expense) -> Expense {
        var autoCategory = "Sin Clasificar"
        let lowerMerchant = expense.merchant.lowercased()
        if lowerMerchant.contains("starbucks") || lowerMerchant.contains("eats") || lowerMerchant.contains("tambo") || lowerMerchant.contains("sharethemeal") {
            autoCategory = "Comida"
        } else if lowerMerchant.contains("uber") || lowerMerchant.contains("lyft") || lowerMerchant.contains("didi") || lowerMerchant.contains("cabify") || lowerMerchant.contains("yango") {
            autoCategory = "Transporte"
        } else if lowerMerchant.contains("netflix") || lowerMerchant.contains("spotify") || lowerMerchant.contains("apple") || lowerMerchant.contains("disney") || lowerMerchant.contains("prime") {
            autoCategory = "Entretenimiento"
        }
        
        let isSub = autoCategory == "Entretenimiento"
        
        expense.category = autoCategory
        expense.isSubscription = isSub
        return expense
    }
    
    private func decodeBase64Url(_ base64Url: String) -> String? {
        var base64 = base64Url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        let length = Double(base64.lengthOfBytes(using: String.Encoding.utf8))
        let requiredLength = 4 * ceil(length / 4.0)
        let paddingLength = requiredLength - length
        if paddingLength > 0 {
            let padding = "".padding(toLength: Int(paddingLength), withPad: "=", startingAt: 0)
            base64 += padding
        }
        
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }
    
    private func decodeQuotedPrintable(_ input: String, encoding: String.Encoding = .isoLatin1) -> String {
        // 1. Remove soft line breaks: "=" followed by "\r\n" or "\n"
        var processed = input.replacingOccurrences(of: "=\\r\\n", with: "", options: .regularExpression)
        processed = processed.replacingOccurrences(of: "=\\n", with: "", options: .regularExpression)
        
        // 2. Convert to bytes and decode =XX
        guard let data = processed.data(using: .ascii) else { return processed }
        
        var outputData = Data()
        outputData.reserveCapacity(data.count)
        
        var i = 0
        let bytes = [UInt8](data)
        
        while i < bytes.count {
            if bytes[i] == 61 { // '=' character
                if i + 2 < bytes.count {
                    let hexStr = String(bytes: [bytes[i+1], bytes[i+2]], encoding: .ascii) ?? ""
                    if let hexByte = UInt8(hexStr, radix: 16) {
                        outputData.append(hexByte)
                        i += 3
                        continue
                    }
                }
            }
            outputData.append(bytes[i])
            i += 1
        }
        
        return String(data: outputData, encoding: encoding) ?? String(data: outputData, encoding: .utf8) ?? processed
    }
}
