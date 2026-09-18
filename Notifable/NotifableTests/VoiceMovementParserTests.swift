import Testing
import Foundation
@testable import Notifable

/// Las frases del diseño «Dictado por voz» y las formas habituales de dictar
/// un monto. La categoría se inyecta para no depender de las reglas guardadas.
struct VoiceMovementParserTests {

    /// Un catálogo mínimo, fijo: las pruebas no dependen del descargado.
    private static let catalog = [
        "almuerzo": "Comida", "taxi": "Transporte", "cine": "Entretenimiento",
        "pollo": "Comida", "metro": "Supermercado", "plaza vea": "Supermercado"
    ]

    private func parse(_ text: String) -> [VoiceMovement] {
        VoiceMovementParser.parse(text, categoryFor: { title, whole in
            let text = (title + " " + whole).lowercased()
            return Self.catalog.first { text.contains($0.key) }?.value
        }, keywordCategory: { word in
            let singular = word.hasSuffix("s") ? String(word.dropLast()) : word
            return Self.catalog[word] ?? Self.catalog[singular]
        })
    }

    @Test func gastoSimple() {
        let result = parse("Gasté 24 soles en el almuerzo")
        #expect(result.count == 1)
        #expect(result[0].kind == .gasto)
        #expect(result[0].amount == 24)
        #expect(result[0].title == "Almuerzo")
        #expect(result[0].category == "Comida")
        #expect(result[0].currency == "PEN")
    }

    @Test func tituloCortaEnDe() {
        let result = parse("Y 8 en el taxi de vuelta")
        #expect(result.count == 1)
        #expect(result[0].amount == 8)
        #expect(result[0].title == "Taxi")
        #expect(result[0].category == "Transporte")
    }

    @Test func ingresoSinMontoPregunta() {
        let result = parse("Me pagaron el freelance")
        #expect(result.count == 1)
        #expect(result[0].kind == .ingreso)
        #expect(result[0].amount == nil)
        #expect(result[0].title == "Freelance")
    }

    @Test func montoEnPalabras() {
        #expect(VoiceMovementParser.amount(in: "Mil doscientos") == 1200)
        #expect(VoiceMovementParser.amount(in: "treinta y cinco soles") == 35)
        #expect(VoiceMovementParser.amount(in: "veinticuatro con cincuenta") == 24.5)
        #expect(VoiceMovementParser.amount(in: "doce soles y medio") == 12.5)
    }

    @Test func montoConDecimalesYMiles() {
        #expect(VoiceMovementParser.amount(in: "S/ 24.50 en pan") == 24.5)
        #expect(VoiceMovementParser.amount(in: "24,50 en pan") == 24.5)
        #expect(VoiceMovementParser.amount(in: "1,200 soles") == 1200)
    }

    @Test func dosMovimientosEnUnaFrase() {
        let result = parse("24 en el almuerzo y 8 en el taxi")
        #expect(result.count == 2)
        #expect(result[0].amount == 24)
        #expect(result[0].title == "Almuerzo")
        #expect(result[1].amount == 8)
        #expect(result[1].title == "Taxi")
    }

    @Test func treintaYCincoNoSeParte() {
        let result = parse("treinta y cinco soles en el almuerzo")
        #expect(result.count == 1)
        #expect(result[0].amount == 35)
    }

    @Test func dolaresYFuente() {
        let result = parse("pagué 15 dólares con yape en netflix")
        #expect(result[0].currency == "USD")
        #expect(result[0].source == "Yape")
        #expect(result[0].amount == 15)
        #expect(result[0].title == "Netflix")
    }

    @Test func conservaTildes() {
        let result = parse("8 soles en un café")
        #expect(result[0].title == "Café")
    }

    @Test func unoArticuloNoEsMonto() {
        let result = parse("un café")
        #expect(result.first?.amount == nil)
        #expect(result.first?.title == "Café")
    }

    @Test func fraseSinQuePregunta() {
        let result = parse("Quiero registrar que he gastado 25 soles")
        #expect(result.count == 1)
        #expect(result[0].amount == 25)
        #expect(result[0].title == nil)
        #expect(result[0].category == Accounting.unclassified)
    }

    // MARK: - Frases que dan vueltas

    @Test func relatoConLugar() {
        let result = parse("Bueno, o sea, ayer fui con mis amigos al cine y la entrada me salió como 25 soles")
        #expect(result.count == 1)
        #expect(result[0].amount == 25)
        #expect(result[0].title == "Cine")
        #expect(result[0].category == "Entretenimiento")
    }

    @Test func correccionTomaElUltimoMonto() {
        let result = parse("iba a gastar 50 en el almuerzo pero al final fueron 30")
        #expect(result.count == 1)
        #expect(result[0].amount == 30)
        #expect(result[0].title == "Almuerzo")
    }

    @Test func palabraDelCatalogoEnMedio() {
        let result = parse("pasé por plaza vea a comprar unas cositas y gasté 48 soles")
        #expect(result[0].amount == 48)
        #expect(result[0].title == "Plaza vea")
        #expect(result[0].category == "Supermercado")
    }

    @Test func gastadoNoEsGas() {
        let result = VoiceMovementParser.parse("he gastado 12 soles") { _, _ in nil }
        #expect(result[0].title == nil)
    }

    @Test func ayer() {
        let now = Date()
        let result = VoiceMovementParser.parse("ayer gasté 10 en pan", now: now) { _, _ in nil }
        let expected = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        #expect(Calendar.current.isDate(result[0].date, inSameDayAs: expected))
    }
}
