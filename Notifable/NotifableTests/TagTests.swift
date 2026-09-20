import Testing
import Foundation
@testable import Notifable

/// Las etiquetas. Lo que se comprueba aquí es lo que la pantalla no puede
/// enseñar mal: que dos formas de escribir la misma etiqueta sean una sola, que
/// un gasto con dos etiquetas cuente en las dos —y que eso no se disfrace de
/// porcentaje—, y que "sin etiquetar" sea la única cifra disjunta.
struct TagTests {

    static let cal = Period.calendar

    static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    static var september: DateInterval {
        DateInterval(start: day(2026, 9, 1), end: day(2026, 10, 1))
    }

    static func expense(_ amount: Double,
                        _ date: Date,
                        category: String = "Salud",
                        tags: [String] = []) -> ExpenseSnapshot {
        ExpenseSnapshot(amount: amount, currency: "PEN", date: date,
                        category: category, merchant: "FARMACIA", tags: tags)
    }

    // MARK: - Normalización

    @Test("Mayúsculas, tildes y espacios no crean etiquetas distintas")
    func normalizacion() {
        #expect(TagCatalog.normalized("Madre") == TagCatalog.normalized("madre"))
        #expect(TagCatalog.normalized(" MADRE ") == TagCatalog.normalized("madre"))
        #expect(TagCatalog.normalized("Mamá") == TagCatalog.normalized("mama"))
        #expect(TagCatalog.normalized("madre") != TagCatalog.normalized("padre"))
    }

    @Test("`use` devuelve el nombre con el que se creó, no el que se tecleó")
    func formaCanonica() {
        let defaults = UserDefaults(suiteName: "tags.canonica")!
        defaults.removePersistentDomain(forName: "tags.canonica")
        let catalog = TagCatalog(defaults: defaults)

        #expect(catalog.use("Madre") == "Madre")
        #expect(catalog.use("madre") == "Madre")
        #expect(catalog.use("  MADRE  ") == "Madre")
        #expect(catalog.names.count == 1)
    }

    @Test("Una etiqueta vacía no se crea")
    func vacia() {
        let defaults = UserDefaults(suiteName: "tags.vacia")!
        defaults.removePersistentDomain(forName: "tags.vacia")
        let catalog = TagCatalog(defaults: defaults)

        #expect(catalog.use("   ") == nil)
        #expect(catalog.names.isEmpty)
    }

    // MARK: - Totales

    @Test("Un gasto con dos etiquetas suma entero en las dos")
    func gastoConDosEtiquetas() {
        let rows = TagTotals.rows(
            expenses: [Self.expense(100, Self.day(2026, 9, 10), tags: ["madre", "urgente"])],
            in: Self.september,
            usdToPen: 3.8)

        #expect(rows.count == 2)
        #expect(rows.allSatisfy { Money.cents($0.total) == 10_000 })
        // Y por eso la suma de las filas (200) no es el gasto del mes (100):
        // es justo lo que la pantalla no debe presentar como porcentaje.
        #expect(Money.cents(Money.sum(rows.map(\.total))) == 20_000)
    }

    @Test("La misma etiqueta en dos formas es una sola fila")
    func filasSeAgrupanPorClave() {
        let rows = TagTotals.rows(
            expenses: [Self.expense(60, Self.day(2026, 9, 3), tags: ["Madre"]),
                       Self.expense(40, Self.day(2026, 9, 8), tags: ["madre"])],
            in: Self.september,
            usdToPen: 3.8)

        #expect(rows.count == 1)
        #expect(rows.first?.count == 2)
        #expect(Money.cents(rows.first?.total ?? 0) == 10_000)
    }

    @Test("Fuera del intervalo no cuenta")
    func fueraDelMes() {
        let rows = TagTotals.rows(
            expenses: [Self.expense(50, Self.day(2026, 8, 30), tags: ["madre"]),
                       Self.expense(30, Self.day(2026, 9, 2), tags: ["madre"])],
            in: Self.september,
            usdToPen: 3.8)

        #expect(Money.cents(rows.first?.total ?? 0) == 3_000)
    }

    @Test("Una etiqueta del catálogo sin uso aparece en cero")
    func etiquetaSinUso() {
        let rows = TagTotals.rows(expenses: [], in: Self.september, usdToPen: 3.8, known: ["viaje"])

        #expect(rows.count == 1)
        #expect(rows.first?.count == 0)
        #expect(Money.isZero(rows.first?.total ?? 1))
    }

    @Test("«Sin etiquetar» sólo cuenta lo que no lleva ninguna")
    func sinEtiquetar() {
        let expenses = [Self.expense(100, Self.day(2026, 9, 10), tags: ["madre"]),
                        Self.expense(40, Self.day(2026, 9, 11))]

        #expect(Money.cents(TagTotals.untagged(expenses: expenses,
                                               in: Self.september,
                                               usdToPen: 3.8)) == 4_000)
    }

    @Test("Dentro de una etiqueta, las categorías sí suman su total")
    func repartoPorCategoria() {
        let expenses = [Self.expense(120, Self.day(2026, 9, 4), category: "Salud", tags: ["madre"]),
                        Self.expense(80, Self.day(2026, 9, 9), category: "Supermercado", tags: ["madre"]),
                        Self.expense(50, Self.day(2026, 9, 9), category: "Salud", tags: ["padre"])]

        let reparto = TagTotals.byCategory(tag: "Madre", expenses: expenses,
                                           in: Self.september, usdToPen: 3.8)

        #expect(reparto.count == 2)
        #expect(reparto.first?.category == "Salud")
        #expect(Money.cents(Money.sum(reparto.map(\.total))) == 20_000)
    }

    // MARK: - Fusionar

    @Test("La vista previa de fusión une, no suma: el gasto con las dos cuenta una vez")
    func fusionUneSinDuplicar() {
        let expenses = [Self.expense(100, Self.day(2026, 9, 4), tags: ["madre"]),
                        Self.expense(50, Self.day(2026, 9, 6), tags: ["mamá"]),
                        Self.expense(30, Self.day(2026, 9, 7), tags: ["madre", "mamá"])]

        let preview = TagTotals.mergePreview(source: "mamá", target: "madre",
                                             expenses: expenses, in: Self.september, usdToPen: 3.8)

        #expect(preview.count == 3)
        #expect(Money.cents(preview.total) == 18_000)
    }

    @Test("«Usada alguna vez» mira todo el historial, no el mes")
    func usadaAlgunaVez() {
        let used = TagTotals.everUsed([Self.expense(40, Self.day(2025, 3, 2), tags: ["padre"])])

        #expect(used.contains(TagCatalog.normalized("Padre")))
        #expect(!used.contains(TagCatalog.normalized("regalo")))
    }

    @Test("El gasto neto manda: una devolución baja también el total de la etiqueta")
    func gastoNeto() {
        let expense = ExpenseSnapshot(amount: 100, currency: "PEN",
                                      date: Self.day(2026, 9, 10),
                                      category: "Salud", merchant: "FARMACIA",
                                      tags: ["madre"], isDebt: false,
                                      paymentsInOwnCurrency: 40)
        let rows = TagTotals.rows(expenses: [expense], in: Self.september, usdToPen: 3.8)

        #expect(Money.cents(rows.first?.total ?? 0) == 6_000)
    }
}
