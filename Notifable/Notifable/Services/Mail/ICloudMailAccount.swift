import Foundation
import Security

/// La cuenta de iCloud conectada, con su contraseña específica en el Keychain.
///
/// **Por qué esto no se parece a Gmail.** Gmail se conecta con OAuth: el
/// usuario aprueba en Google, la app recibe un token limitado a
/// `gmail.readonly`, nunca ve la contraseña y el permiso se revoca desde la
/// cuenta de Google. Apple no publica ninguna API de correo para iCloud ni
/// OAuth para el buzón: la única vía es IMAP con una **contraseña específica de
/// aplicación** que el usuario genera en appleid.apple.com y teclea aquí.
///
/// Eso tiene consecuencias que la pantalla tiene que decir en voz alta, porque
/// no son obvias:
///
/// - Esa contraseña abre el buzón **entero**, y no sólo para leer: IMAP y SMTP
///   van juntos, así que técnicamente permite también enviar correo. Apple no
///   ofrece un permiso de sólo lectura. La app se limita sola —`EXAMINE` y
///   `BODY.PEEK`, ver `IMAPClient`— pero es una limitación nuestra, no un
///   permiso que Apple imponga.
/// - Se revoca sólo desde appleid.apple.com, no desde la app.
///
/// Por eso se guarda en el Keychain con `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`:
/// sólo con el teléfono desbloqueado, y sin viajar a la copia de seguridad de
/// iCloud ni a un iPhone nuevo. Una credencial de este alcance no debe estar en
/// `UserDefaults`, que es un plist en claro dentro del contenedor de la app.
enum ICloudMailAccount {

    /// Bajo qué servicio se guarda en el Keychain.
    private static let service = "com.agrupay.icloudmail"
    static let addressKey = "iCloudMailAddress"
    /// Desde cuándo se ha leído, para no volver a pedir lo mismo.
    static let lastSyncKey = "iCloudMailLastSync"

    // MARK: - Estado

    /// La dirección conectada, o `nil` si no hay ninguna.
    static var address: String? {
        UserDefaults.standard.string(forKey: addressKey)
    }

    static var isConnected: Bool {
        guard let address, !address.isEmpty else { return false }
        return password(for: address) != nil
    }

    static var lastSync: Date? {
        get { UserDefaults.standard.object(forKey: lastSyncKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastSyncKey) }
    }

    /// El usuario que quiere IMAP es la parte anterior a la arroba, no la
    /// dirección entera: Apple usa el nombre corto para la entrada y la
    /// dirección completa para la salida. Con la dirección entera el `LOGIN`
    /// falla con un error de credenciales que no explica nada.
    static func imapUsername(for address: String) -> String {
        address.components(separatedBy: "@").first ?? address
    }

    // MARK: - Guardar y borrar

    /// Guarda la cuenta. La contraseña se normaliza: Apple la enseña como
    /// `abcd-efgh-ijkl-mnop` y la gente la copia con los guiones, con espacios
    /// o pegada — las tres formas valen.
    static func save(address: String, password: String) throws {
        let cleanAddress = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanPassword = normalize(password)

        try storePassword(cleanPassword, for: cleanAddress)
        UserDefaults.standard.set(cleanAddress, forKey: addressKey)
    }

    static func disconnect() {
        if let address { deletePassword(for: address) }
        UserDefaults.standard.removeObject(forKey: addressKey)
        UserDefaults.standard.removeObject(forKey: lastSyncKey)
    }

    /// Apple presenta la contraseña en cuatro grupos de cuatro. Ni los guiones
    /// ni los espacios forman parte de ella.
    static func normalize(_ password: String) -> String {
        password.replacingOccurrences(of: "-", with: "")
            .components(separatedBy: .whitespacesAndNewlines).joined()
    }

    /// `true` si tiene pinta de contraseña específica de Apple: 16 letras.
    /// Sirve para avisar antes de intentar conectar, no para rechazar — si
    /// Apple cambiara el formato, un chequeo estricto dejaría la función muerta.
    static func looksLikeAppPassword(_ password: String) -> Bool {
        let clean = normalize(password)
        return clean.count == 16 && clean.allSatisfy { $0.isLetter }
    }

    // MARK: - Keychain

    static func password(for address: String) -> String? {
        var query = baseQuery(account: address)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func storePassword(_ password: String, for address: String) throws {
        deletePassword(for: address)

        var query = baseQuery(account: address)
        query[kSecValueData as String] = Data(password.utf8)
        // Sólo con el teléfono desbloqueado, y sin salir de este dispositivo:
        // ni al respaldo de iCloud ni a un iPhone restaurado.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "No se pudo guardar la contraseña de forma segura."
            ])
        }
    }

    private static func deletePassword(for address: String) {
        SecItemDelete(baseQuery(account: address) as CFDictionary)
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
