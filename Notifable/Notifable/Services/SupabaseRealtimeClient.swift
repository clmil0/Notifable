import Foundation

/// Cliente mínimo de Supabase Realtime (Phoenix Channels sobre WebSocket),
/// hecho a mano con `URLSessionWebSocketTask` — el proyecto no usa el SDK de
/// Supabase en ningún lado (todo es REST/RPC directo por `URLSession`, ver
/// `FriendsManager`/`SupabaseAuthManager`/`ConfigBackupManager`), así que esto
/// sigue la misma línea en vez de sumar una dependencia sólo para esto.
///
/// Sólo hace lo que Amigos necesita: escuchar INSERT/UPDATE/DELETE de
/// Postgres en una tabla y avisar. No hay Presence ni Broadcast, y no hace
/// falta filtrar por usuario a mano — RLS ya decide qué fila le llega a quién
/// a partir del JWT que se manda al unirse al canal, igual que en cada
/// petición REST de este proyecto.
///
/// Requisito del lado de Supabase (una vez, en el SQL Editor):
///   alter publication supabase_realtime add table public.friendships, public.friend_shares;
/// Activarlo sólo desde el toggle del dashboard hace lo mismo por debajo;
/// si el toggle no estuviera disponible, ese `alter publication` es la forma
/// directa de conseguirlo.
/// `@MainActor` a propósito: todo lo que toca (`subscriptions`, `task`,
/// `joinedTables`...) se muta tanto desde quien llama `subscribe` como desde
/// los bucles internos de heartbeat/recepción, y sin aislarlo en un mismo
/// actor esas mutaciones podrían pisarse entre hilos. Un `Task {}` creado
/// aquí dentro hereda este aislamiento, así que los bucles internos siguen
/// corriendo en el actor principal sin bloquear la UI (las únicas esperas
/// reales son `Task.sleep` y `task.receive()`, ambas suspensiones, no bloqueos).
@MainActor
final class SupabaseRealtimeClient {

    static let shared = SupabaseRealtimeClient()

    struct Change {
        let table: String
        /// "INSERT" | "UPDATE" | "DELETE"
        let eventType: String
        /// Fila nueva (INSERT/UPDATE) o vacía (DELETE, donde lo único que
        /// manda Postgres es `old`).
        let record: [String: Any]
        let oldRecord: [String: Any]?
    }

    private struct Subscription {
        let id = UUID()
        let table: String
        let handler: (Change) -> Void
    }

    private let projectRef = "zjzzqaeusmxmtszgdncl"
    private let apiKey = "sb_publishable_NVM2GcvxZFmf0VLNbaBr7A_y_8EMS97"

    /// 30s es el default de `realtime-js`; unos segundos menos deja margen
    /// antes de que algún proxy de por medio corte la conexión por inactividad.
    private let heartbeatInterval: UInt64 = 25_000_000_000

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var subscriptions: [Subscription] = []
    private var joinedTables: Set<String> = []
    private var refCounter = 0
    private var heartbeatTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var isConnecting = false

    private init() {}

    // MARK: - API pública

    /// Escucha cambios en `public.<table>`. Se puede llamar varias veces para
    /// la misma tabla (varios listeners) o para tablas distintas: comparten
    /// una única conexión de socket.
    @discardableResult
    func subscribe(table: String, onChange: @escaping (Change) -> Void) -> UUID {
        let sub = Subscription(table: table, handler: onChange)
        subscriptions.append(sub)
        Task { await self.connectAndJoin(table: table) }
        return sub.id
    }

    func unsubscribe(_ id: UUID) {
        subscriptions.removeAll { $0.id == id }
    }

    private func connectAndJoin(table: String) async {
        await connectIfNeeded()
        if !joinedTables.contains(table) {
            await joinChannel(table: table)
        }
    }

    // MARK: - Conexión

    private func connectIfNeeded() async {
        guard task == nil, !isConnecting else { return }
        // Se marca ANTES del primer `await`: dos llamadas casi simultáneas
        // (dos `subscribe` seguidos, cada uno con su propio `Task`) pueden
        // entrelazarse en la pausa de `validAccessToken()`, y si el flag se
        // pone después de esa espera, las dos pasan el guard de arriba y se
        // abren dos sockets — que es exactamente lo que se veía en los logs
        // (todo duplicado, canal unido dos veces).
        isConnecting = true
        defer { isConnecting = false }

        guard await SupabaseAuthManager.shared.validAccessToken() != nil else {
            print("SupabaseRealtimeClient: sin sesión de Supabase todavía, no se conecta.")
            return
        }
        guard let url = URL(string: "wss://\(projectRef).supabase.co/realtime/v1/websocket?apikey=\(apiKey)&vsn=1.0.0") else { return }

        print("SupabaseRealtimeClient: conectando…")
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        self.session = session
        self.task = task
        task.resume()

        startReceiving()
        startHeartbeat()

        // Reafirma todos los canales que ya tenían oyentes: hace falta tanto
        // en la primera conexión como al reconectar tras un corte.
        joinedTables.removeAll()
        for table in Set(subscriptions.map(\.table)) {
            await joinChannel(table: table)
        }
    }

    private func joinChannel(table: String) async {
        guard let token = await SupabaseAuthManager.shared.validAccessToken() else { return }
        refCounter += 1
        print("SupabaseRealtimeClient: uniéndome al canal de \(table)…")
        send([
            "topic": "realtime:public:\(table)",
            "event": "phx_join",
            "payload": [
                "config": [
                    "postgres_changes": [
                        ["event": "*", "schema": "public", "table": table]
                    ]
                ],
                "access_token": token
            ],
            "ref": "\(refCounter)"
        ])
        joinedTables.insert(table)
    }

    private func send(_ object: [String: Any]) {
        guard let task,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { error in
            if let error {
                print("SupabaseRealtimeClient: error mandando mensaje: \(error)")
            }
        }
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self?.heartbeatInterval ?? 25_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.refCounter += 1
                self.send(["topic": "phoenix", "event": "heartbeat", "payload": [:], "ref": "\(self.refCounter)"])
            }
        }
    }

    private func startReceiving() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let task = self.task else { return }
                do {
                    let message = try await task.receive()
                    self.handle(message)
                } catch {
                    // El socket se cayó (red, backgrounding, el servidor lo
                    // cerró): se limpia y se reintenta con un respiro corto,
                    // no en bucle cerrado.
                    print("SupabaseRealtimeClient: se cortó el socket (\(error.localizedDescription)), reintentando…")
                    self.teardown()
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    guard !Task.isCancelled else { return }
                    await self.connectIfNeeded()
                    return
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?
        switch message {
        case .data(let d): data = d
        case .string(let s): data = s.data(using: .utf8)
        @unknown default: data = nil
        }
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = json["event"] as? String else {
            if case .string(let raw) = message {
                print("SupabaseRealtimeClient: mensaje que no pude interpretar como JSON: \(raw)")
            }
            return
        }

        if event == "phx_reply", let payload = json["payload"] as? [String: Any] {
            let status = payload["status"] as? String
            if status == "error" {
                print("SupabaseRealtimeClient: el servidor rechazó la unión al canal: \(payload)")
            } else {
                print("SupabaseRealtimeClient: canal confirmado (\(json["topic"] ?? "?")): \(payload)")
            }
            return
        }
        if event == "phx_close" || event == "phx_error" {
            print("SupabaseRealtimeClient: el servidor cerró el canal \(json["topic"] ?? "?"): \(json)")
            // El socket puede seguir vivo aunque este canal se haya cerrado
            // (pasaba justo al haber dos uniones duplicadas al mismo canal,
            // ver `connectIfNeeded`): sacarlo de `joinedTables` para que la
            // próxima vez que alguien llame `subscribe` de esa tabla se
            // vuelva a unir, en vez de darla por unida para siempre.
            if let topic = json["topic"] as? String {
                let table = topic.replacingOccurrences(of: "realtime:public:", with: "")
                joinedTables.remove(table)
            }
            return
        }
        if event == "system" {
            // Confirmación informativa de Postgres ("Subscribed to
            // PostgreSQL"), no hace falta hacer nada con ella.
            return
        }

        guard event == "postgres_changes" else {
            print("SupabaseRealtimeClient: evento sin manejar '\(event)': \(json)")
            return
        }
        guard let payload = json["payload"] as? [String: Any],
              let changeData = payload["data"] as? [String: Any],
              let table = changeData["table"] as? String,
              // Supabase manda `type` (y la fila en `record`/`old_record`);
              // se acepta también `eventType`/`new`/`old` por si algún
              // proyecto corre una versión de Realtime que use esos nombres.
              let eventType = (changeData["type"] as? String) ?? (changeData["eventType"] as? String) else {
            print("SupabaseRealtimeClient: postgres_changes con forma inesperada: \(json)")
            return
        }

        let change = Change(table: table,
                            eventType: eventType,
                            record: (changeData["record"] as? [String: Any]) ?? (changeData["new"] as? [String: Any]) ?? [:],
                            oldRecord: (changeData["old_record"] as? [String: Any]) ?? (changeData["old"] as? [String: Any]))

        let matching = subscriptions.filter { $0.table == table }
        print("SupabaseRealtimeClient: \(eventType) en \(table) — \(matching.count) oyente(s).")
        for sub in matching {
            sub.handler(change)
        }
    }

    private func teardown() {
        heartbeatTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session = nil
        joinedTables.removeAll()
    }
}
