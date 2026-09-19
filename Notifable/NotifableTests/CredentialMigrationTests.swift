import Foundation
import Testing
@testable import Notifable

/// Los tokens pasan de `UserDefaults` al Llavero sin desconectar a nadie, y
/// una instalación nueva no hereda los de una anterior.
@Suite(.serialized)
struct CredentialMigrationTests {

    private func defaults() -> UserDefaults {
        let name = "test-credentials-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func clearStores() {
        SecureStore.gmail.removeAll()
        SecureStore.backup.removeAll()
    }

    @Test func updateMovesTokensToKeychain() {
        clearStores()
        let d = defaults()
        d.set("g-access", forKey: "GmailAccessToken")
        d.set("g-refresh", forKey: "GmailRefreshToken")
        d.set("header.payload.sig", forKey: "GmailIDToken")
        d.set("b-refresh", forKey: "backupAccountRefreshToken")

        CredentialMigration.runIfNeeded(d)

        #expect(SecureStore.gmail.read(GmailAuthService.Keys.accessToken) == "g-access")
        #expect(SecureStore.gmail.read(GmailAuthService.Keys.refreshToken) == "g-refresh")
        #expect(SecureStore.backup.read(BackupAccount.Keys.refreshToken) == "b-refresh")
        #expect(d.bool(forKey: GmailAuthService.Keys.hasIdentity))
        for key in ["GmailAccessToken", "GmailRefreshToken", "GmailIDToken", "backupAccountRefreshToken"] {
            #expect(d.string(forKey: key) == nil, "\(key) sigue en UserDefaults")
        }
        clearStores()
    }

    @Test func freshInstallDropsLeftoverTokens() {
        clearStores()
        SecureStore.gmail.write("de-la-instalacion-anterior", for: GmailAuthService.Keys.refreshToken)
        SecureStore.backup.write("idem", for: BackupAccount.Keys.refreshToken)

        CredentialMigration.runIfNeeded(defaults())

        #expect(SecureStore.gmail.read(GmailAuthService.Keys.refreshToken) == nil)
        #expect(SecureStore.backup.read(BackupAccount.Keys.refreshToken) == nil)
    }

    @Test func runsOnlyOnce() {
        clearStores()
        let d = defaults()
        CredentialMigration.runIfNeeded(d)
        SecureStore.gmail.write("nuevo", for: GmailAuthService.Keys.refreshToken)

        CredentialMigration.runIfNeeded(d)

        #expect(SecureStore.gmail.read(GmailAuthService.Keys.refreshToken) == "nuevo")
        clearStores()
    }
}
