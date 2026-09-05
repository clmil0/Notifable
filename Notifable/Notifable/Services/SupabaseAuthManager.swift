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
    private func pushProfile(name: String) async {
        guard let userID, let accessToken else { return }
        guard let url = URL(string: "\(projectURL)/rest/v1/profiles") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        let payload: [String: String] = ["id": userID, "display_name": name]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        _ = try? await URLSession.shared.data(for: request)
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
