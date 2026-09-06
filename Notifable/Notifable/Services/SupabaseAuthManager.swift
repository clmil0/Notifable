import Foundation

/// Sesión de Supabase para Amigos: un usuario anónimo por dispositivo — sin
/// email ni contraseña, sólo un `auth.uid()` estable que las políticas RLS
/// usan para decidir qué puede leer o escribir cada quien. El nombre que ven
/// tus amigos se pide una sola vez y se guarda en `profiles`.
///
/// Comparte proyecto de Supabase con `SyncManager` (Views/SocialView.swift),
/// pero no su tabla: Amigos nunca sube movimientos ni comercios, sólo los
/// totales agregados que el usuario decide compartir (ver FriendsManager).
@Observable
final class SupabaseAuthManager {

    static let shared = SupabaseAuthManager()

    private let projectURL = "https://zjzzqaeusmxmtszgdncl.supabase.co"
    private let apiKey = "sb_publishable_NVM2GcvxZFmf0VLNbaBr7A_y_8EMS97"

    private(set) var userID: String?
    private(set) var accessToken: String?
    private var refreshToken: String?

    /// Igual que `GmailAccessToken`/`GmailRefreshToken` en GmailAuthService:
    /// UserDefaults por simplicidad. Keychain sería lo correcto en producción.
    private enum Keys {
        static let userID = "supabaseUserID"
        static let accessToken = "supabaseAccessToken"
        static let refreshToken = "supabaseRefreshToken"
        static let displayName = "socialDisplayName"
    }

    var displayName: String? {
        get { UserDefaults.standard.string(forKey: Keys.displayName) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.displayName) }
    }

    var isReady: Bool { userID != nil && accessToken != nil }

    private init() {
        userID = UserDefaults.standard.string(forKey: Keys.userID)
        accessToken = UserDefaults.standard.string(forKey: Keys.accessToken)
        refreshToken = UserDefaults.standard.string(forKey: Keys.refreshToken)
    }

    /// Punto de entrada único: crea sesión si falta y guarda el perfil con
    /// `name`. Se llama al abrir la pestaña Amigos. `false` si Supabase
    /// rechazó la sesión anónima (probablemente no está activada en el panel).
    @discardableResult
    func ensureSession(defaultName: String) async -> Bool {
        if accessToken == nil {
            await signInAnonymously()
        }
        guard isReady else { return false }
        if displayName == nil {
            displayName = defaultName
        }
        if let name = displayName {
            await pushProfile(name: name)
        }
        return true
    }

    /// El usuario cambió su nombre (p. ej. desde un ajuste futuro). Vuelve a
    /// subirlo a `profiles` para que los amigos ya conectados lo vean.
    func updateDisplayName(_ name: String) async {
        displayName = name
        await pushProfile(name: name)
    }

    /// Nombre, estado y emoji de una vez: es lo que guarda el modal de perfil.
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
            accessToken = decoded.access_token
            refreshToken = decoded.refresh_token
            userID = decoded.user.id
            UserDefaults.standard.set(accessToken, forKey: Keys.accessToken)
            UserDefaults.standard.set(refreshToken, forKey: Keys.refreshToken)
            UserDefaults.standard.set(userID, forKey: Keys.userID)
        } catch {
            print("Amigos: error de red creando sesión anónima: \(error)")
        }
    }

    /// Upsert por `id` (clave primaria de `profiles`): crea la fila la primera
    /// vez, y la actualiza si el nombre cambió.
    private func pushProfile(name: String,
                            status: String? = nil,
                            avatarEmoji: String? = nil) async {
        let store = SocialProfileStore.shared
        let sentStatus = status ?? store.status
        let sentEmoji = avatarEmoji ?? store.avatarEmoji

        // Dos intentos como mucho: con los campos nuevos y, si el servidor no
        // los conoce todavía (falta correr el SQL), sólo con el nombre. Sin
        // esto, un proyecto sin migrar dejaría de guardar hasta el nombre.
        if supportsProfileExtras {
            let extended: [String: String] = [
                "id": "", "display_name": name,
                "status": sentStatus, "avatar_emoji": sentEmoji ?? ""
            ]
            if await postProfile(fields: extended, name: name) { return }
            supportsProfileExtras = false
            print("Amigos: `profiles` todavía no tiene `status`/`avatar_emoji`; se sube sólo el nombre.")
        }
        _ = await postProfile(fields: ["id": "", "display_name": name], name: name)
    }

    /// `true` si el servidor lo aceptó. `fields` llega sin `id` resuelto: lo
    /// pone aquí, que es donde se sabe que hay sesión.
    private func postProfile(fields: [String: String], name: String) async -> Bool {
        guard let userID, let accessToken else { return false }
        guard let url = URL(string: "\(projectURL)/rest/v1/profiles") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        var payload = fields
        payload["id"] = userID
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200...299).contains(http.statusCode)
        } catch {
            return false
        }
    }

    /// Base para que `FriendsManager` arme sus propias peticiones REST/RPC
    /// autenticadas, sin repetir las tres cabeceras en cada sitio.
    func authorizedRequest(url: URL, method: String) -> URLRequest? {
        guard let accessToken else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.addValue(apiKey, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    var baseURL: String { projectURL }
}
