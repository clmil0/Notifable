import Testing
import Foundation
import SwiftData
@testable import Notifable

/// Lectura de respuestas IMAP.
///
/// Es la parte que más fácil se rompe en silencio: un fallo aquí no da error,
/// devuelve un correo cortado que ningún parser reconoce, y el usuario ve
/// "0 movimientos" sin saber por qué.
struct IMAPParsingTests {

    private func data(_ text: String) -> Data { Data(text.utf8) }

    @Test("Una respuesta simple se cierra con su línea etiquetada")
    func respuestaSimple() {
        let buffer = data("* OK algo\r\nA0001 OK LOGIN completed\r\n")
        let response = IMAPClient.completedResponse(in: buffer, tag: "A0001")

        #expect(response?.isOK == true)
        #expect(response?.consumed == buffer.count)
    }

    @Test("Una respuesta incompleta no se da por cerrada")
    func respuestaIncompleta() {
        // Sin la línea etiquetada todavía no se puede responder.
        #expect(IMAPClient.completedResponse(in: data("* OK algo\r\n"), tag: "A0001") == nil)
    }

    @Test("NO y BAD se distinguen de OK")
    func respuestaDeError() {
        let response = IMAPClient.completedResponse(in: data("A0002 NO credenciales\r\n"), tag: "A0002")
        #expect(response?.isOK == false)
        #expect(response?.detail.contains("credenciales") == true)
    }

    /// El caso que motiva todo el parseo por literales: el cuerpo de un correo
    /// es contenido crudo y puede contener cualquier cosa, incluida una línea
    /// que parezca el cierre de la orden. Sin saltarlo por su longitud
    /// declarada, la respuesta se cortaría por la mitad.
    @Test("Un literal que contiene una línea etiquetada no corta la respuesta")
    func literalConTextoEnganoso() {
        let payload = "A0003 OK no soy el cierre\r\n"
        let buffer = data("* 1 FETCH (BODY[] {\(payload.utf8.count)}\r\n\(payload))\r\nA0003 OK FETCH completed\r\n")

        let response = IMAPClient.completedResponse(in: buffer, tag: "A0003")
        #expect(response != nil)
        #expect(response?.isOK == true)
        // Consume el buffer entero, no sólo hasta la línea engañosa.
        #expect(response?.consumed == buffer.count)
    }

    @Test("Un literal a medio llegar espera a estar completo")
    func literalIncompleto() {
        // Se anuncian 100 bytes pero sólo han llegado unos pocos.
        let buffer = data("* 1 FETCH (BODY[] {100}\r\nsólo esto")
        #expect(IMAPClient.completedResponse(in: buffer, tag: "A0004") == nil)
    }

    @Test("El contenido del literal se extrae con su longitud exacta")
    func extraerLiteral() {
        let cuerpo = "From: banco@bcp.com.pe\r\n\r\nConsumo de S/ 84.90"
        let buffer = data("* 1 FETCH (UID 7 BODY[] {\(cuerpo.utf8.count)}\r\n\(cuerpo))\r\nA0005 OK\r\n")

        let extracted = IMAPClient.extractLiteral(from: buffer)
        #expect(String(decoding: extracted, as: UTF8.self) == cuerpo)
    }

    @Test("Los UIDs salen de la línea SEARCH")
    func tamanoDeLiteral() {
        #expect(IMAPClient.literalSize(in: Array("* 1 FETCH (BODY[] {2048}".utf8)) == 2048)
        // La variante no sincronizada lleva un "+".
        #expect(IMAPClient.literalSize(in: Array("A1 LOGIN {12+}".utf8)) == 12)
        #expect(IMAPClient.literalSize(in: Array("A1 OK done".utf8)) == nil)
    }

    @Test("La fecha va en el formato que IMAP entiende, sin depender del idioma")
    func formatoDeFecha() {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 9
        let date = Calendar(identifier: .gregorian).date(from: components)!
        #expect(IMAPClient.imapDate(date) == "09-Mar-2026")
    }
}

/// Apertura de correos MIME.
struct MIMEDecoderTests {

    @Test("Un correo de texto plano se lee entero")
    func textoPlano() {
        let raw = Data("""
        From: notificaciones@notificacionesbcp.com.pe\r
        Subject: Consumo con tarjeta\r
        \r
        Realizaste un consumo de S/ 84.90 en PLAZA VEA.
        """.utf8)

        let message = MIMEDecoder.parse(raw: raw)
        #expect(message.from.contains("notificacionesbcp"))
        #expect(message.subject == "Consumo con tarjeta")
        #expect(message.text.contains("S/ 84.90"))
    }

    @Test("En un multipart se prefiere el texto plano al HTML")
    func multipartPrefiereTextoPlano() {
        let raw = Data("""
        Subject: Aviso\r
        Content-Type: multipart/alternative; boundary="frontera"\r
        \r
        --frontera\r
        Content-Type: text/plain; charset="utf-8"\r
        \r
        Version en texto: S/ 120.00\r
        --frontera\r
        Content-Type: text/html; charset="utf-8"\r
        \r
        <html><body>Version en HTML</body></html>\r
        --frontera--\r
        """.utf8)

        let message = MIMEDecoder.parse(raw: raw)
        #expect(message.text.contains("Version en texto"))
        #expect(!message.text.contains("Version en HTML"))
    }

    @Test("Si sólo viene HTML, se limpia y se usa")
    func soloHTML() {
        let raw = Data("""
        Content-Type: text/html; charset="utf-8"\r
        \r
        <html><body><p>Consumo de <b>S/ 45.50</b></p></body></html>
        """.utf8)

        let message = MIMEDecoder.parse(raw: raw)
        #expect(message.text.contains("S/ 45.50"))
        #expect(!message.text.contains("<b>"))
    }

    /// El CSS de un correo de banco lleva números por todas partes (píxeles,
    /// colores). Si `<style>` sólo perdiera las etiquetas y no el contenido, un
    /// parser podría leer un `padding: 12.50px` como si fuera un importe.
    @Test("El contenido de <style> y <script> desaparece, no sólo sus etiquetas")
    func estilosFuera() {
        let html = "<style>.x{padding:99.99px}</style><script>var monto=77.77;</script><p>S/ 10.00</p>"
        let text = MIMEDecoder.stripHTML(html)

        #expect(text.contains("S/ 10.00"))
        #expect(!text.contains("99.99"))
        #expect(!text.contains("77.77"))
    }

    @Test("Quoted-printable reconstruye los acentos y deshace los cortes blandos")
    func quotedPrintable() {
        // "Depósito" en UTF-8, con un corte blando de línea en medio.
        let decoded = MIMEDecoder.decodeQuotedPrintable("Dep=C3=B3si=\r\nto recibido")
        #expect(decoded == "Depósito recibido")
    }

    @Test("Base64 se decodifica aunque venga partido en líneas")
    func base64EnLineas() {
        let original = "Consumo de S/ 999.99 en TOTTUS"
        let encoded = Data(original.utf8).base64EncodedString()
        // Los servidores parten el base64 cada 76 caracteres.
        let split = encoded.enumerated().map { index, char in
            index > 0 && index % 10 == 0 ? "\r\n\(char)" : String(char)
        }.joined()

        let decoded = MIMEDecoder.decodeBody(Data(split.utf8),
                                             transferEncoding: "base64",
                                             charset: "utf-8")
        #expect(decoded == original)
    }

    @Test("Latin-1 no se lee como UTF-8")
    func latin1() {
        // 0xF3 es "ó" en Latin-1 y no es UTF-8 válido.
        let decoded = MIMEDecoder.decodeBody(Data([0x44, 0x65, 0x70, 0xF3, 0x73, 0x69, 0x74, 0x6F]),
                                             transferEncoding: "",
                                             charset: "iso-8859-1")
        #expect(decoded == "Depósito")
    }

    @Test("Un asunto con palabras codificadas se lee legible")
    func palabrasCodificadas() {
        let encoded = Data("Constancia de Yapeo".utf8).base64EncodedString()
        #expect(MIMEDecoder.decodeEncodedWords("=?UTF-8?B?\(encoded)?=") == "Constancia de Yapeo")
        // La variante Q, donde "_" es un espacio.
        #expect(MIMEDecoder.decodeEncodedWords("=?UTF-8?Q?Pago_recibido?=") == "Pago recibido")
    }

    @Test("Las cabeceras partidas en varias líneas se unen")
    func cabecerasContinuadas() {
        let headers = MIMEDecoder.parseHeaders("Content-Type: multipart/mixed;\r\n\tboundary=\"una-frontera-larga\"")
        let contentType = headers["content-type"] ?? ""
        #expect(MIMEDecoder.parameter("boundary", in: contentType) == "una-frontera-larga")
    }
}

/// La cuenta y su credencial.
struct ICloudMailAccountTests {

    @Test("La contraseña se acepta con guiones, con espacios o pegada")
    func normalizacion() {
        #expect(ICloudMailAccount.normalize("abcd-efgh-ijkl-mnop") == "abcdefghijklmnop")
        #expect(ICloudMailAccount.normalize("abcd efgh ijkl mnop") == "abcdefghijklmnop")
        #expect(ICloudMailAccount.normalize("abcdefghijklmnop") == "abcdefghijklmnop")
    }

    /// Apple pide el nombre corto para IMAP de entrada. Con la dirección
    /// completa el LOGIN falla con un error de credenciales que no explica nada.
    @Test("El usuario de IMAP es la parte anterior a la arroba")
    func usuarioDeIMAP() {
        #expect(ICloudMailAccount.imapUsername(for: "josealan@icloud.com") == "josealan")
        #expect(ICloudMailAccount.imapUsername(for: "alguien@me.com") == "alguien")
    }

    @Test("Se distingue una contraseña específica de la del Apple ID")
    func formatoDeContrasena() {
        #expect(ICloudMailAccount.looksLikeAppPassword("abcd-efgh-ijkl-mnop"))
        #expect(!ICloudMailAccount.looksLikeAppPassword("MiClave123!"))
        #expect(!ICloudMailAccount.looksLikeAppPassword("abcd-efgh"))
    }

    /// El UID sólo es único dentro de un buzón: sin la dirección delante, el
    /// correo 42 de una cuenta y el 42 de otra serían el mismo movimiento.
    @Test("El identificador de correo lleva la cuenta, para no colisionar")
    func identificadorDeCorreo() {
        let a = ICloudSyncService.emailID(address: "uno@icloud.com", uid: 42)
        let b = ICloudSyncService.emailID(address: "dos@icloud.com", uid: 42)
        #expect(a != b)
        #expect(a.hasPrefix("icloud:"))
    }
}
