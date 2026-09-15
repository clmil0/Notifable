import Foundation
import Testing
@testable import Notifable

struct MerchantCatalogTests {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("catalog-\(UUID().uuidString).json")
    }

    @Test func sinArchivoUsaLaListaDeFabrica() {
        let catalog = MerchantCatalog(fileURL: tempURL())
        #expect(catalog.version == nil)
        #expect(catalog.category(for: "TOTTUS LA MARINA") == "Supermercado")
    }

    @Test func ganaLaPalabraMasLarga() {
        let catalog = MerchantCatalog(fileURL: tempURL())
        #expect(catalog.category(for: "UBER EATS PERU") == "Comida")
        #expect(catalog.category(for: "UBER TRIP") == "Transporte")
        #expect(catalog.category(for: "METROPOLITANO RECARGA") == "Transporte")
    }

    @Test func ignoraTildes() {
        let catalog = MerchantCatalog(fileURL: tempURL())
        #expect(catalog.category(for: "POLLERIA EL REY") == "Comida")
    }

    @Test func loDescargadoQuedaGuardado() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let catalog = MerchantCatalog(fileURL: url)
        catalog.replace(with: .init(version: "v2|1", downloadedAt: Date(),
                                    entries: [MerchantKeyword(keyword: "Juan Valdez", category: "Comida")]))

        let reopened = MerchantCatalog(fileURL: url)
        #expect(reopened.version == "v2|1")
        #expect(reopened.category(for: "JUAN VALDEZ LARCOMAR") == "Comida")
        #expect(reopened.category(for: "TOTTUS") == nil)
    }

    @Test func laSugerenciaUsaElCatalogo() {
        let catalog = MerchantCatalog(fileURL: tempURL())
        catalog.replace(with: .init(version: "x", downloadedAt: nil,
                                    entries: [MerchantKeyword(keyword: "chilis", category: "Comida")]))
        let suggestion = SuggestionEngine.suggest(for: "CHILIS JOCKEY", rules: [:], catalog: catalog)
        #expect(suggestion?.category == "Comida")
    }
}
