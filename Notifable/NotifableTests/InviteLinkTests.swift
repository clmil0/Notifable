import Foundation
import Testing
@testable import Notifable

/// El token de invitación se escribe a mano a veces: la app tiene que
/// normalizarlo igual que `normalize_invite_token` en el servidor.
struct InviteLinkTests {

    @Test func acceptsGroupedLowercaseAndLookalikes() {
        #expect(InviteLinks.normalizedCode("abcd-efgh-jkmn-pqrs-tvwx") == "ABCDEFGHJKMNPQRSTVWX")
        #expect(InviteLinks.normalizedCode("O0IL 1234 5678 9ABC DEFG") == "0011123456789ABCDEFG")
    }

    @Test func rejectsWrongLengthAndOldCodes() {
        #expect(InviteLinks.normalizedCode("a1b2c3d4") == nil)
        #expect(InviteLinks.normalizedCode("ABCD-EFGH-JKMN-PQRS-TVW") == nil)
        #expect(InviteLinks.normalizedCode("ABCD-EFGH-JKMN-PQRS-TVWU") == nil)
    }

    @Test func groupsInFours() {
        #expect(InviteLinks.grouped("ABCDEFGHJKMNPQRSTVWX") == "ABCD-EFGH-JKMN-PQRS-TVWX")
    }

    @Test func universalLinkCarriesTheToken() throws {
        guard let host = InviteLinks.webHosts.first else { return }
        let url = try #require(URL(string: "https://\(host)/amigo/abcd-efgh-jkmn-pqrs-tvwx"))
        #expect(AppDeepLink(url: url) == .friendInvite(code: "ABCDEFGHJKMNPQRSTVWX"))
    }
}
