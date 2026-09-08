import Foundation
import Network

/// Cliente IMAP mínimo, sólo de lectura.
///
/// Existe porque **Apple no publica ninguna API de iCloud Mail**: no hay
/// equivalente a la API de Gmail ni OAuth para el buzón. La única vía es IMAP
/// con una contraseña específica de aplicación. Ver `ICloudMailAccount`.
///
/// Hace exactamente lo que hace falta para leer avisos de banco y nada más:
/// `LOGIN`, `EXAMINE`, `UID SEARCH`, `UID FETCH`, `LOGOUT`. Dos decisiones que
/// garantizan que el buzón del usuario **no se toca**:
///
/// - `EXAMINE` en vez de `SELECT`: abre el buzón en sólo lectura, así que
///   ninguna orden puede modificarlo aunque se colara un error.
/// - `BODY.PEEK[]` en vez de `BODY[]`: leer un correo no lo marca como leído.
///   Con `BODY[]` la app le dejaría el buzón marcado al usuario.
actor IMAPClient {

    enum Failure: LocalizedError, Equatable {
        case connectionFailed(String)
        case authenticationFailed
        case commandFailed(String)
        case timedOut
        case notConnected

        var errorDescription: String? {
            switch self {
            case .connectionFailed(let detail):
                return "No se pudo conectar con el servidor de correo. \(detail)"
            case .authenticationFailed:
                return "iCloud rechazó el usuario o la contraseña específica."
            case .commandFailed(let detail):
                return "El servidor respondió con un error: \(detail)"
            case .timedOut:
                return "El servidor no respondió a tiempo."
            case .notConnected:
                return "No hay conexión con el servidor."
            }
        }
    }

    struct Configuration {
        var host: String
        var port: UInt16
        /// Segundos que se espera a una respuesta antes de abandonar.
        var timeout: TimeInterval

        static let iCloud = Configuration(host: "imap.mail.me.com", port: 993, timeout: 30)
    }

    private let configuration: Configuration
    private var connection: NWConnection?
    /// Lo recibido y aún no consumido. IMAP no respeta los límites de los
    /// paquetes: una respuesta puede llegar partida en tres lecturas, y dos
    /// respuestas cortas pueden llegar juntas en una.
    private var buffer = Data()
    private var tagCounter = 0

    init(configuration: Configuration = .iCloud) {
        self.configuration = configuration
    }

    // MARK: - Conexión

    func connect() async throws {
        guard connection == nil else { return }

        let parameters = NWParameters(tls: .init(), tcp: .init())
        let endpoint = NWEndpoint.hostPort(host: .init(configuration.host),
                                           port: .init(rawValue: configuration.port)!)
        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // `hasResumed` porque `stateUpdateHandler` puede emitir más de un
            // estado terminal y reanudar dos veces una continuación es un crash.
            var hasResumed = false
            connection.stateUpdateHandler = { state in
                guard !hasResumed else { return }
                switch state {
                case .ready:
                    hasResumed = true
                    continuation.resume()
                case .failed(let error):
                    hasResumed = true
                    continuation.resume(throwing: Failure.connectionFailed(error.localizedDescription))
                case .cancelled:
                    hasResumed = true
                    continuation.resume(throwing: Failure.connectionFailed("Conexión cancelada."))
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }

        // El saludo del servidor ("* OK ...") llega solo, sin pedirlo.
        _ = try await readUntagged()
    }

    func disconnect() async {
        if connection != nil {
            _ = try? await send("LOGOUT")
        }
        connection?.cancel()
        connection = nil
        buffer.removeAll()
    }

    // MARK: - Órdenes

    func login(user: String, password: String) async throws {
        do {
            _ = try await send("LOGIN \(quoted(user)) \(quoted(password))")
        } catch Failure.commandFailed {
            // Un LOGIN rechazado no es un fallo cualquiera: es la contraseña.
            throw Failure.authenticationFailed
        }
    }

    /// Abre un buzón en **sólo lectura**.
    func examine(mailbox: String = "INBOX") async throws {
        _ = try await send("EXAMINE \(quoted(mailbox))")
    }

    /// UIDs de los correos de un remitente desde una fecha.
    ///
    /// Una búsqueda por remitente en vez de una sola con todos: IMAP compone
    /// varios `FROM` con un `OR` prefijo que hay que anidar en árbol, y una
    /// expresión mal anidada la rechaza el servidor entero — con lo que no
    /// llegaría ningún correo de ningún banco. Así, un remitente que falle sólo
    /// se pierde a sí mismo, y de paso se puede informar del avance por banco.
    func searchUIDs(from sender: String, since: Date) async throws -> [UInt32] {
        let response = try await send("UID SEARCH SINCE \(Self.imapDate(since)) FROM \(quoted(sender))")

        // "* SEARCH 12 34 56"
        for line in response.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.uppercased().hasPrefix("* SEARCH") else { continue }
            return trimmed.dropFirst("* SEARCH".count)
                .components(separatedBy: .whitespaces)
                .compactMap { UInt32($0) }
        }
        return []
    }

    /// El mensaje completo, sin marcarlo como leído.
    func fetchMessage(uid: UInt32) async throws -> Data {
        let response = try await sendRaw("UID FETCH \(uid) BODY.PEEK[]")
        return Self.extractLiteral(from: response)
    }

    // MARK: - Protocolo

    private func nextTag() -> String {
        tagCounter += 1
        return String(format: "A%04d", tagCounter)
    }

    @discardableResult
    private func send(_ command: String) async throws -> String {
        String(decoding: try await sendRaw(command), as: UTF8.self)
    }

    /// Se devuelven bytes y no `String` porque el cuerpo de un correo puede no
    /// ser UTF-8 válido; decodificarlo aquí lo destrozaría antes de que
    /// `MIMEDecoder` pueda mirar su `charset`.
    private func sendRaw(_ command: String) async throws -> Data {
        guard let connection else { throw Failure.notConnected }

        let tag = nextTag()
        let line = "\(tag) \(command)\r\n"

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: Data(line.utf8), completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: Failure.connectionFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }

        return try await readResponse(tag: tag)
    }

    /// Lee hasta la línea etiquetada que cierra la orden.
    private func readResponse(tag: String) async throws -> Data {
        let deadline = Date().addingTimeInterval(configuration.timeout)

        while true {
            if let result = Self.completedResponse(in: buffer, tag: tag) {
                buffer.removeSubrange(..<result.consumed)
                guard result.isOK else {
                    throw Failure.commandFailed(result.detail)
                }
                return result.payload
            }
            guard Date() < deadline else { throw Failure.timedOut }
            try await readMore()
        }
    }

    /// El saludo inicial: una línea sin etiqueta.
    private func readUntagged() async throws -> String {
        let deadline = Date().addingTimeInterval(configuration.timeout)
        while true {
            if let range = buffer.range(of: Data("\r\n".utf8)) {
                let line = String(decoding: buffer[..<range.lowerBound], as: UTF8.self)
                buffer.removeSubrange(..<range.upperBound)
                return line
            }
            guard Date() < deadline else { throw Failure.timedOut }
            try await readMore()
        }
    }

    private func readMore() async throws {
        guard let connection else { throw Failure.notConnected }

        let chunk: Data = try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: Failure.connectionFailed(error.localizedDescription))
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: Failure.connectionFailed("El servidor cerró la conexión."))
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
        buffer.append(chunk)
    }

    // MARK: - Lectura de respuestas (puro, para poder probarlo)

    struct ParsedResponse {
        /// Todo lo recibido para esta orden, cierre incluido.
        var payload: Data
        var isOK: Bool
        var detail: String
        /// Cuántos bytes del buffer consume.
        var consumed: Int
    }

    /// Busca la línea `TAG OK|NO|BAD` que cierra una orden, **saltándose los
    /// literales**.
    ///
    /// Un literal es `{1234}` al final de una línea seguido de exactamente esos
    /// bytes, que son datos crudos y pueden contener cualquier cosa —incluida
    /// una línea que parezca una respuesta etiquetada—. Recorrer el buffer línea
    /// a línea sin saltarlos haría que un correo que mencione "A0002 OK" cortara
    /// la respuesta por la mitad.
    static func completedResponse(in buffer: Data, tag: String) -> ParsedResponse? {
        let bytes = [UInt8](buffer)
        let tagBytes = [UInt8]("\(tag) ".utf8)
        var cursor = 0

        while cursor < bytes.count {
            guard let lineEnd = lineEnd(in: bytes, from: cursor) else { return nil }
            let line = Array(bytes[cursor..<lineEnd.contentEnd])

            // ¿Esta línea abre un literal?
            if let size = literalSize(in: line) {
                let literalStart = lineEnd.next
                let literalEnd = literalStart + size
                guard literalEnd <= bytes.count else { return nil }   // aún no ha llegado entero
                cursor = literalEnd
                continue
            }

            if line.count >= tagBytes.count, Array(line[..<tagBytes.count]) == tagBytes {
                let rest = String(decoding: line[tagBytes.count...], as: UTF8.self)
                    .trimmingCharacters(in: .whitespaces)
                let status = rest.components(separatedBy: " ").first?.uppercased() ?? ""
                return ParsedResponse(
                    payload: Data(bytes[..<lineEnd.contentEnd]),
                    isOK: status == "OK",
                    detail: rest,
                    consumed: lineEnd.next
                )
            }
            cursor = lineEnd.next
        }
        return nil
    }

    /// `{1234}` al final de la línea. `{1234+}` es la variante no sincronizada.
    static func literalSize(in line: [UInt8]) -> Int? {
        guard line.last == UInt8(ascii: "}") else { return nil }
        guard let open = line.lastIndex(of: UInt8(ascii: "{")) else { return nil }
        var digits = String(decoding: line[(open + 1)..<(line.count - 1)], as: UTF8.self)
        if digits.hasSuffix("+") { digits.removeLast() }
        return Int(digits)
    }

    private static func lineEnd(in bytes: [UInt8], from start: Int) -> (contentEnd: Int, next: Int)? {
        var index = start
        while index < bytes.count {
            if bytes[index] == 10 {                                    // \n
                let contentEnd = (index > start && bytes[index - 1] == 13) ? index - 1 : index
                return (contentEnd, index + 1)
            }
            index += 1
        }
        return nil
    }

    /// Saca el contenido del literal de una respuesta a `FETCH`.
    ///
    /// La respuesta es `* 1 FETCH (UID 5 BODY[] {2048}\r\n<2048 bytes>)\r\n…`.
    /// Lo que interesa son esos bytes exactos, no la línea que los anuncia.
    static func extractLiteral(from response: Data) -> Data {
        let bytes = [UInt8](response)
        var cursor = 0

        while cursor < bytes.count {
            guard let line = lineEnd(in: bytes, from: cursor) else { break }
            if let size = literalSize(in: Array(bytes[cursor..<line.contentEnd])) {
                let start = line.next
                let end = min(start + size, bytes.count)
                return Data(bytes[start..<end])
            }
            cursor = line.next
        }
        return Data()
    }

    // MARK: - Formato

    /// IMAP quiere las fechas como `01-Jan-2026`, en inglés y sin depender del
    /// idioma del teléfono.
    static func imapDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd-MMM-yyyy"
        return formatter.string(from: date)
    }

    /// Una cadena IMAP entre comillas, con `\` y `"` escapados. Sin esto, una
    /// contraseña con comillas rompería la orden — y peor, podría inyectar otra.
    private func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
