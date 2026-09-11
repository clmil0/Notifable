import Foundation
import SwiftData

/// Última foto conocida de un amigo, guardada en el propio teléfono.
///
/// `FriendsManager` la pinta primero (instantáneo, sin esperar red) y luego
/// la reemplaza en cuanto llega la respuesta del servidor — que es también
/// quien la mantiene actualizada. Esta caché nunca decide nada por su cuenta,
/// sólo evita la pantalla en blanco del primer instante.
@Model
final class CachedFriend {
    @Attribute(.unique) var id: String
    var displayName: String
    var status: String
    var friendSince: Date?

    init(id: String, displayName: String, status: String, friendSince: Date? = nil) {
        self.id = id
        self.displayName = displayName
        self.status = status
        self.friendSince = friendSince
    }
}

/// Última foto conocida de una fila de `friend_shares` (lo que un amigo te
/// comparte, o lo que tú le compartes a él). `categoryTotals`/`shareCategories`
/// van como JSON porque SwiftData no guarda arrays de structs directamente.
@Model
final class CachedFriendShare {
    @Attribute(.unique) var id: String
    var sharerID: String
    var viewerID: String
    var shareTotal: Bool
    var shareCategoriesData: Data
    var totalAmount: Double?
    var categoryTotalsData: Data
    var viewerStatus: String
    var updatedAt: String

    init(row: FriendShareRow) {
        id = row.id
        sharerID = row.sharerID
        viewerID = row.viewerID
        shareTotal = row.shareTotal
        shareCategoriesData = (try? JSONEncoder().encode(row.shareCategories)) ?? Data()
        totalAmount = row.totalAmount
        categoryTotalsData = (try? JSONEncoder().encode(row.categoryTotals)) ?? Data()
        viewerStatus = row.viewerStatus
        updatedAt = row.updatedAt
    }

    func update(from row: FriendShareRow) {
        sharerID = row.sharerID
        viewerID = row.viewerID
        shareTotal = row.shareTotal
        shareCategoriesData = (try? JSONEncoder().encode(row.shareCategories)) ?? Data()
        totalAmount = row.totalAmount
        categoryTotalsData = (try? JSONEncoder().encode(row.categoryTotals)) ?? Data()
        viewerStatus = row.viewerStatus
        updatedAt = row.updatedAt
    }

    var asRow: FriendShareRow {
        let categories = (try? JSONDecoder().decode([String].self, from: shareCategoriesData)) ?? []
        let totals = (try? JSONDecoder().decode([FriendShareRow.CategoryAmount].self, from: categoryTotalsData)) ?? []
        return FriendShareRow(id: id, sharerID: sharerID, viewerID: viewerID, shareTotal: shareTotal,
                               shareCategories: categories, totalAmount: totalAmount,
                               categoryTotals: totals, viewerStatus: viewerStatus, updatedAt: updatedAt)
    }
}
