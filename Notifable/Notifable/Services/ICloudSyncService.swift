import Foundation
import SwiftData

/// Lectura de avisos de banco desde un buzón de iCloud.
///
/// Equivalente a `GmailSyncService`, pero por IMAP: **Apple no publica ninguna
/// API de correo para iCloud**, así que no hay OAuth, no hay token de sólo
/// lectura y no hay permisos que revocar desde la app. Ver `ICloudMailAccount`
/// para lo que eso implica y `IMAPClient` para cómo se limita el acceso.
///
/// A partir del texto del correo, todo es idéntico a Gmail: los mismos parsers,
/// la misma regla de categoría y la misma deduplicación, porque todo eso vive
/// en `BankEmailIngestor`.
@MainActor
final class ICloudSyncService: ObservableObject {

    static let shared = ICloudSyncService()

    @Published private(set) var isSyncing = false
    @Published private(set) var lastError: String?
    @Published private(set) var totalToProcess = 0
    @Published private(set) var processed = 0
    @Published private(set) var foundByBank: [String: Int] = [:]

    /// Correos ya mirados, para no volver a bajarlos. Se guarda como `Set` y no
    /// como array: la lista de Gmail creció a miles de identificadores y
    /// buscarlos linealmente dentro de un bucle costaba más que la propia red.
    private static let processedKey = "iCloudProcessedUIDs"

    var modelContext: ModelContext?

    private init() {}

    // MARK: - Comprobar la cuenta

    /// Intenta conectar y autenticarse, sin leer nada. Es lo que valida el
    /// formulario: decir "guardado" y que falle en la primera sincronización
    /// deja al usuario sin saber si se equivocó de contraseña o si no hay
    /// correos.
    func verify(address: String, password: String) async -> String? {
        let client = IMAPClient()
        do {
            try await client.connect()
            try await client.login(user: ICloudMailAccount.imapUsername(for: address),
                                   password: ICloudMailAccount.normalize(password))
            try await client.examine()
            await client.disconnect()
            return nil
        } catch {
            await client.disconnect()
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Sincronizar

    /// Lee los avisos de banco entre dos fechas. Sin `startDate` se retoma
    /// desde la última lectura, con una hora de margen por si algún correo
    /// entró justo en el corte.
    func sync(startDate: Date? = nil, endDate: Date? = nil) async {
        guard !isSyncing else { return }
        guard let address = ICloudMailAccount.address,
              let password = ICloudMailAccount.password(for: address) else {
            lastError = "No hay ninguna cuenta de iCloud conectada."
            return
        }
        guard let context = modelContext else { return }

        let since = startDate
            ?? ICloudMailAccount.lastSync?.addingTimeInterval(-3600)
            ?? Calendar.current.date(byAdding: .month, value: -1, to: Date())!

        isSyncing = true
        lastError = nil
        processed = 0
        totalToProcess = 0
        foundByBank = Dictionary(uniqueKeysWithValues: BankEmailIngestor.parsers.map { ($0.bankName, 0) })
        defer { isSyncing = false }

        let client = IMAPClient()
        do {
            try await client.connect()
            try await client.login(user: ICloudMailAccount.imapUsername(for: address),
                                   password: ICloudMailAccount.normalize(password))
            try await client.examine()

            // Una búsqueda por remitente. Ver `IMAPClient.searchUIDs`.
            var uids: Set<UInt32> = []
            for sender in BankEmailIngestor.senderEmails {
                // Un remitente que falle no puede tumbar la sincronización
                // entera: se pierde ese banco, no todos.
                if let found = try? await client.searchUIDs(from: sender, since: since) {
                    uids.formUnion(found)
                }
            }

            var alreadyProcessed = Self.processedUIDs()
            let pending = uids.subtracting(alreadyProcessed).sorted()
            totalToProcess = pending.count

            // Se siembra con lo que ya está en la base: si la lista de
            // procesados se perdió, el `emailID` sigue evitando duplicar.
            var knownIDs = BankEmailIngestor.existingEmailIDs(in: context)

            for uid in pending {
                let emailID = Self.emailID(address: address, uid: uid)
                processed += 1

                guard !knownIDs.contains(emailID) else {
                    alreadyProcessed.insert(uid)
                    continue
                }
                guard let raw = try? await client.fetchMessage(uid: uid), !raw.isEmpty else {
                    // No se marca como procesado: un fallo de red debe poder
                    // reintentarse en la siguiente sincronización.
                    continue
                }

                // Abrir el MIME es trabajo de CPU sobre un correo que puede
                // pesar cientos de kilobytes por el HTML del banco. Fuera del
                // hilo principal, o la interfaz se traba en cada correo.
                let message = await Task.detached(priority: .userInitiated) {
                    MIMEDecoder.parse(raw: raw)
                }.value

                if let parsed = BankEmailIngestor.parse(message.text) {
                    var inserted = false
                    if let expense = parsed.expense {
                        // El correo manda sobre la cabecera `Date` sólo si el
                        // parser no supo sacar la fecha del propio aviso.
                        inserted = BankEmailIngestor.insert(expense: expense,
                                                            bankName: parsed.bankName,
                                                            emailID: emailID,
                                                            context: context)
                    } else if let income = parsed.income {
                        inserted = BankEmailIngestor.insert(income: income,
                                                            emailID: emailID,
                                                            context: context)
                    }
                    if inserted {
                        knownIDs.insert(emailID)
                        foundByBank[parsed.bankName, default: 0] += 1
                    }
                }
                alreadyProcessed.insert(uid)
            }

            Self.storeProcessedUIDs(alreadyProcessed)
            // Igual que en Gmail: una lectura de un rango pasado no significa
            // "ya está todo al día", o el tramo hasta hoy no se bajaría nunca.
            if endDate == nil { ICloudMailAccount.lastSync = Date() }

            await client.disconnect()
            ConfigBackupManager.reapplyPendingDecisions(modelContext: context)

        } catch {
            await client.disconnect()
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Estado local

    /// El identificador que se guarda en `Expense.emailID`.
    ///
    /// Lleva la dirección delante porque el UID sólo es único **dentro de un
    /// buzón**: sin ella, el correo 42 de una cuenta y el 42 de otra serían el
    /// mismo, y cambiar de cuenta de iCloud haría desaparecer movimientos por
    /// una colisión. El prefijo también los separa de los de Gmail.
    nonisolated static func emailID(address: String, uid: UInt32) -> String {
        "icloud:\(address):\(uid)"
    }

    static func processedUIDs() -> Set<UInt32> {
        let stored = UserDefaults.standard.array(forKey: processedKey) as? [Int] ?? []
        return Set(stored.map(UInt32.init))
    }

    private static func storeProcessedUIDs(_ uids: Set<UInt32>) {
        UserDefaults.standard.set(uids.map(Int.init), forKey: processedKey)
    }

    static func resetSyncState() {
        UserDefaults.standard.removeObject(forKey: processedKey)
        ICloudMailAccount.lastSync = nil
    }
}
