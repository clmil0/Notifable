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
        ScotiabankParser(),
        AppleParser()
    ]
    
    // Configura el ModelContext desde el lugar donde se llame
    var modelContext: ModelContext?
    
    init() {
        self.lastSyncDate = UserDefaults.standard.object(forKey: "lastSyncDate") as? Date
    }
    
    // MARK: - Comprobación con la app abierta

    /// Cada cuánto se mira el correo mientras la app está en primer plano.
    static let foregroundPollInterval: TimeInterval = 60

    private var pollTimer: Timer?

    /// Arranca la comprobación de cada minuto. Antes sólo se leía al volver a
    /// primer plano, así que con la app abierta un rato "Última lectura"
    /// envejecía y parecía que había dejado de registrar.
    ///
    /// Cuesta muy poco: cuando no hay correo nuevo es **una** petición
    /// `messages.list` (unos pocos KB, 5 unidades de cuota de Gmail, muy lejos
    /// del límite por usuario). Sólo si aparece un correo sin procesar se
    /// descarga ese mensaje. Se detiene al salir de la app: en segundo plano no
    /// corre nada.
    func startForegroundPolling() {
        stopForegroundPolling()
        let timer = Timer(timeInterval: Self.foregroundPollInterval, repeats: true) { [weak self] _ in
            guard let self, GmailAuthService.shared.isAuthenticated, !self.isSyncing else { return }
            self.syncEmails(quiet: true)
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stopForegroundPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// - Parameter quiet: comprobación periódica. No enciende `isSyncing` (que
    ///   en Gmail y bancos cambia la fila de "Última lectura" por la barra de
    ///   progreso) salvo que de verdad haya correos nuevos que procesar.
    /// Hay una lectura en curso. Sólo se toca en el hilo principal.
    private var isRunning = false
    /// Rango pedido mientras otra lectura corría: se lanza al terminar ésa.
    private var queuedRange: (start: Date?, end: Date?)?

    /// Cierra la lectura en curso y, si alguien pidió un rango mientras
    /// tanto, lo lanza ahora.
    private func finishRun() {
        DispatchQueue.main.async {
            self.isRunning = false
            if let queued = self.queuedRange {
                self.queuedRange = nil
                self.syncEmails(force: true, startDate: queued.start, endDate: queued.end)
            }
        }
    }

    func syncEmails(force: Bool = false, quiet: Bool = false, startDate: Date? = nil, endDate: Date? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.syncEmails(force: force, quiet: quiet, startDate: startDate, endDate: endDate) }
            return
        }
        // Throttling: un poco menos del intervalo del temporizador, para que su
        // propio desfase no le haga saltarse una vuelta.
        if !force, let lastSync = lastSyncDate, Date().timeIntervalSince(lastSync) < Self.foregroundPollInterval - 10 {
            print("Sync throttled. Last sync was \(Int(Date().timeIntervalSince(lastSync)/60)) minutes ago.")
            return
        }

        // Nadie pidió un rango y nunca se ha leído nada: no hay nada que
        // sincronizar. Antes esta rama se inventaba el último mes y descargaba
        // correo por su cuenta apenas se vinculaba Gmail — sin que el usuario
        // hubiera elegido leer su pasado, y a veces antes de que le llegara la
        // pregunta. El pasado sólo se descarga cuando lo pide: en la pantalla
        // de "¿Cuánto correo miramos?" o en Gmail y bancos.
        if startDate == nil, endDate == nil, lastSyncDate == nil {
            print("Sync skipped: sin lectura previa y sin rango elegido por el usuario.")
            return
        }
        
        // Una lectura a la vez. Dos solapadas —tras reinstalar, la del
        // onboarding y la de volver a primer plano o una de rango— importaban
        // cada una su copia de los mismos correos. Un rango pedido a medias no
        // se pierde: se lanza al acabar la actual. Una comprobación normal se
        // descarta, porque la lectura en curso ya la cubre.
        if isRunning {
            if startDate != nil || endDate != nil { queuedRange = (startDate, endDate) }
            Diagnostics.shared.log("Sync Gmail: ya hay una lectura en curso, \(queuedRange != nil ? "se encola el rango" : "se omite")")
            return
        }
        isRunning = true

        Diagnostics.shared.log("Sync Gmail: inicio (force: \(force), rango: \(startDate != nil || endDate != nil))")
        if !quiet {
            DispatchQueue.main.async {
                self.isSyncing = true
                self.lastSyncError = nil
                self.totalEmailsToProcess = 0
                self.emailsProcessed = 0
                self.expensesFoundByBank = [:]
            }
        }
        
        guard let token = GmailAuthService.shared.getAccessToken() else {
            DispatchQueue.main.async {
                self.isSyncing = false
                self.lastSyncError = "No access token"
            }
            finishRun()
            return
        }
        
        fetchMessageList(token: token, startDate: startDate, endDate: endDate) { [weak self] result in
            switch result {
            case .success(let messages):
                self?.processMessages(messages, token: token,
                                      isRangeSync: startDate != nil || endDate != nil,
                                      coversNow: Self.reachesNow(endDate),
                                      quiet: quiet)
            case .failure(let error):
                // Token might be expired, try to refresh
                print("Failed to fetch messages: \(error). Trying to refresh token...")
                GmailAuthService.shared.refreshAccessToken { newToken in
                    if let newToken = newToken {
                        self?.fetchMessageList(token: newToken, startDate: startDate, endDate: endDate) { result in
                            switch result {
                            case .success(let msgs):
                                self?.processMessages(msgs, token: newToken,
                                                      isRangeSync: startDate != nil || endDate != nil,
                                                      coversNow: Self.reachesNow(endDate),
                                                      quiet: quiet)
                            case .failure(let err):
                                DispatchQueue.main.async {
                                    self?.isSyncing = false
                                    self?.lastSyncError = err.localizedDescription
                                }
                                self?.finishRun()
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            self?.isSyncing = false
                            self?.lastSyncError = "Token refresh failed"
                        }
                        self?.finishRun()
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
            // Sin rango y sin lectura previa no se inventa una ventana: ver
            // `syncEmails`, que ya corta antes de llegar aquí.
            completion(.success([]))
            return
        }
        
        if let end = endDate {
            // Set end to the end of the day to include the selected date fully
            let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: end) ?? end
            let endEpoch = Int(endOfDay.timeIntervalSince1970)
            query = "\(query) AND before:\(endEpoch)"
        }
        
        // Siempre con `completion`: un `return` a secas dejaría la lectura
        // "en curso" para siempre y `isRunning` bloquearía todas las demás.
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            completion(.success([]))
            return
        }

        // Gmail pagina: sin seguir `nextPageToken`, un rango largo se cortaba en
        // 500 correos y el resto se perdía en silencio. Cinco meses de dos
        // bancos pasan de 500 sin dificultad.
        fetchMessagePage(token: token, encodedQuery: encodedQuery, pageToken: nil,
                         accumulated: [], completion: completion)
    }

    private func fetchMessagePage(token: String,
                                  encodedQuery: String,
                                  pageToken: String?,
                                  accumulated: [[String: Any]],
                                  completion: @escaping (Result<[[String: Any]], Error>) -> Void) {

        var urlString = "\(baseURL)/messages?q=\(encodedQuery)&maxResults=500"
        if let pageToken { urlString += "&pageToken=\(pageToken)" }
        guard let url = URL(string: urlString) else {
            completion(.success(accumulated))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                completion(.failure(NSError(domain: "Auth", code: 401, userInfo: nil)))
                return
            }
            guard let data = data else {
                completion(.success(accumulated))
                return
            }

            do {
                let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                let messages = json?["messages"] as? [[String: Any]] ?? []
                let total = accumulated + messages

                // Tope de cordura: 20 páginas son 10 000 correos.
                if let next = json?["nextPageToken"] as? String, total.count < 10_000 {
                    self?.fetchMessagePage(token: token, encodedQuery: encodedQuery,
                                           pageToken: next, accumulated: total,
                                           completion: completion)
                } else {
                    completion(.success(total))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    /// `true` si la sincronización llega hasta ahora. Una sincronización
    /// histórica acotada no puede decir "ya está todo al día".
    static func reachesNow(_ endDate: Date?) -> Bool {
        guard let endDate else { return true }
        return Calendar.current.startOfDay(for: endDate) >= Calendar.current.startOfDay(for: Date())
    }

    /// Punto de partida para leer "los últimos N meses", siempre el día 1 de
    /// un mes — nunca una fecha suelta a mitad de mes, que dejaría el primer
    /// tramo del rango incompleto y "1 mes" significaría cosas distintas
    /// según qué día del mes se pidiera.
    ///
    /// El mes de hoy sólo cuenta como uno completo si ya se pasó la quincena
    /// (día > 15); si no, el rango arranca un mes antes. Así, pedir "1 mes"
    /// el 3 o el 15 de agosto trae desde el 1 de julio (agosto apenas
    /// empieza, no es un mes de historial todavía), pero pedirlo el 20 de
    /// agosto ya trae desde el 1 de agosto (agosto ya lleva más de la mitad).
    static func smartRangeStart(months: Int, from reference: Date = Date(), calendar: Calendar = .current) -> Date {
        let day = calendar.component(.day, from: reference)
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: reference)) ?? reference
        let anchor = day <= 15
            ? (calendar.date(byAdding: .month, value: -1, to: currentMonthStart) ?? currentMonthStart)
            : currentMonthStart
        let start = calendar.date(byAdding: .month, value: -(months - 1), to: anchor) ?? anchor
        return calendar.startOfDay(for: start)
    }

    /// Correos que la app ya convirtió en un gasto que sigue en la base.
    ///
    /// La deduplicación no puede depender sólo de `processedEmailIDs`: esa lista
    /// vive en `UserDefaults` y se borra al restablecer la sincronización o al
    /// reinstalar, y entonces el mismo rango se importaba dos veces.
    ///
    /// Incluye `relatedEmailID`: el segundo correo de un par de Apple (recibo +
    /// cargo del banco) no crea gasto, se une al primero. Sin contarlo, cada
    /// lectura por rango lo veía como nuevo y, como el gasto ya estaba unido,
    /// no encontraba con qué unirlo y creaba un duplicado.
    private func existingEmailIDs() -> Set<String> {
        guard let context = modelContext else { return [] }
        let expenses = (try? context.fetch(FetchDescriptor<Expense>())) ?? []
        let incomes = (try? context.fetch(FetchDescriptor<Income>())) ?? []
        return Set(expenses.compactMap { $0.emailID })
            .union(expenses.compactMap { $0.relatedEmailID })
            .union(incomes.compactMap { $0.emailID })
    }

    /// Varios movimientos con el **mismo** `emailID`: copias que dejaron dos
    /// lecturas solapadas antes de que `syncEmails` las serializara (se vio
    /// al reinstalar: el mismo yapeo repetido varias veces). Un correo es un
    /// movimiento, así que se queda uno por correo.
    ///
    /// Se conserva el que tenga más decisiones del usuario encima (abonos,
    /// deuda, categoría) y, de las demás copias, sólo se borran las que no
    /// tienen abonos: borrar una con abonos soltaría esos cobros.
    @discardableResult
    static func removeSameEmailDuplicates(in context: ModelContext) -> Int {
        let expenses = (try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.emailID != nil }))) ?? []
        let groups = Dictionary(grouping: expenses, by: { $0.emailID ?? "" }).filter { $0.value.count > 1 }

        func weight(_ e: Expense) -> Int {
            ((e.payments ?? []).isEmpty ? 0 : 4)
                + (e.isDebt ? 2 : 0)
                + (e.category == Accounting.unclassified ? 0 : 1)
        }

        var removed = 0
        for (_, copies) in groups {
            let keep = copies.max { weight($0) < weight($1) }
            for copy in copies where copy.id != keep?.id && (copy.payments ?? []).isEmpty {
                context.delete(copy)
                removed += 1
            }
        }

        let incomes = (try? context.fetch(FetchDescriptor<Income>(predicate: #Predicate { $0.emailID != nil }))) ?? []
        for (_, copies) in Dictionary(grouping: incomes, by: { $0.emailID ?? "" }) where copies.count > 1 {
            // Uno atado a una deuda gana: es una decisión del usuario.
            let keep = copies.first { $0.debtReference != nil } ?? copies[0]
            for copy in copies where copy.id != keep.id && copy.debtReference == nil {
                context.delete(copy)
                removed += 1
            }
        }

        if removed > 0 {
            try? context.save()
            Diagnostics.shared.log("Copias del mismo correo borradas: \(removed)")
        }
        return removed
    }

    /// Borra los duplicados que dejó el error de arriba: un gasto cuyo correo
    /// ya está unido a otro gasto. Sólo si nadie decidió nada sobre él — ni
    /// deuda, ni cobros, ni ediciones —; si no, se deja y se anota.
    @discardableResult
    static func removeLinkedDuplicates(in context: ModelContext) -> Int {
        removeSameEmailDuplicates(in: context)
        let expenses = (try? context.fetch(FetchDescriptor<Expense>())) ?? []
        let linkedIDs = Set(expenses.compactMap(\.relatedEmailID))
        guard !linkedIDs.isEmpty else { return 0 }
        let edits = ExpenseEditStore.all()

        var removed = 0
        for expense in expenses {
            guard let emailID = expense.emailID, linkedIDs.contains(emailID), expense.relatedEmailID == nil,
                  expenses.contains(where: { $0.id != expense.id && $0.relatedEmailID == emailID }) else { continue }
            guard !expense.isDebt, (expense.payments ?? []).isEmpty,
                  edits[TransactionKey.key(for: expense)] == nil else {
                Diagnostics.shared.log("Duplicado de correo unido conservado (tiene decisiones): \(expense.merchant)")
                continue
            }
            context.delete(expense)
            removed += 1
        }
        if removed > 0 {
            try? context.save()
            Diagnostics.shared.log("Duplicados de correos unidos borrados: \(removed)")
        }
        return removed
    }

    /// `existingEmailIDs()` en el hilo principal, se llame desde donde se llame.
    ///
    /// **Corrección de un cuelgue permanente:** aquí había un
    /// `DispatchQueue.main.sync` a secas. `processMessages` llega desde el
    /// callback de `URLSession` (un hilo de fondo) y ahí funcionaba, pero
    /// `recoverExpenses` se invoca desde el botón "Sí, recuperar" de la alerta
    /// de Recuperación de Gastos —o sea, **ya en el hilo principal**—, y
    /// `main.sync` desde el propio hilo principal es un interbloqueo inmediato
    /// y definitivo: la app se quedaba congelada, sin crash y sin registro.
    /// Estando ya en main no hace falta ningún salto; el `sync` se reserva para
    /// cuando de verdad se viene de otro hilo.
    private func knownEmailIDsFromMain() -> Set<String> {
        if Thread.isMainThread { return existingEmailIDs() }
        return DispatchQueue.main.sync { self.existingEmailIDs() }
    }

    private func processMessages(_ messages: [[String: Any]],
                                 token: String,
                                 isRangeSync: Bool = false,
                                 coversNow: Bool = true,
                                 quiet: Bool = false) {
        let processedIDs = UserDefaults.standard.stringArray(forKey: "processedEmailIDs") ?? []
        // Borrados a propósito: no se resucitan solos. Para recuperarlos está
        // "Recuperación de Gastos" en Ajustes.
        let deletedIDs = Set(UserDefaults.standard.stringArray(forKey: "pendingRecoveryIDs") ?? [])

        let newMessages = messages.filter { msg in
            guard let id = msg["id"] as? String else { return false }
            if deletedIDs.contains(id) { return false }
            // En una sincronización con rango explícito no se salta lo ya
            // procesado: se vuelve a mirar para rellenar lo que falte —un correo
            // que falló, un parser arreglado después—, y la comprobación contra
            // la base impide duplicar.
            return isRangeSync || !processedIDs.contains(id)
        }
        
        // Sin nada nuevo la comprobación no se ve ni toca los contadores (el
        // onboarding los lee para dar por terminada su lectura); con correos
        // que procesar se enseña el progreso, como una lectura normal.
        if !(quiet && newMessages.isEmpty) { DispatchQueue.main.async {
            if quiet {
                self.isSyncing = true
                self.lastSyncError = nil
            }
            self.totalEmailsToProcess = newMessages.count
            self.emailsProcessed = 0
            self.expensesFoundByBank = [:]
            for parser in self.parsers {
                self.expensesFoundByBank[parser.bankName] = 0
            }
        } }
        
        Diagnostics.shared.log("Sync Gmail: \(newMessages.count) correos por procesar de \(messages.count)")
        var newIDs = processedIDs
        let queue = DispatchQueue(label: "com.notifable.syncQueue") // Para evitar race conditions
        
        let group = DispatchGroup()
        var newExpensesFound = 0
        let semaphore = DispatchSemaphore(value: 5) // Maximum 5 concurrent requests

        // Se siembra con lo que ya está en la base y se va ampliando: dos
        // correos de la misma tanda no pueden crear el mismo gasto dos veces.
        var knownIDs: Set<String> = knownEmailIDsFromMain()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for message in newMessages {
                guard let id = message["id"] as? String else { continue }
                
                semaphore.wait()
                group.enter()
                self?.fetchMessageDetails(id: id, token: token) { body, receivedAt in
                    defer {
                        semaphore.signal()
                        group.leave()
                    }
                    
                    var foundBankName: String? = nil
                    
                    if let body = body {
                        let alreadyImported = queue.sync { knownIDs.contains(id) }

                        if !alreadyImported, let parsed = self?.parseEmailBody(body, receivedAt: receivedAt) {
                            foundBankName = parsed.bankName
                            DispatchQueue.main.sync {
                                if let context = self?.modelContext {
                                    var inserted = false
                                    if let expense = parsed.expense {
                                        inserted = self?.handleExpenseInsertion(expenseData: (expense, parsed.bankName), emailID: id, context: context) == true
                                    } else if let income = parsed.income {
                                        inserted = self?.handleIncomeInsertion(income: income, emailID: id, context: context) == true
                                    }
                                    if inserted {
                                        newExpensesFound += 1
                                    }
                                }
                            }
                            queue.sync { _ = knownIDs.insert(id) }
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
                // Una sincronización histórica acotada no marca "al día": si lo
                // hiciera, la automática miraría sólo desde hace una hora y el
                // tramo entre esa fecha final y hoy no se descargaría nunca.
                if coversNow {
                    self?.lastSyncDate = Date()
                }
                self?.isSyncing = false
                // Los gastos acaban de rearmarse desde el correo, así que ahora
                // sí existen los que estaban esperando su marca de deuda o su
                // categoría restaurada. Ver ConfigBackupManager.
                if let context = self?.modelContext {
                    Self.removeLinkedDuplicates(in: context)
                    ConfigBackupManager.reapplyPendingDecisions(modelContext: context)
                }
                print("Sync complete. Found \(newExpensesFound) new expenses of \(newMessages.count) checked.")
                Diagnostics.shared.log("Sync Gmail: fin, \(newExpensesFound) nuevos")
                self?.finishRun()
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

        // Recuperar dos veces tampoco puede duplicar.
        var knownIDs: Set<String> = knownEmailIDsFromMain()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for id in ids {
                semaphore.wait()
                group.enter()
                self?.fetchMessageDetails(id: id, token: token) { body, receivedAt in
                    defer {
                        semaphore.signal()
                        group.leave()
                    }
                    
                    var foundBankName: String? = nil
                    if let body = body {
                        let alreadyImported = queue.sync { knownIDs.contains(id) }

                        if !alreadyImported, let parsed = self?.parseEmailBody(body, receivedAt: receivedAt) {
                            foundBankName = parsed.bankName
                            DispatchQueue.main.sync {
                                if let context = self?.modelContext {
                                    var inserted = false
                                    if let expense = parsed.expense {
                                        inserted = self?.handleExpenseInsertion(expenseData: (expense, parsed.bankName), emailID: id, context: context) == true
                                    } else if let income = parsed.income {
                                        inserted = self?.handleIncomeInsertion(income: income, emailID: id, context: context) == true
                                    }
                                    if inserted {
                                        newExpensesFound += 1
                                    }
                                }
                            }
                            queue.sync { _ = knownIDs.insert(id) }
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
                if let context = self?.modelContext {
                    Self.removeLinkedDuplicates(in: context)
                    ConfigBackupManager.reapplyPendingDecisions(modelContext: context)
                }
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
    
    func diagnosticBBVATransfer() {
        guard let token = GmailAuthService.shared.getAccessToken() else {
            DispatchQueue.main.async { self.diagnosticResult = "No token"; self.showDiagnostic = true }
            return
        }
        DispatchQueue.main.async { self.diagnosticResult = "Buscando..."; self.showDiagnostic = true }
        
        let query = "from:procesos@bbva.com.pe terceros"
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
                    DispatchQueue.main.async { self.diagnosticResult = "No se encontraron transferencias BBVA. \n\n\(raw)" }
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
                    let parser = YapeParser() // Por defecto
                    let appleParser = AppleParser()
                    let bbvaParser = BBVAParser()
                    
                    var result: Expense? = nil
                    var parserUsed = ""
                    
                    if let appleRes = appleParser.parse(cleanText: bodyText) {
                        result = appleRes
                        parserUsed = "AppleParser"
                    } else if let bbvaRes = bbvaParser.parse(cleanText: bodyText) {
                        result = bbvaRes
                        parserUsed = "BBVAParser"
                    } else if let yapeRes = parser.parse(cleanText: bodyText) {
                        result = yapeRes
                        parserUsed = "YapeParser"
                    }
                    
                    // Fecha en dos formatos: ISO con offset (para no dejar dudas
                    // de zona horaria) y como la vería el usuario en la app — así el
                    // diagnóstico permite comparar directo contra "Fecha y hora de la
                    // operación" del correo sin adivinar.
                    var fechaDebug = "NIL"
                    if let parsedDate = result?.date {
                        let iso = ISO8601DateFormatter()
                        iso.timeZone = TimeZone.current
                        iso.formatOptions = [.withInternetDateTime]
                        let display = DateFormatter()
                        display.locale = Locale(identifier: "es_PE")
                        display.dateFormat = "EEEE d 'de' MMMM, yyyy HH:mm"
                        fechaDebug = "\(display.string(from: parsedDate))  (\(iso.string(from: parsedDate)))"
                        if abs(parsedDate.timeIntervalSinceNow) < 5 {
                            fechaDebug += "  ⚠️ igual a \"ahora\": el patrón de fecha del parser no matcheó y quedó el valor por defecto"
                        }
                    }

                    let finalStr = """
                    --- RAW JSON ---
                    Snippet: \(json["snippet"] as? String ?? "")
                    
                    --- TEXTO EXTRAÍDO ---
                    \(bodyText)
                    
                    --- RESULTADO \(parserUsed) ---
                    Monto: \(result != nil ? String(result!.amount) : "NIL")
                    Merchant: \(result != nil ? result!.merchant : "NIL")
                    Fecha: \(fechaDebug)
                    """
                    DispatchQueue.main.async { self.diagnosticResult = finalStr }
                }
            } catch {}
        }.resume()
    }
    
    func diagnosticApple() {
        guard let token = GmailAuthService.shared.getAccessToken() else {
            DispatchQueue.main.async { self.diagnosticResult = "No token"; self.showDiagnostic = true }
            return
        }
        DispatchQueue.main.async { self.diagnosticResult = "Buscando..."; self.showDiagnostic = true }
        
        let query = "from:no_reply@email.apple.com Factura"
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
                    DispatchQueue.main.async { self.diagnosticResult = "No se encontraron recibos de Apple. \n\n\(raw)" }
                }
            } catch {}
        }.resume()
    }
    
    /// Devuelve el texto del correo y cuándo lo recibió Gmail (`internalDate`,
    /// en milisegundos). Esa fecha es el respaldo cuando el parser no logra
    /// leer la del movimiento: ver `parseEmailBody`.
    private func fetchMessageDetails(id: String, token: String, completion: @escaping (String?, Date?) -> Void) {
        guard let url = URL(string: "\(baseURL)/messages/\(id)?format=full") else {
            completion(nil, nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(nil, nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    let bodyText = self.extractFullText(from: json)
                    
                    // DEBUG: Guardar el texto si es de BBVA
                    if bodyText.lowercased().contains("pago autom") {
                        try? bodyText.write(to: URL(fileURLWithPath: "/Users/josephmt/Downloads/bbva_body.txt"), atomically: true, encoding: .utf8)
                    }
                    
                    let receivedAt = (json["internalDate"] as? String)
                        .flatMap(Double.init)
                        .map { Date(timeIntervalSince1970: $0 / 1000) }
                    completion(bodyText, receivedAt)
                } else {
                    completion(nil, nil)
                }
            } catch {
                completion(nil, nil)
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
    
    /// Tolerancia para decidir que la fecha que dio el parser es imposible.
    /// Holgada a propósito: el parser interpreta la hora del correo en la zona
    /// del teléfono, que puede estar varias horas por delante de la de Perú.
    static let impossibleDateSlack: TimeInterval = 12 * 3600

    /// Un movimiento no puede ser posterior al correo que lo avisa. Si lo es,
    /// el parser no encontró la fecha y cayó en su respaldo `Date()`: al
    /// reinstalar y releer meses de correo, todos esos gastos acababan con la
    /// hora de la reinstalación, amontonados en el mes actual. La fecha en que
    /// Gmail recibió el correo es una aproximación mucho mejor.
    static func correctedDate(_ parsed: Date, receivedAt: Date?) -> Date {
        guard let receivedAt, parsed.timeIntervalSince(receivedAt) > impossibleDateSlack else { return parsed }
        return receivedAt
    }

    private func parseEmailBody(_ text: String, receivedAt: Date?) -> (expense: Expense?, income: Income?, bankName: String)? {
        let cleanText = text.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")

        for parser in parsers {
            if let expense = parser.parse(cleanText: cleanText) {
                let fixed = Self.correctedDate(expense.date, receivedAt: receivedAt)
                if fixed != expense.date {
                    Diagnostics.shared.log("Sync Gmail: \(parser.bankName) sin fecha legible, se usa la del correo")
                    expense.date = fixed
                }
                return (applyAutoCategorization(to: expense), nil, parser.bankName)
            }
        }

        // Un correo no puede ser gasto e ingreso a la vez: sólo se prueba
        // parseIncome cuando ningún parser lo reconoció como gasto.
        for parser in parsers {
            if let income = parser.parseIncome(cleanText: cleanText) {
                income.date = Self.correctedDate(income.date, receivedAt: receivedAt)
                return (nil, income, parser.bankName)
            }
        }

        return nil
    }
    
    // MARK: - Autocategorización Global
    
    private func applyAutoCategorization(to expense: Expense) -> Expense {
        // Una regla que el usuario ya definió en la Bandeja manda sobre todo lo
        // demás: para eso la definió. Antes sólo se reetiquetaban los gastos que
        // ya estaban en la base y el siguiente correo del mismo comercio volvía
        // a caer sin clasificar.
        if let rule = MerchantRules.category(for: expense.merchant) {
            expense.category = rule
            expense.isSubscription = rule == "Entretenimiento"
            return expense
        }

        var autoCategory = Accounting.unclassified
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
    
    /// ¿Ya existe un movimiento de este correo? Se pregunta a la base justo
    /// antes de insertar, en el hilo principal, que es donde se inserta.
    ///
    /// `knownIDs` sólo es una foto tomada al empezar cada lectura: dos lecturas
    /// que se solapan (la del onboarding y una de rango, por ejemplo) no ven lo
    /// que inserta la otra, y cada una creaba su copia del mismo correo. Antes
    /// esta comprobación sólo existía en el camino de Apple.
    static func isAlreadyImported(emailID: String, context: ModelContext) -> Bool {
        let expenses = FetchDescriptor<Expense>(predicate: #Predicate {
            $0.emailID == emailID || $0.relatedEmailID == emailID
        })
        let incomes = FetchDescriptor<Income>(predicate: #Predicate { $0.emailID == emailID })
        return ((try? context.fetchCount(expenses)) ?? 0) > 0
            || ((try? context.fetchCount(incomes)) ?? 0) > 0
    }

    private func handleExpenseInsertion(expenseData: (expense: Expense, bankName: String), emailID: String, context: ModelContext) -> Bool {
        let newExpense = expenseData.expense
        if Self.isAlreadyImported(emailID: emailID, context: context) { return false }
        
        let isAppleReceipt = expenseData.bankName == "Apple"
        let isAppleBankBill = !isAppleReceipt && newExpense.merchant.lowercased().contains("apple")
        
        if isAppleReceipt || isAppleBankBill {
            let amount = newExpense.amount
            let date = newExpense.date
            
            let allExpenses = (try? context.fetch(FetchDescriptor<Expense>())) ?? []

            // Este correo ya está en un gasto, propio o unido: no hay nada que
            // crear. Segunda red por si llega aquí sin pasar por `knownIDs`.
            if allExpenses.contains(where: { $0.emailID == emailID || $0.relatedEmailID == emailID }) {
                return false
            }

            if let match = allExpenses.first(where: {
                $0.id != newExpense.id &&
                $0.relatedEmailID == nil &&
                $0.amount == amount &&
                abs($0.date.timeIntervalSince(date)) <= 48 * 3600 &&
                ($0.merchant.lowercased().contains("apple") || $0.merchant == "Apple")
            }) {
                if isAppleReceipt {
                    // Overwrite match (Bank Expense) with Apple Receipt details
                    match.merchant = newExpense.merchant == "Apple" ? match.merchant : "Apple: \(newExpense.merchant)"
                    if let notes = newExpense.notes { match.notes = notes }
                    match.isSubscription = newExpense.isSubscription
                    match.category = newExpense.category
                    match.relatedEmailID = emailID
                } else {
                    // Llega el cargo del banco, pero el recibo de Apple ya
                    // había creado el gasto (llegó primero). La factura de
                    // Apple sólo trae el día — sin hora, queda en 00:00 — así
                    // que la hora real hay que tomarla del correo del banco,
                    // que sí la tiene.
                    match.date = date
                    if let card = newExpense.cardLastDigits { match.cardLastDigits = card }
                    match.relatedEmailID = emailID
                }
                try? context.save()
                return true
            }
        }
        
        if isAppleReceipt {
            // No se encontró el cargo del banco todavía para vincularlo (puede
            // llegar después, o nunca si el usuario no sincroniza ese correo).
            // Si no le ponemos ya el prefijo "Apple:", este gasto se guarda con
            // el nombre de la app/plan ("Claude by Anthropic...") sin la
            // palabra "apple" en ningún lado — y cuando el cargo del banco
            // llegue después, la búsqueda por merchant.contains("apple") no lo
            // va a encontrar y el gasto se duplica. Poniéndolo desde ya, la
            // vinculación funciona sin importar en qué orden lleguen los correos.
            newExpense.merchant = newExpense.merchant == "Apple" ? newExpense.merchant : "Apple: \(newExpense.merchant)"
        }
        
        newExpense.emailID = emailID
        context.insert(newExpense)
        try? context.save()
        return true
    }

    /// Constancias de dinero recibido (ej. un Yapeo entrante): a diferencia de
    /// los gastos, no hay vínculo con Apple ni deduplicación especial que
    /// resolver — el `emailID` ya evita procesarlo dos veces.
    private func handleIncomeInsertion(income: Income, emailID: String, context: ModelContext) -> Bool {
        if Self.isAlreadyImported(emailID: emailID, context: context) { return false }
        income.emailID = emailID
        context.insert(income)
        try? context.save()
        return true
    }
}
