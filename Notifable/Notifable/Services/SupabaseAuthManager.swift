import Foundation
import Security

/// Sesión de Supabase para Amigos. Decide **quién eres** para `auth.uid()` y,
/// con eso, de quién son las amistades, los compartidos y el código de amigo.
///
/// Dos identidades posibles, en este orden:
///
/// 1. **La cuenta de Google** (`BackupAccount`, la misma del respaldo de
///    configuración). No cambia al reinstalar ni al cambiar de teléfono. La
///    primera vez, `adopt_social_identity` le pasa todo lo del perfil anónimo
///    anterior (ver `agrupay_friends_v6_google_identity.sql`).
/// 2. **Una sesión anónima**, sólo para quien nunca conectó Google. Vive en el
///    Llavero, que sobrevive a borrar la app; antes vivía en UserDefaults y
///    cada reinstalación creaba una persona nueva sin amigos.
///
/// Una vez que el teléfono usó la cuenta de Google para Amigos, ya no vuelve a
/// crear sesiones anónimas: si Google no responde, Amigos espera en vez de
/// empezar de cero con otra identidad.
///
/// Comparte proyecto de Supabase con `SyncManager` (Views/SocialView.swift),
/// pero no su tabla: Amigos nunca sube movimientos ni comercios, sólo los
/// totales agregados que el usuario decide compartir (ver FriendsManager).
@MainActor
@Observable
final class SupabaseAuthManager {

    static let shared = SupabaseAuthManager()

    private let projectURL = "https://zjzzqaeusmxmtszgdncl.supabase.co"
    private let apiKey = "sb_publishable_NVM2GcvxZFmf0VLNbaBr7A_y_8EMS97"

    /// El `auth.uid()` con el que habla Amigos ahora mismo.
    private(set) var userID: String?

    /// Sesión anónima. Sólo se usa mientras no haya cuenta de Google enlazada.
    private var anonUserID: String?
    private var anonAccessToken: String?
    private var anonRefreshToken: String?

    private enum Keys {
        static let anonUserID = "supabaseUserID"
        static let anonAccessToken = "supabaseAccessToken"
        static let anonRefreshToken = "supabaseRefreshToken"
        static let displayName = "socialDisplayName"
        /// Id de la cuenta de Google que ya adoptó la identidad de Amigos en
        /// este teléfono. Presente = no volver a la sesión anónima.
        static let linkedGoogleUserID = "socialLinkedGoogleUserID"
    }

    var displayName: String? {
        get { UserDefaults.standard.string(forKey: Keys.displayName) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.displayName) }
    }

    private var linkedGoogleUserID: String? {
        get { UserDefaults.standard.string(forKey: Keys.linkedGoogleUserID) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.linkedGoogleUserID) }
    }

    /// `true` si Amigos habla con la cuenta de Google y no con la anónima.
    var usesGoogleIdentity: Bool {
        guard let linked = linkedGoogleUserID else { return false }
        return userID == linked
    }

    private(set) var isReady = false

    private init() {
        loadAnonymousSession()
        if let linked = linkedGoogleUserID, BackupAccount.shared.userID == linked {
            userID = linked
            isReady = true
        } else if linkedGoogleUserID == nil, let anonUserID, anonAccessToken != nil {
            userID = anonUserID
            isReady = true
        }
    }

    // MARK: - Entrar

    /// Punto de entrada único; se llama al abrir la pestaña Amigos. Elige la
    /// identidad, adopta el perfil anónimo si toca y sincroniza el perfil.
    /// `false` si no hay forma de tener sesión ahora.
    @discardableResult
    func ensureSession(defaultName: String) async -> Bool {
        if await resolveGoogleIdentity() {
            userID = linkedGoogleUserID
        } else if linkedGoogleUserID != nil {
            // Ya se enlazó Google en este teléfono: no se crea otra persona.
            print("Amigos: la cuenta de Google no respondió; se reintenta al volver a abrir Amigos.")
            isReady = false
            return false
        } else {
            if anonAccessToken == nil { await signInAnonymously() }
            userID = anonUserID
        }

        let token = await validAccessToken()
        isReady = userID != nil && token != nil
        guard isReady else { return false }

        await syncOwnProfile(defaultName: defaultName)
        return true
    }

    /// `true` si Amigos puede usar la cuenta de Google. La primera vez adopta
    /// en el servidor el perfil anónimo de este teléfono y los que tuvieran el
    /// mismo correo; hasta que eso sale bien se sigue con la sesión anónima,
    /// para no dejar a nadie con una cuenta vacía si el SQL v6 no está.
    private func resolveGoogleIdentity() async -> Bool {
        let account = BackupAccount.shared
        // Esperar al login de Google antes de caer en la anónima: hoy la
        // sesión anónima se creaba en paralelo y dejaba un perfil vacío.
        if !account.isSignedIn, account.canSignInSilently {
            _ = await account.signInWithGoogle()
        }
        guard account.isSignedIn, let googleID = account.userID,
              await account.validAccessToken() != nil else { return false }

        if linkedGoogleUserID == googleID, anonRefreshToken == nil { return true }

        // Vale de un solo uso firmado con la sesión anónima: prueba que este
        // teléfono es dueño de ese perfil. Sin sesión anónima, no hace falta.
        let linkToken = anonRefreshToken == nil ? nil : await createLinkToken()

        guard let result = await adopt(linkToken: linkToken) else {
            return linkedGoogleUserID == googleID
        }

        linkedGoogleUserID = googleID
        clearAnonymousSession()
        if let code = result.code {
            UserDefaults.standard.set(code, forKey: FriendsManager.friendCodeKey(googleID))
        }
        print("Amigos: identidad de Google lista (\(result.merged) perfil(es) adoptado(s)).")
        return true
    }

    private struct AdoptResult: Decodable {
        let merged: Int
        let code: String?
    }

    private func adopt(linkToken: String?) async -> AdoptResult? {
        guard let url = URL(string: "\(projectURL)/rest/v1/rpc/adopt_social_identity"),
              let token = await BackupAccount.shared.validAccessToken() else { return nil }
        var request = request(url: url, method: "POST", token: token)
        let body: [String: Any] = ["p_link_token": linkToken as Any? ?? NSNull()]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                print("Amigos: adopt_social_identity falló (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)). \(body.prefix(200))")
                return nil
            }
            return try JSONDecoder().decode(AdoptResult.self, from: data)
        } catch {
            print("Amigos: error adoptando la identidad: \(error)")
            return nil
        }
    }

    private func createLinkToken() async -> String? {
        guard let url = URL(string: "\(projectURL)/rest/v1/rpc/create_identity_link_token"),
              let token = await validAnonymousAccessToken() else { return nil }
        var request = request(url: url, method: "POST", token: token)
        request.httpBody = Data("{}".utf8)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
        return try? JSONDecoder().decode(String.self, from: data)
    }

    // MARK: - Perfil propio

    /// Si el servidor ya tiene mi perfil (reinstalación, otro teléfono), manda
    /// el servidor: se baja nombre, estado, emoji y pingüino. Antes se subía
    /// el nombre local, y en un teléfono recién instalado ese nombre era
    /// "Amigo" y pisaba el de verdad. Si no hay perfil, se crea con lo local.
    private func syncOwnProfile(defaultName: String) async {
        if let remote = await fetchOwnProfile() {
            let store = SocialProfileStore.shared
            let name = remote.display_name.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                displayName = name
                store.displayName = name
            }
            if let status = remote.status { store.status = status }
            if let emoji = remote.avatar_emoji { store.avatarEmoji = emoji.isEmpty ? nil : emoji }
            if let penguin = remote.penguin { store.penguin = penguin }
            return
        }
        if displayName == nil { displayName = defaultName }
        if let name = displayName { await pushProfile(name: name) }
    }

    private struct OwnProfile: Decodable {
        let display_name: String
        let status: String?
        let avatar_emoji: String?
        let penguin: PenguinLook?
    }

    private func fetchOwnProfile() async -> OwnProfile? {
        guard let userID,
              let url = URL(string: "\(projectURL)/rest/v1/profiles?id=eq.\(userID)&select=*"),
              let request = await authorizedRequest(url: url, method: "GET"),
              let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
        return (try? JSONDecoder().decode([OwnProfile].self, from: data))?.first
    }

    /// El usuario cambió su nombre (p. ej. desde un ajuste futuro). Vuelve a
    /// subirlo a `profiles` para que los amigos ya conectados lo vean.
    func updateDisplayName(_ name: String) async {
        displayName = name
        await pushProfile(name: name)
    }

    /// Nombre, estado y emoji de una vez: es lo que guarda el modal de perfil.
    /// El pingüino (`SocialProfileStore.penguin`) va con los demás campos.
    func updateProfile(name: String, status: String, avatarEmoji: String?) async {
        displayName = name
        SocialProfileStore.shared.displayName = name
        SocialProfileStore.shared.status = status
        SocialProfileStore.shared.avatarEmoji = avatarEmoji
        await pushProfile(name: name, status: status, avatarEmoji: avatarEmoji)
    }

    /// `false` mientras el proyecto de Supabase no tenga las columnas nuevas de
    /// `profiles`. Lo pone `pushProfile` al ver que el servidor las rechaza, y
    /// lo lee Amigos para no prometer que el estado se ve del otro lado.
    private(set) var supportsProfileExtras = true

    /// Upsert por `id` (clave primaria de `profiles`): crea la fila la primera
    /// vez, y la actualiza si el nombre cambió.
    private func pushProfile(name: String,
                            status: String? = nil,
                            avatarEmoji: String? = nil) async {
        let store = SocialProfileStore.shared
        let sentStatus = status ?? store.status
        let sentEmoji = avatarEmoji ?? store.avatarEmoji

        // Tres intentos como mucho, de más a menos campos, por si el servidor
        // todavía no tiene alguna columna (falta correr su SQL). Sólo se baja
        // de nivel con un 400 — lo que devuelve PostgREST ante una columna
        // desconocida —; un 401 o un fallo de red no dicen nada del esquema y
        // antes apagaban el estado para toda la sesión.
        var extended: [String: Any] = [
            "display_name": name,
            "status": sentStatus, "avatar_emoji": sentEmoji ?? ""
        ]
        if supportsProfileExtras && supportsPenguin,
           let data = try? JSONEncoder().encode(store.penguin),
           let penguin = try? JSONSerialization.jsonObject(with: data) {
            var withPenguin = extended
            withPenguin["penguin"] = penguin
            let code = await postProfile(fields: withPenguin)
            if Self.isSuccess(code) { return }
            guard code == 400 else { return }
            supportsPenguin = false
            print("Amigos: `profiles` todavía no tiene `penguin` (agrupay_friends_v5_penguin.sql).")
        }
        if supportsProfileExtras {
            let code = await postProfile(fields: extended)
            if Self.isSuccess(code) { return }
            guard code == 400 else { return }
            supportsProfileExtras = false
            print("Amigos: `profiles` todavía no tiene `status`/`avatar_emoji`; se sube sólo el nombre.")
        }
        extended = ["display_name": name]
        _ = await postProfile(fields: extended)
    }

    private static func isSuccess(_ code: Int?) -> Bool {
        guard let code else { return false }
        return (200...299).contains(code)
    }

    /// `false` mientras `profiles` no tenga la columna `penguin`.
    private var supportsPenguin = true

    /// El código HTTP con el que respondió el servidor, `nil` sin sesión o
    /// sin red. El `id` se pone aquí, que es donde se sabe que hay sesión.
    private func postProfile(fields: [String: Any]) async -> Int? {
        guard let userID, let url = URL(string: "\(projectURL)/rest/v1/profiles"),
              var request = await authorizedRequest(url: url, method: "POST") else { return nil }
        request.addValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        var payload = fields
        payload["id"] = userID
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode
        } catch {
            return nil
        }
    }

    // MARK: - Tokens

    /// Un `access_token` vivo de la identidad actual, refrescándolo si venció.
    /// Todo lo que hable con Supabase desde Amigos (REST y Realtime) pasa por
    /// aquí, no por un token guardado: el JWT dura una hora.
    func validAccessToken() async -> String? {
        guard let userID else { return nil }
        if userID == linkedGoogleUserID {
            return await BackupAccount.shared.validAccessToken()
        }
        return await validAnonymousAccessToken()
    }

    /// Base para que `FriendsManager` arme sus propias peticiones REST/RPC
    /// autenticadas, sin repetir las tres cabeceras en cada sitio.
    func authorizedRequest(url: URL, method: String) async -> URLRequest? {
        guard let token = await validAccessToken() else { return nil }
        return request(url: url, method: method, token: token)
    }

    private func request(url: URL, method: String, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.addValue(apiKey, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    var baseURL: String { projectURL }

    // MARK: - Sesión anónima

    private func signInAnonymously() async {
        guard let url = URL(string: "\(projectURL)/auth/v1/signup") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "apikey")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [String: String]())

        struct AuthResponse: Decodable {
            let access_token: String
            let refresh_token: String
            let user: UserPayload
            struct UserPayload: Decodable { let id: String }
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                print("Amigos: no se pudo crear la sesión anónima. ¿Activaste 'Anonymous sign-ins' en Supabase Auth?")
                return
            }
            let decoded = try JSONDecoder().decode(AuthResponse.self, from: data)
            anonUserID = decoded.user.id
            anonAccessToken = decoded.access_token
            anonRefreshToken = decoded.refresh_token
            saveAnonymousSession()
        } catch {
            print("Amigos: error de red creando sesión anónima: \(error)")
        }
    }

    private func validAnonymousAccessToken() async -> String? {
        if let anonAccessToken, !Self.isExpired(anonAccessToken) { return anonAccessToken }
        guard await refreshAnonymousSession() else { return nil }
        return anonAccessToken
    }

    /// Decodifica el `exp` del JWT (segunda parte, base64url) sin verificar
    /// la firma — sólo hace falta saber si ya venció, no validarlo; eso ya lo
    /// hace el servidor en cada petición.
    private static func isExpired(_ token: String) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return true }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? Double else { return true }
        // 30s de margen: que no vaya a vencer a mitad de una petición.
        return Date(timeIntervalSince1970: exp) <= Date().addingTimeInterval(30)
    }

    private func refreshAnonymousSession() async -> Bool {
        guard let anonRefreshToken,
              let url = URL(string: "\(projectURL)/auth/v1/token?grant_type=refresh_token") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "apikey")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": anonRefreshToken])

        struct RefreshResponse: Decodable {
            let access_token: String
            let refresh_token: String
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                print("Amigos: no se pudo refrescar la sesión anónima (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)).")
                return false
            }
            let decoded = try JSONDecoder().decode(RefreshResponse.self, from: data)
            anonAccessToken = decoded.access_token
            self.anonRefreshToken = decoded.refresh_token
            saveAnonymousSession()
            return true
        } catch {
            print("Amigos: error de red refrescando la sesión anónima: \(error)")
            return false
        }
    }

    /// Del Llavero; si no está, de UserDefaults (versiones anteriores), y se
    /// muda al Llavero para que la próxima reinstalación la encuentre.
    private func loadAnonymousSession() {
        if let id = Keychain.read(Keys.anonUserID), let refresh = Keychain.read(Keys.anonRefreshToken) {
            anonUserID = id
            anonRefreshToken = refresh
            anonAccessToken = Keychain.read(Keys.anonAccessToken)
            return
        }
        let d = UserDefaults.standard
        guard let id = d.string(forKey: Keys.anonUserID),
              let refresh = d.string(forKey: Keys.anonRefreshToken) else { return }
        anonUserID = id
        anonRefreshToken = refresh
        anonAccessToken = d.string(forKey: Keys.anonAccessToken)
        saveAnonymousSession()
    }

    private func saveAnonymousSession() {
        Keychain.write(anonUserID, for: Keys.anonUserID)
        Keychain.write(anonAccessToken, for: Keys.anonAccessToken)
        Keychain.write(anonRefreshToken, for: Keys.anonRefreshToken)
        let d = UserDefaults.standard
        [Keys.anonUserID, Keys.anonAccessToken, Keys.anonRefreshToken].forEach { d.removeObject(forKey: $0) }
    }

    /// Tras adoptarla, la sesión anónima ya no identifica a nadie.
    private func clearAnonymousSession() {
        anonUserID = nil
        anonAccessToken = nil
        anonRefreshToken = nil
        saveAnonymousSession()
    }
}

/// Lo mínimo del Llavero para tres textos. `AfterFirstUnlock`: Realtime y los
/// intents pueden pedir el token con el teléfono bloqueado.
private enum Keychain {
    private static let service = "clmilo.Notifable.amigos"

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String?, for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        guard let value else { return }
        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
