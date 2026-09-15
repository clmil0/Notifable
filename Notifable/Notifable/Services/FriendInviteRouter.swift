import Foundation
import Observation

/// Lleva el código de un enlace de invitación hasta Amigos.
///
/// El enlace llega a `ContentView`, pero quien sabe si hay sesión y presenta
/// la hoja es `AmigosHubView`, que puede ni estar montada todavía. El código
/// espera aquí hasta que ella lo recoja.
@MainActor
@Observable
final class FriendInviteRouter {
    static let shared = FriendInviteRouter()
    var pendingCode: String?

    func take() -> String? {
        defer { pendingCode = nil }
        return pendingCode
    }
}
