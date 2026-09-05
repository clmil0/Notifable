import Foundation
import SwiftData
import UIKit
import CryptoKit

/// Sincronización de todo lo que se pierde al formatear el celular y **no** se
/// puede rearmar releyendo el correo.
///
/// Qué sube
/// - Configuración: reglas de comercio, catálogo de categorías (con sus
///   renombrados), límites por categoría, presupuesto, bancos activos,
///   notificaciones, apariencia, atajos rápidos y gastos recurrentes.
/// - Decisiones sobre movimientos que el correo no contiene: marcas de deuda y
///   categorías puestas a mano a un gasto suelto. Viajan con una huella
///   (`TransactionKey`) que sobrevive a que el gasto se borre y se vuelva a
///   crear al releer Gmail.
/// - Movimientos creados a mano (sin correo detrás), incluidos los abonos a
///   deudas: si no se suben, no hay de dónde recuperarlos.
///
/// Qué NO sube: los gastos e ingresos que vienen del correo. Se reconstruyen
/// solos, y subirlos sería mandar el detalle financiero completo a un servidor
/// sin necesidad.
///
/// Identidad, en orden de preferencia
/// 1. `.account` — la cuenta de Google que el usuario ya usa para leer su
///    correo (`BackupAccount`). No tiene que guardar nada.
/// 2. `.code` — para quien no quiere iniciar sesión: un código que sí debe
///    guardar por su cuenta, porque es la única llave.
@MainActor
@Observable
final class ConfigBackupManager {

    static let shared = ConfigBackupManager()

    enum Mode: String {
        case off, account, code
    }

    private let projectURL = "https://zjzzqaeusmxmtszgdncl.supabase.co"
    private let apiKey = "sb_publishable_NVM2GcvxZFmf0VLNbaBr7A_y_8EMS97"

    private enum Keys {
        static let mode = "configBackupMode"
        static let backupCode = "configBackupCode"
        static let lastSyncedAt = "configBackupLastSyncedAt"
        static let fingerprint = "configBackupFingerprint"
        static let pausedMode = "configBackupPausedMode"
        static let pausedCode = "configBackupPausedCode"
        static let offerDismissed = "configBackupOfferDismissed"
    }

    // MARK: - Estado observable

    private(set) var mode: Mode = .off
    private(set) var backupCode: String?
    private(set) var lastSyncedAt: Date?
    private(set) var isSyncing = false
    private(set) var hasPendingChanges = false

    /// Respaldo encontrado para la cuenta recién conectada, en un teléfono que
    /// todavía no sincroniza. Lo enseña `BackupFoundView`.
    var foundBackup: BackupHeader?

    /// Se pausó sola tras un "Empezar de cero": ver `pauseAfterLocalWipe()`.
    var isPausedAfterWipe: Bool { UserDefaults.standard.string(forKey: Keys.pausedCode) != nil }
    var lastErrorMessage: String?

    var isEnabled: Bool { mode != .off }
    var accountEmail: String? { BackupAccount.shared.email ?? GmailAuthService.shared.accountEmail }

    /// `true` si activar la sincronización no le va a pedir nada al usuario.
    var canUseAccount: Bool { BackupAccount.shared.isSignedIn || BackupAccount.shared.canSignInSilently }

    // MARK: - Infraestructura

    private var container: ModelContainer?
    private var debounce: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private init() {
        let d = UserDefaults.standard
        mode = Mode(rawValue: d.string(forKey: Keys.mode) ?? "") ?? .off
        backupCode = d.string(forKey: Keys.backupCode)
        lastSyncedAt = d.object(forKey: Keys.lastSyncedAt) as? Date
        // Un código guardado sin modo viene de la versión anterior del respaldo.
        if mode == .off, backupCode != nil { mode = .code; persistMode() }
    }

    /// Se llama una vez desde `NotifableApp`. A partir de aquí la clase se
    /// sincroniza sola: no hace falta que ninguna vista le avise de nada.
    func configure(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container
        startWatching()
        Task {
            // Reaplicar ediciones y vínculos toca modelos de SwiftData y guarda.
            // Hacerlo síncrono aquí era hacerlo **mientras SwiftUI monta la
            // vista** —`configure` se llama desde el `.task` del arranque— y eso
            // dispara "modificar estado durante una actualización de vista".
            // Un `yield` deja que el primer dibujado termine antes.
            await Task.yield()
            Self.reapplyPendingDecisions(modelContext: container.mainContext)
            _ = await syncIfNeeded()
            await checkForExistingBackup()
        }
    }

    /// Celular nuevo: el usuario acaba de conectar su correo y esa cuenta ya
    /// tiene un respaldo. Preguntar una vez es la diferencia entre recuperar la
    /// configuración y volver a armarla a mano; insistir sería acoso, así que
    /// "Ahora no" se recuerda.
    func checkForExistingBackup() async {
        // El onboarding es un `fullScreenCover` y sólo puede haber uno: si
        // ofreciéramos restaurar mientras está encima, la oferta no se vería y
        // se daría por descartada.
        guard UserDefaults.standard.bool(forKey: "hasSeenOnboarding") else { return }
        guard !isEnabled, !isPausedAfterWipe else { return }
        guard !UserDefaults.standard.bool(forKey: Keys.offerDismissed) else { return }
        guard BackupAccount.shared.canSignInSilently || BackupAccount.shared.isSignedIn else { return }
        if !BackupAccount.shared.isSignedIn, await BackupAccount.shared.signInWithGoogle() != nil { return }

        let header = await peek(code: nil)
        // "Esta cuenta todavía no tiene respaldo" es la respuesta normal de un
        // usuario nuevo: no es un error que valga la pena enseñar.
        lastErrorMessage = nil
        guard let header, header.hasData else { return }
        foundBackup = header
    }

    /// "Ahora no": no se vuelve a preguntar sola. La pantalla de Sincronización
    /// sigue ahí para quien cambie de opinión.
    func dismissBackupOffer() {
        foundBackup = nil
        UserDefaults.standard.set(true, forKey: Keys.offerDismissed)
    }

    /// "Restaurar" desde la pantalla de celular nuevo.
    @discardableResult
    func acceptFoundBackup() async -> String? {
        foundBackup = nil
        UserDefaults.standard.set(true, forKey: Keys.offerDismissed)
        return await restore(code: nil)
    }

    // MARK: - Disparadores automáticos

    /// Tres señales, una sola política: marcar sucio y dejar que el rebote
    /// decida. Cualquier ajuste vive en `UserDefaults` y cualquier movimiento,
    /// atajo o recurrente en SwiftData, así que estas dos notificaciones cubren
    /// todo lo que se respalda sin tener que tocar cada pantalla que guarda.
    private func startWatching() {
        let center = NotificationCenter.default

        // `Task { @MainActor in … }` y NO `MainActor.assumeIsolated`: cuando
        // NotificationCenter entrega el bloque en `OperationQueue.main`, corre
        // en el hilo principal pero **fuera del ejecutor del MainActor**, así
        // que `assumeIsolated` no cumple su comprobación y aborta el proceso.
        // Estar en el hilo principal y estar en el actor principal no son lo
        // mismo. El salto asíncrono es la forma segura de entrar al actor.
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification,
                                            object: UserDefaults.standard, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.markDirty()
            }
        })

        observers.append(center.addObserver(forName: ModelContext.didSave,
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.markDirty()
            }
        })

        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.flushInBackground()
            }
        })

        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.syncOnForeground()
            }
        })
    }

    /// Un método aparte y no un `Task` dentro del cierre: `assumeIsolated` es
    /// genérico sobre lo que devuelve el bloque, y devolver un `Task` desde ahí
    /// deja su inicializador ambiguo. Los otros tres observadores llaman a un
    /// método igual que éste; conviene que este también lo haga.
    private func syncOnForeground() {
        Task {
            _ = await self.syncIfNeeded()
        }
    }

    /// Algo cambió. No sube nada todavía: espera 3 s por si vienen más cambios
    /// (editar un límite dispara varios guardados seguidos) y compara la huella
    /// antes de mandar nada, así que un cambio que no afecta al respaldo —o el
    /// propio `lastSyncedAt` que escribimos nosotros— no gasta una escritura.
    func markDirty() {
        guard isEnabled, !isSyncing else { return }
        hasPendingChanges = true
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            _ = await self?.syncIfNeeded()
        }
    }

    /// La app se va a segundo plano: sube ya, sin esperar el rebote, pidiendo
    /// al sistema los segundos que hagan falta para terminar.
    private func flushInBackground() {
        guard isEnabled, hasPendingChanges else { return }
        debounce?.cancel()
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "ConfigBackupSync", expirationHandler: nil)
        Task { [weak self] in
            _ = await self?.syncIfNeeded()
            if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) }
        }
    }

    // MARK: - Activar

    /// El camino bueno: la cuenta de Google que ya se usa para el correo.
    /// Devuelve `nil` si salió bien, o el motivo si no.
    @discardableResult
    func enableWithAccount() async -> String? {
        // No basta con `isSignedIn`: una sesión guardada cuyo refresh_token ya
        // no sirve pasaría ese filtro y la llamada saldría como anónima, que en
        // PostgREST se ve como un 404 desconcertante. Se exige un token vivo.
        if await BackupAccount.shared.validAccessToken() == nil {
            if let error = await BackupAccount.shared.signInWithGoogle() {
                lastErrorMessage = error
                return error
            }
            if await BackupAccount.shared.validAccessToken() == nil {
                let error = "No se pudo iniciar sesión con Google."
                lastErrorMessage = error
                return error
            }
        }

        // Si ya venía usando un código suelto, la cuenta lo adopta en vez de
        // empezar un respaldo vacío: no se pierde lo subido hasta ahora.
        var body: [String: Any] = [:]
        if let backupCode, mode == .code { body["p_adopt_code"] = backupCode }
        body["p_device_label"] = UIDevice.current.name
        body["p_app_version"] = Self.appVersion ?? NSNull()
        if let email = BackupAccount.shared.email { body["p_account_email"] = email }

        guard let data = await call("ensure_my_backup", body: body, prefix: "No se pudo activar la sincronización") else {
            return lastErrorMessage
        }
        guard let code = Self.decodeScalarString(data) else {
            lastErrorMessage = "Respuesta inesperada al activar la sincronización."
            return lastErrorMessage
        }

        backupCode = code
        mode = .account
        persistMode()
        _ = await sync(force: true)
        return nil
    }

    /// Para quien no quiere iniciar sesión. Devuelve el código, que el usuario
    /// tiene que guardar: es la única llave de ese respaldo.
    @discardableResult
    func enableWithCode() async -> String? {
        if let backupCode, mode != .off { return backupCode }
        guard let data = await call("generate_backup_code", body: [:], prefix: "No se pudo activar la sincronización"),
              let code = Self.decodeScalarString(data) else { return nil }

        backupCode = code
        mode = .code
        persistMode()
        _ = await sync(force: true)
        return code
    }

    /// Apaga la sincronización. `deleteRemote` borra además lo ya subido.
    func disable(deleteRemote: Bool) async {
        if deleteRemote {
            _ = await call("delete_config_backup", body: codeBody(), prefix: "No se pudo borrar el respaldo")
        }
        debounce?.cancel()
        mode = .off
        backupCode = nil
        lastSyncedAt = nil
        hasPendingChanges = false
        UserDefaults.standard.removeObject(forKey: Keys.fingerprint)
        persistMode()
    }

    // MARK: - Empezar de cero

    /// "Borrar datos → Empezar de cero" deja el teléfono vacío. Si la
    /// sincronización siguiera encendida, el siguiente rebote subiría ese vacío
    /// y se llevaría por delante la copia en la nube — justo lo contrario de
    /// para lo que existe. Así que se pausa y se guarda a un lado a qué
    /// respaldo apuntaba, para poder reanudarla con un toque.
    func pauseAfterLocalWipe() {
        guard isEnabled else { return }
        debounce?.cancel()
        let d = UserDefaults.standard
        d.set(mode.rawValue, forKey: Keys.pausedMode)
        d.set(backupCode, forKey: Keys.pausedCode)
        mode = .off
        backupCode = nil
        hasPendingChanges = false
        d.removeObject(forKey: Keys.fingerprint)
        persistMode()
    }

    /// Reanuda lo pausado. `restoreFirst` trae la copia de la nube a este
    /// teléfono; sin él, se sube lo que hay ahora y la copia anterior se
    /// reemplaza.
    @discardableResult
    func resumeAfterWipe(restoreFirst: Bool) async -> String? {
        let d = UserDefaults.standard
        guard let code = d.string(forKey: Keys.pausedCode) else { return "No hay nada pausado." }
        let pausedMode = Mode(rawValue: d.string(forKey: Keys.pausedMode) ?? "") ?? .code

        if restoreFirst {
            if let error = await restore(code: pausedMode == .code ? code : nil) { return error }
        } else {
            backupCode = code
            mode = pausedMode
            persistMode()
            _ = await sync(force: true)
        }
        d.removeObject(forKey: Keys.pausedCode)
        d.removeObject(forKey: Keys.pausedMode)
        return lastErrorMessage
    }

    // MARK: - Sincronizar

    /// Sube sólo si de verdad cambió algo respecto a lo último subido.
    @discardableResult
    func syncIfNeeded() async -> Bool {
        await sync(force: false)
    }

    /// El botón "Sincronizar ahora": sube aunque la huella no haya cambiado.
    @discardableResult
    func syncNow() async -> Bool {
        await sync(force: true)
    }

    @discardableResult
    private func sync(force: Bool) async -> Bool {
        guard isEnabled, backupCode != nil, !isSyncing else { return false }
        guard let snapshot = buildSnapshot() else { return false }

        let fingerprint = Self.fingerprint(of: snapshot)
        if !force, fingerprint == UserDefaults.standard.string(forKey: Keys.fingerprint) {
            hasPendingChanges = false
            lastErrorMessage = nil
            return true
        }

        isSyncing = true
        defer { isSyncing = false }

        var body = snapshot.rpcBody
        body.merge(codeBody()) { current, _ in current }
        body["p_app_version"] = Self.appVersion ?? NSNull()
        body["p_device_label"] = UIDevice.current.name

        guard await call("write_config_backup", body: body, prefix: "No se pudo sincronizar") != nil else {
            return false
        }

        UserDefaults.standard.set(fingerprint, forKey: Keys.fingerprint)
        lastSyncedAt = Date()
        UserDefaults.standard.set(lastSyncedAt, forKey: Keys.lastSyncedAt)
        hasPendingChanges = false
        lastErrorMessage = nil
        return true
    }

    // MARK: - Restaurar

    /// Trae el respaldo y lo aplica entero. `code == nil` usa la cuenta.
    /// Devuelve `nil` si salió bien, o el motivo del fallo.
    @discardableResult
    func restore(code: String?) async -> String? {
        var body: [String: Any] = [:]
        if let code, !code.isEmpty {
            body["p_code"] = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        } else if await BackupAccount.shared.validAccessToken() == nil {
            if let error = await BackupAccount.shared.signInWithGoogle() {
                lastErrorMessage = error
                return error
            }
            if await BackupAccount.shared.validAccessToken() == nil {
                let error = "No se pudo iniciar sesión con Google."
                lastErrorMessage = error
                return error
            }
        }

        guard let data = await call("read_config_backup", body: body, prefix: "No se pudo leer el respaldo") else {
            return lastErrorMessage
        }

        let payload: ConfigBackupPayload
        do {
            payload = try Self.makeDecoder().decode(ConfigBackupPayload.self, from: data)
        } catch {
            lastErrorMessage = "El respaldo llegó en un formato que esta versión no entiende: \(error)"
            return lastErrorMessage
        }

        apply(payload)

        backupCode = payload.backupCode ?? body["p_code"] as? String ?? backupCode
        mode = (body["p_code"] == nil) ? .account : .code
        persistMode()
        lastSyncedAt = Date()
        UserDefaults.standard.set(lastSyncedAt, forKey: Keys.lastSyncedAt)
        // La huella se recalcula sola en la próxima señal; no se fija aquí para
        // que cualquier diferencia local se suba enseguida.
        UserDefaults.standard.removeObject(forKey: Keys.fingerprint)
        lastErrorMessage = nil
        return nil
    }

    /// Sólo la cabecera: para poder decir "hay un respaldo del 3 de marzo"
    /// antes de sobrescribir nada.
    func peek(code: String?) async -> BackupHeader? {
        var body: [String: Any] = [:]
        if let code, !code.isEmpty {
            body["p_code"] = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        guard let data = await call("peek_config_backup", body: body, prefix: "No se pudo leer el respaldo") else {
            return nil
        }
        return try? Self.makeDecoder().decode(BackupHeader.self, from: data)
    }

    // MARK: - Red

    private func codeBody() -> [String: Any] {
        // Con cuenta no se manda el código: el servidor resuelve por `auth.uid()`,
        // así el respaldo sigue siendo suyo aunque el código se filtre.
        guard mode == .code, let backupCode else { return [:] }
        return ["p_code": backupCode]
    }

    @discardableResult
    private func call(_ function: String, body: [String: Any], prefix: String) async -> Data? {
        guard let url = URL(string: "\(projectURL)/rest/v1/rpc/\(function)") else {
            lastErrorMessage = "\(prefix): URL inválida."
            return nil
        }
        // El error anterior se borra al empezar el intento, no al terminarlo:
        // si no, la pantalla sigue mostrando en rojo un fallo de hace tres
        // intentos y parece que nada de lo que haces sirve.
        lastErrorMessage = nil

        // Se pregunta antes de mandar: un 404 significa cosas muy distintas
        // según se llame con sesión o como anónimo.
        let signedIn = await BackupAccount.shared.validAccessToken() != nil
        var request = await BackupAccount.shared.authorizedRequest(url: url)
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(status) else {
                lastErrorMessage = Self.describe(prefix, function: function,
                                                 status: status, data: data, signedIn: signedIn)
                return nil
            }
            return data
        } catch {
            lastErrorMessage = "\(prefix): \(error.localizedDescription)"
            return nil
        }
    }

    /// El motivo real, no un "no se pudo" genérico: sin esto es imposible
    /// distinguir "falta correr el SQL" de "el código no existe".
    private static func describe(_ prefix: String, function: String, status: Int,
                                data: Data, signedIn: Bool) -> String {
        var body = String(data: data, encoding: .utf8) ?? ""
        if body.count > 240 { body = String(body.prefix(240)) + "…" }
        if status == 404 {
            // PostgREST manda en `details` los parámetros con los que buscó y en
            // `hint` la firma que sí existe: sin eso, un 404 puede ser caché,
            // permisos o un nombre de parámetro que no coincide, y no hay forma
            // de distinguirlos desde el teléfono.
            let detail = Self.field("details", in: data) ?? ""
            let hint = Self.field("hint", in: data) ?? ""
            var text = "\(prefix): Supabase no encuentra «\(function)»"
            text += signedIn ? " (con sesión iniciada)." : " (la app llamó sin sesión)."
            if !detail.isEmpty { text += "\n\nBuscó: \(detail)" }
            if !hint.isEmpty { text += "\n\nPista: \(hint)" }
            if detail.isEmpty, hint.isEmpty { text += "\n\n\(body)" }
            return text
        }
        if status == 401 || status == 403 {
            return "\(prefix): la sesión no vale. Vuelve a conectar tu cuenta de Google."
        }
        return body.isEmpty ? "\(prefix) (HTTP \(status))." : "\(prefix) (HTTP \(status)): \(body)"
    }

    /// Un campo suelto del JSON de error de PostgREST.
    nonisolated private static func field(_ name: String, in data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let value = json[name] as? String
        return (value?.isEmpty == false) ? value : nil
    }

    private func persistMode() {
        let d = UserDefaults.standard
        d.set(mode.rawValue, forKey: Keys.mode)
        d.set(backupCode, forKey: Keys.backupCode)
    }

    private static var appVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    private static func decodeScalarString(_ data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(String.self, from: data), !decoded.isEmpty { return decoded }
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"\n "))
        return (raw?.isEmpty == false) ? raw : nil
    }

    // MARK: - Qué se va a guardar

    /// Cuenta lo que la sincronización subiría ahora mismo, a partir de la
    /// misma fotografía que se sube: así el número que ve el usuario no puede
    /// desviarse de lo que de verdad viaja.
    func localSummary() -> BackupSummary {
        guard let snapshot = buildSnapshot() else { return BackupSummary() }
        return BackupSummary(
            rules: snapshot.merchantRules.count,
            categories: snapshot.categoryCatalog.count,
            limits: snapshot.categoryBudgets.count,
            shortcuts: snapshot.quickExpenses.count,
            recurring: snapshot.recurringExpenses.count,
            expenseEdits: snapshot.expenseEdits.count,
            manualExpenses: snapshot.manualTransactions.filter { $0.kind == "expense" }.count,
            manualIncomes: snapshot.manualTransactions.filter { $0.kind == "income" }.count)
    }

    // MARK: - Fotografía del dispositivo

    private func buildSnapshot() -> ConfigSnapshot? {
        guard let context = container?.mainContext else { return nil }

        let quick = (try? context.fetch(FetchDescriptor<QuickExpense>())) ?? []
        let recurring = (try? context.fetch(FetchDescriptor<RecurringExpense>())) ?? []
        let expenses = (try? context.fetch(FetchDescriptor<Expense>())) ?? []
        let incomes = (try? context.fetch(FetchDescriptor<Income>())) ?? []

        var manual: [ManualTransactionBackup] = []

        for e in expenses {
            if e.emailID == nil {
                // Sin correo detrás: si no se sube, se pierde entero.
                manual.append(ManualTransactionBackup(
                    id: e.id, kind: "expense", amount: e.amount, currency: e.currency,
                    title: e.merchant, subtitle: nil, category: e.category,
                    occurredAt: e.date, notes: e.notes,
                    isSubscription: e.isSubscription, isDebt: e.isDebt,
                    cardLastDigits: e.cardLastDigits, fxRate: e.fxRateAtCapture,
                    debtMarkKey: nil, isFinalDebtPayment: false, createdAt: e.date))
            }
            // Los gastos que vienen del correo no se suben: lo que viaja de
            // ellos son las ediciones que el usuario hizo, y eso lo lleva
            // `ExpenseEditStore` — registrado al editar, no deducido después.
        }

        for i in incomes {
            manual.append(ManualTransactionBackup(
                id: i.id, kind: "income", amount: i.amount, currency: i.currency,
                title: i.source, subtitle: i.title, category: "Otros",
                occurredAt: i.date, notes: i.notes,
                isSubscription: false, isDebt: false,
                cardLastDigits: nil, fxRate: i.fxRateAtCapture,
                // Si la relación está rota —el gasto se borró en una relectura—
                // el vínculo persistido sigue sabiendo a qué gasto abonaba.
                debtMarkKey: i.debtReference.map { TransactionKey.key(for: $0) }
                    ?? IncomeLinkStore.markKey(for: i.id),
                isFinalDebtPayment: i.isFinalDebtPayment ?? false,
                createdAt: i.date))
        }

        return ConfigSnapshot(
            merchantRules: MerchantRules.all(),
            categoryCatalog: Array(CategoryCatalog.shared.entries.values).sorted { $0.name < $1.name },
            categoryBudgets: Array(CategoryBudgetStore.shared.budgets.values).sorted { $0.category < $1.category },
            budgetSettings: Self.currentBudgetSettings(),
            bankSources: Self.currentBankSources(),
            notificationSettings: Self.currentNotificationSettings(),
            appearance: Self.currentAppearance(),
            preferences: AppPreferences.snapshot(),
            quickExpenses: quick.map(Self.backup(from:)).sorted { $0.sortIndex < $1.sortIndex },
            recurringExpenses: recurring.map(Self.backup(from:)).sorted { $0.id.uuidString < $1.id.uuidString },
            expenseEdits: ExpenseEditStore.list(),
            manualTransactions: manual.sorted { $0.id.uuidString < $1.id.uuidString })
    }

    /// Huella de lo que se subiría. Todo va ordenado para que dos fotografías
    /// iguales den la misma cadena aunque los diccionarios cambien de orden.
    private static func fingerprint(of snapshot: ConfigSnapshot) -> String {
        let encoder = makeEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return UUID().uuidString }
        // SHA256 y no `hashValue`: el hash de Swift lleva una semilla distinta
        // en cada arranque, así que compararlo entre sesiones subiría siempre.
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Aplicar lo restaurado

    private func apply(_ payload: ConfigBackupPayload) {
        Self.applySettings(payload)
        guard let context = container?.mainContext else { return }

        let quick = (try? context.fetch(FetchDescriptor<QuickExpense>())) ?? []
        let recurring = (try? context.fetch(FetchDescriptor<RecurringExpense>())) ?? []
        Self.applyQuickExpenses(payload.quickExpenses, existing: quick, modelContext: context)
        Self.applyRecurringExpenses(payload.recurringExpenses, existing: recurring, modelContext: context)
        Self.applyManualTransactions(payload, modelContext: context)
        Self.applyExpenseEdits(payload, modelContext: context)

        try? context.save()
    }

    /// Todo lo que vive en `UserDefaults` / los stores singleton.
    static func applySettings(_ payload: ConfigBackupPayload) {
        let defaults = UserDefaults.standard

        defaults.set(payload.merchantRules, forKey: MerchantRules.key)

        for category in payload.categoryCatalog { CategoryCatalog.shared.save(category) }
        for budget in payload.categoryBudgets { CategoryBudgetStore.shared.save(budget) }

        defaults.set(payload.budgetSettings.monthlyBudget, forKey: BudgetStore.monthlyBudgetKey)
        defaults.set(payload.budgetSettings.enabled, forKey: BudgetStore.enabledKey)
        defaults.set(payload.budgetSettings.tracksIncome, forKey: BudgetStore.tracksIncomeKey)

        for bank in BankSource.all {
            if let enabled = payload.bankSources[bank.id] {
                defaults.set(enabled, forKey: bank.storageKey)
            }
        }

        defaults.set(payload.notificationSettings.budgetEnabled, forKey: NotificationSettings.budgetKey)
        defaults.set(payload.notificationSettings.remindRecurring, forKey: NotificationSettings.recurringKey)
        defaults.set(payload.notificationSettings.debtReminderEnabled, forKey: NotificationSettings.debtEnabledKey)
        defaults.set(payload.notificationSettings.debtReminderHour, forKey: NotificationSettings.debtHourKey)
        defaults.set(payload.notificationSettings.debtReminderMinute, forKey: NotificationSettings.debtMinuteKey)
        defaults.set(payload.notificationSettings.categoryLimitAlerts, forKey: NotificationManager.categoryLimitEnabledKey)

        defaults.set(payload.appearance.appearance, forKey: AppAppearance.storageKey)
        defaults.set(payload.appearance.accentColor, forKey: "appAccentColor")
        defaults.set(payload.appearance.textSize, forKey: AppTextSize.storageKey)

        // Al final y por encima de todo lo anterior: el blob cubre esas mismas
        // claves y algunas más, y es el que manda cuando ambos las traen.
        if let preferences = payload.preferences {
            AppPreferences.apply(preferences)
        }
    }

    /// Upsert por `id`: lo que ya existe se actualiza, lo nuevo se inserta, lo
    /// que ya no está en el respaldo se borra.
    static func applyQuickExpenses(_ backups: [QuickExpenseBackup],
                                   existing: [QuickExpense],
                                   modelContext: ModelContext) {
        let existingByID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var keepIDs = Set<UUID>()
        for b in backups {
            keepIDs.insert(b.id)
            if let e = existingByID[b.id] {
                e.label = b.label
                e.merchant = b.merchant
                e.category = b.category
                e.amount = b.amount
                e.currency = b.currency
                e.iconName = b.iconName
                e.sortIndex = b.sortIndex
                e.useCount = b.useCount
                e.lastUsedAt = b.lastUsedAt
            } else {
                let e = QuickExpense(label: b.label, merchant: b.merchant, category: b.category,
                                     amount: b.amount, currency: b.currency, iconName: b.iconName,
                                     sortIndex: b.sortIndex)
                e.id = b.id
                e.useCount = b.useCount
                e.lastUsedAt = b.lastUsedAt
                modelContext.insert(e)
            }
        }
        for e in existing where !keepIDs.contains(e.id) { modelContext.delete(e) }
    }

    static func applyRecurringExpenses(_ backups: [RecurringExpenseBackup],
                                       existing: [RecurringExpense],
                                       modelContext: ModelContext) {
        let existingByID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var keepIDs = Set<UUID>()
        for b in backups {
            keepIDs.insert(b.id)
            if let e = existingByID[b.id] {
                e.merchant = b.merchant
                e.category = b.category
                e.amount = b.amount
                e.currency = b.currency
                e.frequencyRaw = b.frequency
                e.dayOfMonth = b.dayOfMonth
                e.weekdays = b.weekdays
                e.autoConfirm = b.autoConfirm
                e.isPaused = b.isPaused
                e.startDate = b.startDate
                e.endDate = b.endDate
                e.lastResolvedOccurrence = b.lastResolvedOccurrence
            } else {
                let e = RecurringExpense(merchant: b.merchant, category: b.category, amount: b.amount,
                                         currency: b.currency,
                                         frequency: RecurrenceFrequency(rawValue: b.frequency) ?? .monthly,
                                         dayOfMonth: b.dayOfMonth, weekdays: b.weekdays,
                                         autoConfirm: b.autoConfirm, startDate: b.startDate, endDate: b.endDate)
                e.id = b.id
                e.isPaused = b.isPaused
                e.lastResolvedOccurrence = b.lastResolvedOccurrence
                e.createdAt = b.createdAt
                modelContext.insert(e)
            }
        }
        for e in existing where !keepIDs.contains(e.id) { modelContext.delete(e) }
    }

    /// Movimientos creados a mano. Aquí **no** se borra lo que no está en el
    /// respaldo: restaurar no puede llevarse por delante un gasto que el
    /// usuario acaba de anotar en este teléfono.
    static func applyManualTransactions(_ payload: ConfigBackupPayload, modelContext: ModelContext) {
        let expenses = (try? modelContext.fetch(FetchDescriptor<Expense>())) ?? []
        let incomes = (try? modelContext.fetch(FetchDescriptor<Income>())) ?? []
        let existingExpenseIDs = Set(expenses.map(\.id))
        let existingIncomeIDs = Set(incomes.map(\.id))

        var byKey = Dictionary(expenses.map { (TransactionKey.key(for: $0), $0) },
                               uniquingKeysWith: { first, _ in first })

        for t in payload.manualTransactions where t.kind == "expense" {
            guard !existingExpenseIDs.contains(t.id) else { continue }
            let e = Expense(amount: t.amount, merchant: t.title, date: t.occurredAt,
                            category: t.category, notes: t.notes,
                            isSubscription: t.isSubscription, currency: t.currency,
                            emailID: nil, isDebt: t.isDebt,
                            cardLastDigits: t.cardLastDigits, fxRateAtCapture: t.fxRate)
            e.id = t.id
            modelContext.insert(e)
            byKey[TransactionKey.key(for: e)] = e
        }

        var links: [IncomeLink] = []
        for t in payload.manualTransactions where t.kind == "income" {
            // El vínculo se guarda siempre, exista o no el gasto ahora mismo:
            // al restaurar en un teléfono nuevo los gastos del correo todavía
            // no se han leído, y sin esto el cobro quedaría suelto para siempre.
            if let markKey = t.debtMarkKey {
                links.append(IncomeLink(incomeID: t.id, markKey: markKey,
                                        isFinal: t.isFinalDebtPayment))
            }
            guard !existingIncomeIDs.contains(t.id) else { continue }
            let i = Income(amount: t.amount, currency: t.currency, source: t.title,
                           title: t.subtitle, date: t.occurredAt, notes: t.notes,
                           debtReference: t.debtMarkKey.flatMap { byKey[$0] },
                           isFinalDebtPayment: t.isFinalDebtPayment,
                           fxRateAtCapture: t.fxRate)
            i.id = t.id
            modelContext.insert(i)
        }
        IncomeLinkStore.merge(links)
    }

    /// Las ediciones que el usuario hizo sobre gastos del correo. Se funden
    /// con las locales —restaurar no puede borrar lo que se editó en este
    /// teléfono— y se aplican sobre los gastos que ya existan.
    ///
    /// Los que todavía no se han releído del correo no se pierden: el registro
    /// queda guardado y `ExpenseEditStore.apply` los alcanza al terminar la
    /// siguiente lectura de Gmail. Restaurar suele pasar en un teléfono vacío,
    /// donde ninguno de esos gastos existe aún.
    static func applyExpenseEdits(_ payload: ConfigBackupPayload, modelContext: ModelContext) {
        ExpenseEditStore.merge(payload.expenseEdits ?? [])
        ExpenseEditStore.apply(in: modelContext)
        IncomeLinkStore.apply(in: modelContext)
    }

    /// La llama `GmailSyncService` al terminar cada lectura, que es cuando los
    /// gastos acaban de rearmarse. `nonisolated` porque se invoca desde el
    /// cierre de su cola, fuera del actor principal; no toca estado de la clase.
    nonisolated static func reapplyPendingDecisions(modelContext: ModelContext) {
        ExpenseEditStore.apply(in: modelContext)
        IncomeLinkStore.apply(in: modelContext)
    }

    // MARK: - Estado actual del dispositivo

    private static func currentBudgetSettings() -> BudgetSettingsBackup {
        let defaults = UserDefaults.standard
        return BudgetSettingsBackup(
            monthlyBudget: defaults.object(forKey: BudgetStore.monthlyBudgetKey) as? Double ?? 0,
            enabled: defaults.object(forKey: BudgetStore.enabledKey) as? Bool ?? true,
            tracksIncome: defaults.object(forKey: BudgetStore.tracksIncomeKey) as? Bool ?? true)
    }

    private static func currentBankSources() -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: BankSource.all.map { ($0.id, $0.isEnabled) })
    }

    private static func currentNotificationSettings() -> NotificationSettingsBackup {
        let defaults = UserDefaults.standard
        return NotificationSettingsBackup(
            budgetEnabled: defaults.object(forKey: NotificationSettings.budgetKey) as? Bool ?? true,
            remindRecurring: defaults.object(forKey: NotificationSettings.recurringKey) as? Bool ?? true,
            debtReminderEnabled: defaults.object(forKey: NotificationSettings.debtEnabledKey) as? Bool ?? true,
            debtReminderHour: defaults.object(forKey: NotificationSettings.debtHourKey) as? Int ?? 10,
            debtReminderMinute: defaults.object(forKey: NotificationSettings.debtMinuteKey) as? Int ?? 0,
            categoryLimitAlerts: defaults.object(forKey: NotificationManager.categoryLimitEnabledKey) as? Bool ?? true)
    }

    private static func currentAppearance() -> AppearanceBackup {
        let defaults = UserDefaults.standard
        return AppearanceBackup(
            appearance: defaults.string(forKey: AppAppearance.storageKey) ?? AppAppearance.dark.rawValue,
            accentColor: defaults.string(forKey: "appAccentColor") ?? AppThemeColor.blue.rawValue,
            textSize: defaults.string(forKey: AppTextSize.storageKey) ?? AppTextSize.sistema.rawValue)
    }

    private static func backup(from expense: QuickExpense) -> QuickExpenseBackup {
        QuickExpenseBackup(id: expense.id, label: expense.label, merchant: expense.merchant,
                           category: expense.category, amount: expense.amount, currency: expense.currency,
                           iconName: expense.iconName, sortIndex: expense.sortIndex,
                           useCount: expense.useCount, lastUsedAt: expense.lastUsedAt)
    }

    private static func backup(from expense: RecurringExpense) -> RecurringExpenseBackup {
        RecurringExpenseBackup(id: expense.id, merchant: expense.merchant, category: expense.category,
                               amount: expense.amount, currency: expense.currency,
                               frequency: expense.frequencyRaw, dayOfMonth: expense.dayOfMonth,
                               weekdays: expense.weekdays, autoConfirm: expense.autoConfirm,
                               isPaused: expense.isPaused, startDate: expense.startDate,
                               endDate: expense.endDate, lastResolvedOccurrence: expense.lastResolvedOccurrence,
                               createdAt: expense.createdAt)
    }

    // MARK: - Fechas (Postgres devuelve timestamptz con microsegundos)

    // `nonisolated(unsafe)`: `ISO8601DateFormatter` no es Sendable, pero estas
    // dos instancias sólo se leen —nunca se reconfiguran tras crearse— y
    // formatear es seguro en paralelo. Sin `(unsafe)` es error en Swift 6.
    nonisolated(unsafe) private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Postgres devuelve `timestamptz` con **microsegundos**
    /// (`2026-03-01T12:00:00.123456+00:00`) y `ISO8601DateFormatter` sólo
    /// admite hasta milésimas: sin recortar la fracción, todo el respaldo falla
    /// al decodificarse con un "Fecha inválida" difícil de rastrear.
    nonisolated static func parseDate(_ text: String) -> Date? {
        if let date = isoWithFraction.date(from: text) { return date }
        if let date = isoPlain.date(from: text) { return date }
        if let dot = text.firstIndex(of: "."),
           let end = text[dot...].firstIndex(where: { !$0.isNumber && $0 != "." }) {
            let fraction = text[text.index(after: dot)..<end]
            if fraction.count > 3 {
                let trimmed = text[..<dot] + "." + fraction.prefix(3) + text[end...]
                if let date = isoWithFraction.date(from: String(trimmed)) { return date }
            }
            let withoutFraction = String(text[..<dot] + text[end...])
            if let date = isoPlain.date(from: withoutFraction) { return date }
        }
        return TransactionKey.dayFormatter.date(from: text)
    }

    nonisolated static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = parseDate(text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Fecha inválida: \(text)")
        }
        return decoder
    }

    nonisolated static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoWithFraction.string(from: date))
        }
        return encoder
    }
}

// MARK: - Formas que viajan

struct QuickExpenseBackup: Codable {
    var id: UUID
    var label: String
    var merchant: String
    var category: String
    @MoneyCoded var amount: Double
    var currency: String
    var iconName: String
    var sortIndex: Int
    var useCount: Int
    var lastUsedAt: Date?
}

struct RecurringExpenseBackup: Codable {
    var id: UUID
    var merchant: String
    var category: String
    @MoneyCoded var amount: Double
    var currency: String
    var frequency: String
    var dayOfMonth: Int
    var weekdays: [Int]
    var autoConfirm: Bool
    var isPaused: Bool
    var startDate: Date
    var endDate: Date?
    var lastResolvedOccurrence: Date?
    var createdAt: Date
}

struct BudgetSettingsBackup: Codable {
    @MoneyCoded var monthlyBudget: Double
    var enabled: Bool
    var tracksIncome: Bool
}

struct NotificationSettingsBackup: Codable {
    var budgetEnabled: Bool
    var remindRecurring: Bool
    var debtReminderEnabled: Bool
    var debtReminderHour: Int
    var debtReminderMinute: Int
    var categoryLimitAlerts: Bool
}

struct AppearanceBackup: Codable {
    var appearance: String
    var accentColor: String
    var textSize: String
}



/// Un gasto o ingreso escrito a mano: no hay correo del que rearmarlo.
struct ManualTransactionBackup: Codable {
    var id: UUID
    var kind: String            // "expense" | "income"
    @MoneyCoded var amount: Double
    var currency: String
    var title: String           // gasto: comercio · ingreso: origen
    var subtitle: String?       // ingreso: título ("Sueldo")
    var category: String
    var occurredAt: Date
    var notes: String?
    var isSubscription: Bool
    var isDebt: Bool
    var cardLastDigits: String?
    @RateCoded var fxRate: Double?
    var debtMarkKey: String?
    var isFinalDebtPayment: Bool
    var createdAt: Date
}

/// Lo que se sube. Es también lo que se resume en la huella.
struct ConfigSnapshot: Codable {
    var merchantRules: [String: String]
    var categoryCatalog: [CustomCategory]
    var categoryBudgets: [CategoryBudget]
    var budgetSettings: BudgetSettingsBackup
    var bankSources: [String: Bool]
    var notificationSettings: NotificationSettingsBackup
    var appearance: AppearanceBackup
    /// Todas las preferencias de `UserDefaults` en un solo sitio: añadir una
    /// no exige tocar el esquema (ver `AppPreferences`).
    var preferences: [String: AnyCodableValue]
    var quickExpenses: [QuickExpenseBackup]
    var recurringExpenses: [RecurringExpenseBackup]
    var expenseEdits: [ExpenseEdit]
    var manualTransactions: [ManualTransactionBackup]

    /// Cuerpo del RPC. Cada bloque se manda como JSON ya serializado para que
    /// Postgres lo reciba como `jsonb` sin que haya que describir aquí cada
    /// campo dos veces.
    var rpcBody: [String: Any] {
        let encoder = ConfigBackupManager.makeEncoder()
        func json(_ value: some Encodable) -> Any {
            guard let data = try? encoder.encode(value),
                  let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            else { return NSNull() }
            return object
        }
        return [
            "p_merchant_rules": merchantRules,
            "p_category_catalog": json(categoryCatalog),
            "p_category_budgets": json(categoryBudgets),
            "p_budget_settings": json(budgetSettings),
            "p_bank_sources": bankSources,
            "p_notification_settings": json(notificationSettings),
            "p_appearance": json(appearance),
            "p_preferences": preferences.mapValues(\.jsonValue),
            "p_quick_expenses": json(quickExpenses),
            "p_recurring_expenses": json(recurringExpenses),
            "p_expense_edits": json(expenseEdits),
            "p_manual_transactions": json(manualTransactions)
        ]
    }
}

/// Lo que devuelve `read_config_backup`.
struct ConfigBackupPayload: Codable {
    var backupCode: String?
    var updatedAt: Date
    var accountEmail: String?
    var merchantRules: [String: String]
    var categoryCatalog: [CustomCategory]
    var categoryBudgets: [CategoryBudget]
    var budgetSettings: BudgetSettingsBackup
    var bankSources: [String: Bool]
    var notificationSettings: NotificationSettingsBackup
    var appearance: AppearanceBackup
    var preferences: [String: AnyCodableValue]?
    var quickExpenses: [QuickExpenseBackup]
    var recurringExpenses: [RecurringExpenseBackup]
    var expenseEdits: [ExpenseEdit]?
    var manualTransactions: [ManualTransactionBackup]
}

/// Lo que la sincronización guardaría de este teléfono, desglosado. Sustituye
/// al viejo "412 gastos en este dispositivo": los gastos del correo nunca se
/// suben, así que ese número decía exactamente lo contrario de la verdad.
struct BackupSummary {
    var rules = 0
    var categories = 0
    var limits = 0
    var shortcuts = 0
    var recurring = 0
    var expenseEdits = 0
    var manualExpenses = 0
    var manualIncomes = 0

    var total: Int {
        rules + categories + limits + shortcuts + recurring
        + expenseEdits + manualExpenses + manualIncomes
    }

    struct Row: Identifiable {
        let title: String
        let icon: String
        let count: Int
        var id: String { title }
    }

    /// Las filas que se enseñan, ya sin las vacías: una lista con seis ceros no
    /// informa, sólo ocupa.
    var rows: [Row] {
        [
            Row(title: "Reglas de comercio", icon: "slider.horizontal.3", count: rules),
            Row(title: "Categorías y renombrados", icon: "square.grid.2x2", count: categories),
            Row(title: "Límites por categoría", icon: "gauge.with.dots.needle.33percent", count: limits),
            Row(title: "Atajos rápidos", icon: "bolt.fill", count: shortcuts),
            Row(title: "Gastos recurrentes", icon: "repeat", count: recurring),
            Row(title: "Cambios en gastos del correo", icon: "hand.point.up.left", count: expenseEdits),
            Row(title: "Gastos anotados a mano", icon: "square.and.pencil", count: manualExpenses),
            Row(title: "Ingresos anotados a mano", icon: "arrow.down.left.circle", count: manualIncomes)
        ].filter { $0.count > 0 }
    }
}

/// Cabecera de `peek_config_backup`: saber qué hay antes de traerlo todo.
struct BackupHeader: Codable, Identifiable, Equatable {
    var backupCode: String
    var updatedAt: Date?
    var deviceLabel: String?
    var accountEmail: String?
    var hasData: Bool
    // Cuentas para poder decir "38 reglas, 12 categorías" en vez de "hay un
    // respaldo": la diferencia entre aceptar y no aceptar tiene que verse.
    var ruleCount: Int?
    var categoryCount: Int?
    var limitCount: Int?
    var shortcutCount: Int?
    var manualCount: Int?

    var id: String { backupCode }
}
