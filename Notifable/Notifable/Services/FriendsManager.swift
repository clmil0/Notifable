import Foundation
import SwiftUI
import SwiftData

/// Un amigo conectado: su nombre, el estado que él escribió, y las notas
/// privadas que yo le puse (apodo, color, emoji), que salen de
/// `SocialProfileStore` y nunca del servidor. Nada financiero vive aquí — eso
/// es `FriendShareRow`.
struct Friend: Identifiable, Hashable {
    let id: String
    /// Como se llama él a sí mismo. Para lo que se enseña en pantalla usa
    /// `name`, que respeta el apodo.
    let displayName: String
    /// Su línea de estado, si el servidor ya la sirve.
    var status: String = ""
    /// Cuándo se hicieron amigos (`friendships.created_at`). `nil` si esa
    /// amistad viene de la caché local, de antes de que se empezara a pedir
    /// la columna.
    var friendSince: Date? = nil

    private var preferences: FriendPreferences { SocialProfileStore.shared.preferences(for: id) }

    /// Cómo lo llamo yo: el apodo si le puse uno.
    var name: String { SocialProfileStore.shared.name(for: id, realName: displayName) }

    var hasNickname: Bool {
        !preferences.nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var initial: String { SocialProfileStore.initial(of: name) }

    /// Emoji si lo eligió; si no, la inicial.
    var glyph: String { SocialProfileStore.shared.glyph(for: id, realName: displayName) }

    var usesEmoji: Bool { preferences.emoji?.isEmpty == false }

    /// El color elegido, o el de siempre derivado del id.
    var tint: Color { SocialProfileStore.shared.color(for: id) }
}

/// Una fila de `friend_shares`: lo que un amigo (`sharerID`) decidió mostrarle
/// a otro (`viewerID`) este mes. `categoryTotals` sólo trae las categorías que
/// el propio dueño marcó — el servidor nunca ve ni guarda las demás.
struct FriendShareRow: Identifiable, Codable, Hashable {
    let id: String
    let sharerID: String
    let viewerID: String
    let shareTotal: Bool
    let shareCategories: [String]
    let totalAmount: Double?
    let categoryTotals: [CategoryAmount]
    let viewerStatus: String
    let updatedAt: String

    struct CategoryAmount: Codable, Hashable {
        let name: String
        let amount: Double
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sharerID = "sharer_id"
        case viewerID = "viewer_id"
        case shareTotal = "share_total"
        case shareCategories = "share_categories"
        case totalAmount = "total_amount"
        case categoryTotals = "category_totals"
        case viewerStatus = "viewer_status"
        case updatedAt = "updated_at"
    }
}

/// Capa de red para Amigos: amistades, lo que te comparten, lo que compartes,
/// invitaciones. Todas las escrituras pasan por las funciones RPC del
/// esquema SQL (`redeem_invite_code`, `upsert_my_share`, `respond_to_share`,
/// `stop_sharing`) — nunca un INSERT/UPDATE directo, así el servidor decide
/// quién puede tocar qué, no el cliente.
///
/// `@MainActor`: sin esto, dos llamadas a `refresh()` casi simultáneas (el
/// `.task` inicial y un pull-to-refresh que se cruza, por ejemplo) podían
/// correr de verdad en paralelo en hilos distintos y las dos pasar el guard
/// de `startListeningForChanges` antes de que ninguna marcara
/// `isListeningForChanges` — eso abría dos conexiones de Realtime a la vez
/// (se veía en los logs: todo duplicado). Aislado al actor principal, esa
/// comprobación y esa asignación no pueden entrelazarse con otra llamada.
@MainActor
@Observable
final class FriendsManager {

    static let shared = FriendsManager()

    private let auth = SupabaseAuthManager.shared

    var friends: [Friend] = []
    /// Te comparten algo pero todavía no lo aceptaste (aparece bajo "Te quieren compartir").
    var pendingIncoming: [FriendShareRow] = []
    /// Ya aceptado: lo que ves de cada amigo este mes.
    var acceptedIncoming: [FriendShareRow] = []
    /// Lo que tú compartes con cada amigo este mes (una fila por amigo, si ya la tocaste).
    var outgoing: [FriendShareRow] = []
    var isLoading = false
    var lastErrorMessage: String?

    private var profileNames: [String: String] = [:]
    private var profileStatuses: [String: String] = [:]

    /// Sólo se arma una vez por sesión: no hace falta re-suscribirse en cada
    /// `refresh()` (pull-to-refresh, reabrir la pestaña...), sólo la primera
    /// vez que hay sesión.
    private var isListeningForChanges = false

    private var baseURL: String { auth.baseURL }

    private static var currentMonthKey: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-01"
        return f.string(from: Date())
    }

    // MARK: - Caché local

    private var container: ModelContainer?

    /// Se llama una sola vez, al arrancar la app. Pinta con lo último que se
    /// vio **antes** de que exista sesión o red — así Amigos no vuelve a
    /// empezar en blanco cada vez que se abre la app; sólo se actualiza con lo
    /// que llegue después, por `refresh()` o por Realtime.
    func configure(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container
        loadFromCache()
    }

    private func loadFromCache() {
        guard let container else { return }
        let context = ModelContext(container)

        if let cached = try? context.fetch(FetchDescriptor<CachedFriend>()), !cached.isEmpty {
            friends = cached.map { Friend(id: $0.id, displayName: $0.displayName, status: $0.status, friendSince: $0.friendSince) }
            for row in cached {
                profileNames[row.id] = row.displayName
                profileStatuses[row.id] = row.status
            }
        }

        guard let uid = auth.userID,
              let cachedShares = try? context.fetch(FetchDescriptor<CachedFriendShare>()) else { return }
        let rows = cachedShares.map { $0.asRow }
        let asViewer = rows.filter { $0.viewerID == uid }
        pendingIncoming = asViewer.filter { $0.viewerStatus == "pending" }
        acceptedIncoming = asViewer.filter { $0.viewerStatus == "accepted" }
        outgoing = rows.filter { $0.sharerID == uid }
    }

    /// Reemplaza la caché de amigos por `friends` tal como está ahora — el
    /// servidor manda, esto sólo recuerda su última respuesta. El que ya no
    /// aparece (amistad eliminada en otro dispositivo) se borra de aquí
    /// también, si no la próxima apertura seguiría mostrándolo.
    private func persistFriendsCache() {
        guard let container else { return }
        let context = ModelContext(container)
        let existing = (try? context.fetch(FetchDescriptor<CachedFriend>())) ?? []
        var stale = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for friend in friends {
            if let row = stale.removeValue(forKey: friend.id) {
                row.displayName = friend.displayName
                row.status = friend.status
                row.friendSince = friend.friendSince
            } else {
                context.insert(CachedFriend(id: friend.id, displayName: friend.displayName,
                                            status: friend.status, friendSince: friend.friendSince))
            }
        }
        for leftover in stale.values { context.delete(leftover) }
        try? context.save()
    }

    /// Igual que `persistFriendsCache()`, para las tres listas de compartidos
    /// juntas (son la misma tabla del servidor, sólo filtrada distinto).
    private func persistSharesCache() {
        guard let container else { return }
        let context = ModelContext(container)
        let existing = (try? context.fetch(FetchDescriptor<CachedFriendShare>())) ?? []
        var stale = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for row in pendingIncoming + acceptedIncoming + outgoing {
            if let cached = stale.removeValue(forKey: row.id) {
                cached.update(from: row)
            } else {
                context.insert(CachedFriendShare(row: row))
            }
        }
        for leftover in stale.values { context.delete(leftover) }
        try? context.save()
    }

    func refresh() async {
        guard auth.isReady else { return }
        isLoading = true
        defer { isLoading = false }
        await loadFriendships()
        await loadShares()
        await startListeningForChanges()
    }

    /// Escucha en vivo lo que cambia del lado de un amigo: si él canjea tu
    /// código, o si activa/edita lo que te comparte, esto llega solo — sin
    /// esperar a que el usuario haga pull-to-refresh. RLS ya filtra: sólo
    /// llegan filas donde este usuario es `user_a`/`user_b` (amistades) o
    /// `sharer_id`/`viewer_id` (compartidos).
    private func startListeningForChanges() async {
        guard !isListeningForChanges else { return }
        isListeningForChanges = true

        let realtime = SupabaseRealtimeClient.shared
        // `subscribe` no es async y devuelve el id de la suscripción: sin el
        // `_ =` el resultado queda sin usar, y el `await` sobraba.
        _ = realtime.subscribe(table: "friendships") { [weak self] _ in
            Task { await self?.loadFriendships() }
        }
        _ = realtime.subscribe(table: "friend_shares") { [weak self] _ in
            Task { await self?.loadShares() }
        }
    }

    // MARK: - Amistades

    private func loadFriendships() async {
        guard let uid = auth.userID else { return }
        guard let url = URL(string: "\(baseURL)/rest/v1/friendships?or=(user_a.eq.\(uid),user_b.eq.\(uid))&select=user_a,user_b,created_at") else { return }
        guard let request = auth.authorizedRequest(url: url, method: "GET") else { return }

        struct Row: Decodable { let user_a: String; let user_b: String; let created_at: String }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                lastErrorMessage = "No se pudieron cargar tus amigos."
                return
            }
            let rows = try JSONDecoder().decode([Row].self, from: data)
            let friendIDs = rows.map { $0.user_a == uid ? $0.user_b : $0.user_a }
            // "Amigos desde", en el perfil del amigo (`FriendProfileView`).
            var since: [String: Date] = [:]
            for row in rows {
                let friendID = row.user_a == uid ? row.user_b : row.user_a
                since[friendID] = ConfigBackupManager.parseDate(row.created_at)
            }
            var fetched = await fetchProfiles(ids: friendIDs)
            for index in fetched.indices { fetched[index].friendSince = since[fetched[index].id] }
            friends = fetched
            persistFriendsCache()
        } catch {
            lastErrorMessage = "No se pudieron cargar tus amigos."
        }
    }

    /// Dos formas de la misma consulta: con el estado, y sin él para un
    /// proyecto de Supabase al que todavía no se le ha corrido el SQL de las
    /// columnas nuevas. Sin el repliegue, no cargaría ni la lista de amigos.
    private func fetchProfiles(ids: [String]) async -> [Friend] {
        guard !ids.isEmpty else { return [] }
        if let friends = await fetchProfiles(ids: ids, includingStatus: true) { return friends }
        return await fetchProfiles(ids: ids, includingStatus: false) ?? []
    }

    private func fetchProfiles(ids: [String], includingStatus: Bool) async -> [Friend]? {
        let list = ids.joined(separator: ",")
        let columns = includingStatus ? "id,display_name,status" : "id,display_name"
        guard let url = URL(string: "\(baseURL)/rest/v1/profiles?id=in.(\(list))&select=\(columns)") else { return nil }
        guard let request = auth.authorizedRequest(url: url, method: "GET") else { return nil }

        struct Row: Decodable {
            let id: String
            let display_name: String
            let status: String?
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            let rows = try JSONDecoder().decode([Row].self, from: data)
            for row in rows {
                profileNames[row.id] = row.display_name
                profileStatuses[row.id] = row.status ?? ""
            }
            return rows.map { Friend(id: $0.id, displayName: $0.display_name, status: $0.status ?? "") }
        } catch {
            return nil
        }
    }

    /// El nombre real, tal como él lo escribió.
    func name(for id: String) -> String { profileNames[id] ?? "Amigo" }

    /// Cómo lo veo yo: el apodo que le puse, o su nombre.
    func displayName(for id: String) -> String {
        SocialProfileStore.shared.name(for: id, realName: name(for: id))
    }

    func status(for id: String) -> String { profileStatuses[id] ?? "" }

    func friend(with id: String) -> Friend {
        friends.first { $0.id == id }
            ?? Friend(id: id, displayName: name(for: id), status: status(for: id))
    }

    // MARK: - Compartidos

    private func loadShares() async {
        guard let uid = auth.userID else { return }
        let month = Self.currentMonthKey

        var touched = false
        if let asViewer = await fetchShares(query: "viewer_id=eq.\(uid)&period_month=eq.\(month)") {
            pendingIncoming = asViewer.filter { $0.viewerStatus == "pending" }
            acceptedIncoming = asViewer.filter { $0.viewerStatus == "accepted" }
            touched = true
        }
        if let asSharer = await fetchShares(query: "sharer_id=eq.\(uid)&period_month=eq.\(month)") {
            outgoing = asSharer
            touched = true
        }
        // Sólo si al menos una de las dos llamadas trajo algo de verdad: si
        // ambas fallaron (sin red, por ejemplo), no hay nada nuevo que
        // guardar y lo de la caché sigue siendo lo último confiable.
        if touched { persistSharesCache() }
    }

    private func fetchShares(query: String) async -> [FriendShareRow]? {
        guard let url = URL(string: "\(baseURL)/rest/v1/friend_shares?\(query)") else { return nil }
        guard let request = auth.authorizedRequest(url: url, method: "GET") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            return try JSONDecoder().decode([FriendShareRow].self, from: data)
        } catch {
            return nil
        }
    }

    /// Mi fila de salida hacia un amigo puntual, si ya la toqué este mes.
    func myShare(toward friendID: String) -> FriendShareRow? {
        outgoing.first { $0.viewerID == friendID }
    }

    // MARK: - Invitaciones

    /// El código fijo de esta cuenta: uno solo por persona, no expira, y
    /// cualquier cantidad de amigos puede usarlo para agregarte (ver
    /// `agrupay_friends_v3_schema.sql`). El backend ya lo crea solo al crear
    /// el perfil (trigger); el `POST` de aquí es sólo el respaldo defensivo
    /// para una cuenta de antes de esa migración que todavía no tiene fila.
    func myFriendCode() async -> String? {
        guard let uid = auth.userID else { return nil }
        if let code = await fetchMyFriendCode(uid: uid) { return code }

        guard let url = URL(string: "\(baseURL)/rest/v1/friend_codes") else { return nil }
        guard var request = auth.authorizedRequest(url: url, method: "POST") else { return nil }
        request.addValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["owner_id": uid])

        struct Row: Decodable { let code: String }
        if let (data, response) = try? await URLSession.shared.data(for: request),
           let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
           let rows = try? JSONDecoder().decode([Row].self, from: data) {
            return rows.first?.code
        }
        // Si el POST falló porque otra llamada la creó justo antes (carrera
        // improbable, pero posible), la fila ya existe: se busca de nuevo en
        // vez de darlo por perdido.
        return await fetchMyFriendCode(uid: uid)
    }

    private func fetchMyFriendCode(uid: String) async -> String? {
        guard let url = URL(string: "\(baseURL)/rest/v1/friend_codes?owner_id=eq.\(uid)&select=code") else { return nil }
        guard let request = auth.authorizedRequest(url: url, method: "GET") else { return nil }

        struct Row: Decodable { let code: String }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let rows = try? JSONDecoder().decode([Row].self, from: data) else { return nil }
        return rows.first?.code
    }

    /// Canjea el código de un amigo: crea la amistad si es válido y devuelve
    /// el perfil de quien lo generó — la función RPC ya lo trae, así que no
    /// hace falta adivinar cuál es "el nuevo" comparando listas antes/después.
    @discardableResult
    func redeem(code: String) async -> Friend? {
        guard let url = URL(string: "\(baseURL)/rest/v1/rpc/redeem_invite_code") else { return nil }
        guard var request = auth.authorizedRequest(url: url, method: "POST") else { return nil }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["p_code": code])

        struct OwnerProfile: Decodable {
            let id: String
            let display_name: String
            let status: String?
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                lastErrorMessage = "Código inválido."
                return nil
            }
            let profile = try JSONDecoder().decode(OwnerProfile.self, from: data)
            profileNames[profile.id] = profile.display_name
            profileStatuses[profile.id] = profile.status ?? ""
            await refresh()
            return Friend(id: profile.id, displayName: profile.display_name, status: profile.status ?? "")
        } catch {
            lastErrorMessage = "No se pudo canjear el código."
            return nil
        }
    }

    // MARK: - Permisos

    /// El amigo aceptó ver lo que le compartes (mueve la fila de "pendiente" a "aceptado").
    func accept(sharerID: String) async {
        await respond(sharerID: sharerID, status: "accepted")
    }

    func ignore(sharerID: String) async {
        await respond(sharerID: sharerID, status: "ignored")
    }

    private func respond(sharerID: String, status: String) async {
        guard let url = URL(string: "\(baseURL)/rest/v1/rpc/respond_to_share") else { return }
        guard var request = auth.authorizedRequest(url: url, method: "POST") else { return }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["p_sharer_id": sharerID, "p_status": status])
        _ = try? await URLSession.shared.data(for: request)
        await loadShares()
    }

    /// Fija qué le muestro a un amigo este mes. `shareTotal`/`categories` deciden
    /// qué llega al servidor — lo que no está marcado nunca sale del teléfono.
    func setShare(viewerID: String,
                  shareTotal: Bool,
                  categories: [String],
                  totalAmount: Double,
                  categoryTotals: [FriendShareRow.CategoryAmount]) async {
        guard let url = URL(string: "\(baseURL)/rest/v1/rpc/upsert_my_share") else { return }
        guard var request = auth.authorizedRequest(url: url, method: "POST") else { return }

        // `totalAmount`/`categoryTotals` llegan de sumar `Double` en
        // `PeriodTotals` — con suficientes movimientos arrastran el error de
        // punto flotante de siempre (ver `Money.swift`). Sin normalizar aquí,
        // ese "4066.4000000000001" viajaba tal cual al `numeric` de Supabase,
        // que sólo guarda lo que le llega, no lo corrige.
        let sentTotal = shareTotal ? Money.normalized(totalAmount) : nil
        let sentCategories = categoryTotals.filter { categories.contains($0.name) }
        let categoryPayload = sentCategories.map { ["name": $0.name, "amount": Money.normalized($0.amount)] as [String: Any] }

        var payload: [String: Any] = [
            "p_viewer_id": viewerID,
            "p_share_total": shareTotal,
            "p_share_categories": categories,
            "p_category_totals": categoryPayload
        ]
        if let sentTotal { payload["p_total_amount"] = sentTotal } else { payload["p_total_amount"] = NSNull() }

        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        _ = try? await URLSession.shared.data(for: request)
        // El respaldo de configuración no lleva `friend_shares` —esa tabla se
        // reescribe cada mes y vive en el servidor—, así que lo elegido se
        // anota también aquí: es lo que devuelve "a Camila le compartías el
        // total y dos categorías" al estrenar teléfono.
        SocialProfileStore.shared.rememberShare(friendID: viewerID,
                                                shareTotal: shareTotal,
                                                categories: categories)
        await loadShares()
    }

    /// Elimina la amistad de los dos lados. Necesita la función
    /// `delete_friendship` en Supabase: borrar directo por REST lo impediría la
    /// política RLS, y debe borrar también las filas de `friend_shares` de ida
    /// y de vuelta. Si el proyecto todavía no la tiene, no se toca nada local y
    /// se dice por qué.
    @discardableResult
    func removeFriend(_ friendID: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/rest/v1/rpc/delete_friendship") else { return false }
        guard var request = auth.authorizedRequest(url: url, method: "POST") else { return false }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["p_friend_id": friendID])
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                lastErrorMessage = "Falta la función `delete_friendship` en Supabase."
                return false
            }
            SocialProfileStore.shared.forget(friendID: friendID)
            await refresh()
            return true
        } catch {
            lastErrorMessage = "No se pudo eliminar la amistad."
            return false
        }
    }

    /// Deja de compartir con un amigo puntual este mes.
    func stopSharing(viewerID: String) async {
        guard let url = URL(string: "\(baseURL)/rest/v1/rpc/stop_sharing") else { return }
        guard var request = auth.authorizedRequest(url: url, method: "POST") else { return }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["p_viewer_id": viewerID])
        _ = try? await URLSession.shared.data(for: request)
        SocialProfileStore.shared.forgetShare(friendID: viewerID)
        await loadShares()
    }
}
