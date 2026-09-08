import Foundation

/// Convierte un correo crudo (RFC 822, tal como llega por IMAP) en el texto
/// plano que esperan los parsers de banco.
///
/// Gmail entrega el correo ya troceado en JSON, con cada parte por separado y
/// su `data` en base64url. IMAP no: entrega el mensaje entero, cabeceras
/// incluidas, y hay que abrirlo aquí — separar las partes por su `boundary`,
/// deshacer el `Content-Transfer-Encoding` y traducir el juego de caracteres.
///
/// Se queda a propósito en lo que un aviso de banco necesita: `multipart/*`,
/// `base64`, `quoted-printable`, y las codificaciones que usan los bancos
/// peruanos (UTF-8 y Latin-1). No pretende ser un cliente de correo.
enum MIMEDecoder {

    /// Un correo ya abierto: lo que hace falta para decidir si interesa y para
    /// parsearlo.
    struct Message {
        var from: String
        var subject: String
        var date: Date?
        /// Texto legible, con el HTML ya quitado si sólo venía en HTML.
        var text: String
    }

    // MARK: - Entrada

    static func parse(raw: Data) -> Message {
        let (headerBlock, bodyData) = splitHeadersAndBody(raw)
        let headers = parseHeaders(headerBlock)

        return Message(
            from: decodeEncodedWords(headers["from"] ?? ""),
            subject: decodeEncodedWords(headers["subject"] ?? ""),
            date: headers["date"].flatMap(parseDate),
            text: text(body: bodyData, headers: headers)
        )
    }

    // MARK: - Cabeceras

    /// Cabeceras y cuerpo se separan por la primera línea en blanco. Se busca
    /// sobre bytes y no sobre `String`: un correo con una parte binaria puede
    /// no ser UTF-8 válido entero, y decodificarlo antes de trocearlo lo
    /// convertiría en `nil`.
    private static func splitHeadersAndBody(_ raw: Data) -> (String, Data) {
        let separators: [[UInt8]] = [[13, 10, 13, 10], [10, 10]]   // \r\n\r\n y \n\n
        let bytes = [UInt8](raw)

        for separator in separators {
            if let range = firstRange(of: separator, in: bytes) {
                let header = String(decoding: bytes[..<range.lowerBound], as: UTF8.self)
                let body = Data(bytes[range.upperBound...])
                return (header, body)
            }
        }
        return (String(decoding: bytes, as: UTF8.self), Data())
    }

    private static func firstRange(of pattern: [UInt8], in bytes: [UInt8]) -> Range<Int>? {
        guard !pattern.isEmpty, bytes.count >= pattern.count else { return nil }
        for start in 0...(bytes.count - pattern.count)
        where Array(bytes[start..<(start + pattern.count)]) == pattern {
            return start..<(start + pattern.count)
        }
        return nil
    }

    /// Nombres en minúscula y valores con las continuaciones ya unidas: una
    /// cabecera larga se parte en varias líneas, y la siguiente empieza por
    /// espacio o tabulador. Sin unirlas, un `boundary` largo se cortaría.
    static func parseHeaders(_ block: String) -> [String: String] {
        var headers: [String: String] = [:]
        var currentName: String?
        var currentValue = ""

        func flush() {
            if let name = currentName {
                headers[name] = currentValue.trimmingCharacters(in: .whitespaces)
            }
            currentName = nil
            currentValue = ""
        }

        for line in block.components(separatedBy: .newlines) {
            // `CharacterSet.newlines` trabaja sobre escalares, así que un
            // "\r\n" produce una línea vacía de más. Tratarla como final de
            // cabecera cortaba la continuación: un `boundary` en la línea
            // siguiente se perdía, y sin `boundary` un multipart se queda sin
            // texto — el correo entero llegaba vacío al parser.
            if line.isEmpty { continue }

            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                currentValue += " " + line.trimmingCharacters(in: .whitespaces)
                continue
            }
            flush()
            guard let colon = line.firstIndex(of: ":") else { continue }
            currentName = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            currentValue = String(line[line.index(after: colon)...])
        }
        flush()
        return headers
    }

    /// Un parámetro de una cabecera: `charset` en `Content-Type: text/html;
    /// charset="utf-8"`. Acepta el valor con y sin comillas.
    static func parameter(_ name: String, in header: String) -> String? {
        let lower = header.lowercased()
        guard let nameRange = lower.range(of: name.lowercased() + "=") else { return nil }
        var rest = header[nameRange.upperBound...].trimmingCharacters(in: .whitespaces)

        if rest.hasPrefix("\"") {
            rest.removeFirst()
            guard let end = rest.firstIndex(of: "\"") else { return nil }
            return String(rest[..<end])
        }
        let end = rest.firstIndex(where: { $0 == ";" || $0 == " " }) ?? rest.endIndex
        return String(rest[..<end])
    }

    // MARK: - Cuerpo

    private static func text(body: Data, headers: [String: String]) -> String {
        let contentType = headers["content-type"] ?? "text/plain"
        let encoding = (headers["content-transfer-encoding"] ?? "").trimmingCharacters(in: .whitespaces)

        // Un multipart no tiene texto propio: hay que bajar a sus partes.
        if contentType.lowercased().contains("multipart/"),
           let boundary = parameter("boundary", in: contentType) {
            return textFromParts(body: body, boundary: boundary)
        }

        let decoded = decodeBody(body, transferEncoding: encoding,
                                 charset: parameter("charset", in: contentType))
        return contentType.lowercased().contains("text/html") ? stripHTML(decoded) : decoded
    }

    /// Recorre las partes de un `multipart`. Se prefiere `text/plain`; el HTML
    /// es el respaldo, porque limpiarlo siempre pierde algo. En un
    /// `multipart/alternative` el banco manda las dos versiones del mismo aviso.
    private static func textFromParts(body: Data, boundary: String) -> String {
        var plain = ""
        var html = ""

        for part in split(body, boundary: boundary) {
            let (headerBlock, partBody) = splitHeadersAndBody(part)
            let partHeaders = parseHeaders(headerBlock)
            let type = (partHeaders["content-type"] ?? "text/plain").lowercased()

            // Anidado: un multipart/related dentro de un multipart/alternative
            // es lo normal cuando el aviso trae el logo del banco incrustado.
            if type.contains("multipart/"),
               let inner = parameter("boundary", in: partHeaders["content-type"] ?? "") {
                let nested = textFromParts(body: partBody, boundary: inner)
                if !nested.isEmpty { plain += nested + " " }
                continue
            }

            guard type.contains("text/") else { continue }   // adjuntos e imágenes fuera
            let decoded = decodeBody(
                partBody,
                transferEncoding: partHeaders["content-transfer-encoding"] ?? "",
                charset: parameter("charset", in: partHeaders["content-type"] ?? "")
            )
            if type.contains("text/html") {
                html += stripHTML(decoded) + " "
            } else {
                plain += decoded + " "
            }
        }

        let trimmedPlain = plain.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPlain.isEmpty ? html.trimmingCharacters(in: .whitespacesAndNewlines) : trimmedPlain
    }

    /// Trocea por `--boundary`. El cierre es `--boundary--`, y lo que va antes
    /// del primer delimitador es el preámbulo, que se descarta.
    private static func split(_ body: Data, boundary: String) -> [Data] {
        let delimiter = [UInt8]("--\(boundary)".utf8)
        let bytes = [UInt8](body)
        var parts: [Data] = []
        var cursor = 0
        var partStart: Int?

        while cursor <= bytes.count - delimiter.count {
            guard Array(bytes[cursor..<(cursor + delimiter.count)]) == delimiter,
                  cursor == 0 || bytes[cursor - 1] == 10 else {
                cursor += 1
                continue
            }
            if let start = partStart {
                var end = cursor
                // Los saltos que preceden al delimitador son suyos, no de la parte.
                while end > start, bytes[end - 1] == 10 || bytes[end - 1] == 13 { end -= 1 }
                parts.append(Data(bytes[start..<end]))
            }
            cursor += delimiter.count
            // `--` final: se acabaron las partes.
            if cursor + 1 < bytes.count, bytes[cursor] == 45, bytes[cursor + 1] == 45 { break }
            while cursor < bytes.count, bytes[cursor] == 13 || bytes[cursor] == 10 { cursor += 1 }
            partStart = cursor
        }
        return parts
    }

    // MARK: - Codificaciones

    static func decodeBody(_ data: Data, transferEncoding: String, charset: String?) -> String {
        let encoding = stringEncoding(for: charset)

        switch transferEncoding.lowercased() {
        case "base64":
            // Los saltos de línea de la codificación no son datos.
            let cleaned = String(decoding: data, as: UTF8.self)
                .components(separatedBy: .whitespacesAndNewlines).joined()
            guard let decoded = Data(base64Encoded: cleaned, options: .ignoreUnknownCharacters) else {
                return String(decoding: data, as: UTF8.self)
            }
            return String(data: decoded, encoding: encoding)
                ?? String(decoding: decoded, as: UTF8.self)
        case "quoted-printable":
            return decodeQuotedPrintable(String(decoding: data, as: UTF8.self), encoding: encoding)
        default:
            return String(data: data, encoding: encoding) ?? String(decoding: data, as: UTF8.self)
        }
    }

    private static func stringEncoding(for charset: String?) -> String.Encoding {
        switch charset?.lowercased() {
        case "iso-8859-1", "latin1", "iso8859-1", "windows-1252": return .isoLatin1
        case "us-ascii", "ascii": return .ascii
        default: return .utf8
        }
    }

    /// `=E2=82=AC` vuelve a ser un byte, y `=` al final de línea es un corte
    /// blando que desaparece. Se reconstruyen los **bytes** y sólo al final se
    /// interpretan con el juego de caracteres: hacerlo carácter a carácter
    /// parte en dos cualquier letra acentuada de un correo en UTF-8.
    /// - Note: se recorre **byte a byte**, no carácter a carácter. Swift agrupa
    ///   `\r\n` en un solo `Character` (es un grafema), así que comparar
    ///   `input[i] == "\r"` nunca acierta en un correo con saltos de línea de
    ///   red y los cortes blandos se quedaban sin deshacer — la palabra partida
    ///   se quedaba partida y el parser del banco no reconocía el aviso.
    static func decodeQuotedPrintable(_ input: String, encoding: String.Encoding = .utf8) -> String {
        let source = Array(input.utf8)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(source.count)

        let equals = UInt8(ascii: "=")
        let carriageReturn = UInt8(13)
        let newline = UInt8(10)
        var index = 0

        while index < source.count {
            guard source[index] == equals else {
                bytes.append(source[index])
                index += 1
                continue
            }
            guard index + 1 < source.count else {
                bytes.append(equals)
                break
            }

            // Corte blando: "=\r\n" o "=\n" no producen nada.
            if source[index + 1] == carriageReturn {
                index += 2
                if index < source.count, source[index] == newline { index += 1 }
                continue
            }
            if source[index + 1] == newline {
                index += 2
                continue
            }

            if index + 2 < source.count,
               let high = hexDigit(source[index + 1]),
               let low = hexDigit(source[index + 2]) {
                bytes.append(high << 4 | low)
                index += 3
                continue
            }

            // Un "=" que no abre nada válido es un "=" literal.
            bytes.append(equals)
            index += 1
        }

        let data = Data(bytes)
        return String(data: data, encoding: encoding) ?? String(decoding: data, as: UTF8.self)
    }

    private static func hexDigit(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return byte - UInt8(ascii: "0")
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return byte - UInt8(ascii: "A") + 10
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return byte - UInt8(ascii: "a") + 10
        default: return nil
        }
    }

    /// `=?UTF-8?B?…?=` en Asunto y De. Los bancos lo usan en cuanto el asunto
    /// lleva una tilde.
    static func decodeEncodedWords(_ input: String) -> String {
        guard input.contains("=?") else { return input }
        var result = input

        while let start = result.range(of: "=?"),
              let end = result.range(of: "?=", range: start.upperBound..<result.endIndex) {
            let token = String(result[start.upperBound..<end.lowerBound])
            let pieces = token.components(separatedBy: "?")
            guard pieces.count >= 3 else { break }

            let encoding = stringEncoding(for: pieces[0])
            let payload = pieces.dropFirst(2).joined(separator: "?")
            let decoded: String

            switch pieces[1].uppercased() {
            case "B":
                decoded = Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
                    .flatMap { String(data: $0, encoding: encoding) } ?? payload
            case "Q":
                // En palabras codificadas, "_" es un espacio.
                decoded = decodeQuotedPrintable(payload.replacingOccurrences(of: "_", with: " "),
                                                encoding: encoding)
            default:
                decoded = payload
            }
            result.replaceSubrange(start.lowerBound..<end.upperBound, with: decoded)
        }
        return result
    }

    // MARK: - HTML

    /// Quita marcado y deja el texto. Se borran `<style>` y `<script>` **con su
    /// contenido** antes que nada: si sólo se quitaran las etiquetas, las reglas
    /// CSS acabarían dentro del texto y un parser podría leer un número de una
    /// hoja de estilos como si fuera un importe.
    static func stripHTML(_ html: String) -> String {
        var text = html
        for tag in ["style", "script", "head"] {
            text = text.replacingOccurrences(
                of: "<\(tag)[^>]*>.*?</\(tag)>",
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        text = text.replacingOccurrences(of: "<br[^>]*>", with: "\n",
                                         options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "</(p|div|tr|li|h[1-6])>", with: "\n",
                                         options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
                        "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&aacute;": "á",
                        "&eacute;": "é", "&iacute;": "í", "&oacute;": "ó",
                        "&uacute;": "ú", "&ntilde;": "ñ", "&Ntilde;": "Ñ"]
        for (entity, character) in entities {
            text = text.replacingOccurrences(of: entity, with: character, options: .caseInsensitive)
        }
        // Entidades numéricas que queden sueltas.
        text = text.replacingOccurrences(of: "&#[0-9]+;", with: " ", options: .regularExpression)

        return text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Fecha

    /// La fecha de la cabecera `Date:`, en los dos formatos que se ven en la
    /// práctica (con y sin día de la semana).
    static func parseDate(_ value: String) -> Date? {
        let formats = ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        // Algunos servidores añaden la zona en texto: "… -0500 (GMT-5)".
        let cleaned = value.replacingOccurrences(of: "\\s*\\([^)]*\\)\\s*$", with: "",
                                                 options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: cleaned) { return date }
        }
        return nil
    }
}
