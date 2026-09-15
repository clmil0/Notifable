import Foundation

/// ¿Ya está publicada la página del dominio de invitaciones?
///
/// Se comprueba pidiendo el `apple-app-site-association`, el mismo archivo que
/// iOS descarga para confiar en el enlace, y mirando que nombre a esta app.
/// Así el mensaje de WhatsApp sólo lleva el enlace cuando tocarlo funciona:
/// antes de subir `web/`, o si el dominio se cae, se comparte sólo el código.
///
/// El resultado se guarda: un "sí" vale una semana y un "no" se reintenta
/// cada vez que se abre la hoja de Agregar amigo.
enum InviteLinkCheck {

    private static let okUntilKey = "inviteLinkVerifiedUntil"
    static let validity: TimeInterval = 7 * 24 * 60 * 60

    static var isKnownReady: Bool {
        guard let until = UserDefaults.standard.object(forKey: okUntilKey) as? Date else { return false }
        return until > Date() && !InviteLinks.webHosts.isEmpty
    }

    static func isReady() async -> Bool {
        if isKnownReady { return true }
        guard let host = InviteLinks.webHosts.first,
              let url = URL(string: "https://\(host)/.well-known/apple-app-site-association") else { return false }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpMethod = "GET"
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let bundleID = Bundle.main.bundleIdentifier,
              let body = String(data: data, encoding: .utf8),
              body.contains(bundleID) else { return false }

        UserDefaults.standard.set(Date().addingTimeInterval(validity), forKey: okUntilKey)
        return true
    }
}
