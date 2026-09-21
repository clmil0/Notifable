import Testing
import Foundation
@testable import Notifable

/// Tus cuentas y los traslados. Lo que se comprueba es lo que no puede fallar
/// en silencio: de qué cuenta sale cada correo, que el mismo nombre sea la
/// misma cuenta —y sólo el mismo—, y que un traslado no sume en ningún total.
struct MoneyAccountsTests {

    static let cal = Period.calendar

    static func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: - Origen

    @Test("Una tarjeta es banco + últimos cuatro: débito y crédito del mismo banco son dos")
    func origenPorTarjeta() {
        let debit = AccountResolver.originKey(sourceBank: "BBVA", merchant: "WONG", cardLastDigits: "7742", fromEmail: true)
        let credit = AccountResolver.originKey(sourceBank: "BBVA", merchant: "WONG", cardLastDigits: "1234", fromEmail: true)
        #expect(debit == "o:bbva:7742")
        #expect(credit == "o:bbva:1234")
        #expect(debit != credit)
    }

    @Test("Un Plin leído por el parser de BBVA sale de BBVA")
    func plinDeBBVA() {
        #expect(AccountResolver.originKey(sourceBank: "BBVA", merchant: "PLIN - JUAN PEREZ",
                                          cardLastDigits: nil, fromEmail: true) == "o:bbva")
    }

    @Test("Un Yape sale de Yape; un Plin pagado con débito BCP sale de esa tarjeta BCP")
    func yapeYPlinBCP() {
        #expect(AccountResolver.originKey(sourceBank: "Yape", merchant: "YAPE - ANA",
                                          cardLastDigits: nil, fromEmail: true) == "o:yape")
        #expect(AccountResolver.originKey(sourceBank: "Yape", merchant: "YAPE - ANA",
                                          cardLastDigits: "0456", fromEmail: true) == "o:bcp:0456")
    }

    @Test("Sin `sourceBank` (importado antes) se deduce del prefijo del comercio")
    func origenDeducido() {
        #expect(AccountResolver.originKey(sourceBank: nil, merchant: "YAPE - ANA",
                                          cardLastDigits: nil, fromEmail: true) == "o:yape")
        #expect(AccountResolver.originKey(sourceBank: nil, merchant: "BBVA - ANA",
                                          cardLastDigits: "5555", fromEmail: true) == "o:bbva:5555")
        #expect(AccountResolver.originKey(sourceBank: nil, merchant: "TOTTUS",
                                          cardLastDigits: "9999", fromEmail: true) == "o:tarjeta:9999")
    }

    @Test("Lo anotado a mano cae en Efectivo; un ingreso, en la fuente elegida")
    func manuales() {
        #expect(AccountResolver.originKey(sourceBank: nil, merchant: "Menú", cardLastDigits: nil,
                                          fromEmail: false) == "o:efectivo")
        #expect(AccountResolver.originKey(incomeSource: "Plin", fromEmail: false) == "o:plin")
        #expect(AccountResolver.originKey(incomeSource: "Transferencia", fromEmail: false) == nil)
        #expect(AccountResolver.originKey(incomeSource: "Yape", fromEmail: true) == "o:yape")
    }

    // MARK: - Destinatario

    @Test("El destinatario sale del prefijo; los rellenos de los parsers no son personas")
    func destinatarios() {
        #expect(AccountResolver.payee(merchant: "PLIN - Joseph Martinez")?.name == "Joseph Martinez")
        #expect(AccountResolver.payee(merchant: "PLIN - Joseph Martinez")?.via == .plin)
        #expect(AccountResolver.payee(merchant: "YAPE - Desconocido") == nil)
        #expect(AccountResolver.payee(merchant: "BBVA - Transferencia a terceros") == nil)
        #expect(AccountResolver.payee(merchant: "TOTTUS") == nil)
    }

    @Test("Mayúsculas, tildes y espacios no cambian la cuenta; otro nombre sí")
    func mismoNombre() {
        let a = AccountResolver.payeeKey("José  Martínez")
        #expect(a == AccountResolver.payeeKey("JOSE MARTINEZ"))
        #expect(a != AccountResolver.payeeKey("JOSE MARTINEZ T"))
    }

    @Test("Sólo los ingresos del correo traen remitente")
    func remitente() {
        #expect(AccountResolver.sender(title: "JOSE MARTINEZ", fromEmail: true) == "JOSE MARTINEZ")
        #expect(AccountResolver.sender(title: "Sueldo", fromEmail: false) == nil)
    }

    // MARK: - Catálogo y preferencias

    @Test("Un origen sin dígitos se une a la única tarjeta de su banco")
    func aliasUnicaTarjeta() {
        let now = Self.day(2026, 9, 10)
        let catalog = AccountCatalog(touches: [
            AccountTouch(origin: "o:bbva:7742", payee: nil, date: now),
            AccountTouch(origin: "o:bbva", payee: ("ANA", .plin), date: now)
        ])
        #expect(catalog.canonical("o:bbva") == "o:bbva:7742")
        #expect(catalog.accounts["o:bbva:7742"]?.count == 2)
        #expect(catalog.accounts["o:bbva"] == nil)
    }

    @Test("Con dos tarjetas del banco, el origen sin dígitos queda aparte")
    func sinAliasConDosTarjetas() {
        let now = Self.day(2026, 9, 10)
        let catalog = AccountCatalog(touches: [
            AccountTouch(origin: "o:bbva:7742", payee: nil, date: now),
            AccountTouch(origin: "o:bbva:1234", payee: nil, date: now),
            AccountTouch(origin: "o:bbva", payee: nil, date: now)
        ])
        #expect(catalog.canonical("o:bbva") == "o:bbva")
        #expect(catalog.accounts.count == 3)
    }

    @Test("Por defecto las tarjetas son tuyas y los destinatarios no")
    func porDefecto() {
        var prefs = AccountPreferences()
        #expect(prefs.isMine("o:yape"))
        #expect(!prefs.isMine("p:ANA"))
        #expect(prefs.minePayees.isEmpty)
        prefs.mine["p:ANA"] = true
        prefs.mine["o:yape"] = false
        #expect(prefs.minePayees == ["p:ANA"])
        #expect(!prefs.isMine("o:yape"))
    }

    @Test("El carrusel respeta el orden elegido y luego va por movimientos")
    func ordenCarrusel() {
        let now = Self.day(2026, 9, 10)
        let catalog = AccountCatalog(touches: [
            AccountTouch(origin: "o:yape", payee: nil, date: now),
            AccountTouch(origin: "o:bcp:0456", payee: nil, date: now),
            AccountTouch(origin: "o:bcp:0456", payee: nil, date: now),
            AccountTouch(origin: "o:interbank", payee: nil, date: now)
        ])
        var prefs = AccountPreferences()
        prefs.order = ["o:interbank"]
        #expect(prefs.carousel(from: catalog).map(\.key) == ["o:interbank", "o:bcp:0456", "o:yape"])
    }

    // MARK: - Traslados

    @Test("Traslado sólo si el destinatario está marcado como tuyo")
    func reglaDeTraslado() {
        let mine: Set<String> = [AccountResolver.payeeKey("Joseph Martinez")]
        #expect(TransferDetector.isTransfer(payeeKey: AccountResolver.payeeKey("JOSEPH MARTINEZ"), minePayees: mine))
        #expect(!TransferDetector.isTransfer(payeeKey: AccountResolver.payeeKey("Ana"), minePayees: mine))
        #expect(!TransferDetector.isTransfer(payeeKey: nil, minePayees: mine))
    }

    @Test("Se empareja la salida con la entrada del mismo monto más cercana, dentro de la ventana")
    func emparejado() {
        let out = UUID(), near = UUID(), far = UUID(), other = UUID()
        let t = Self.day(2026, 9, 10, hour: 10)
        let pairs = TransferDetector.pairs(
            outgoing: [.init(id: out, cents: 20000, currency: "PEN", date: t)],
            incoming: [
                .init(id: far, cents: 20000, currency: "PEN", date: t.addingTimeInterval(20 * 60)),
                .init(id: near, cents: 20000, currency: "PEN", date: t.addingTimeInterval(60)),
                .init(id: other, cents: 15000, currency: "PEN", date: t)
            ])
        #expect(pairs == [out: near])

        let late = TransferDetector.pairs(
            outgoing: [.init(id: out, cents: 20000, currency: "PEN", date: t)],
            incoming: [.init(id: far, cents: 20000, currency: "PEN", date: t.addingTimeInterval(3 * 3600))])
        #expect(late.isEmpty)
    }

    @Test("Un traslado no suma: ni gasto, ni ingreso, ni categoría, ni coste neto")
    func contabilidad() {
        let period = Period(granularity: .mes, reference: Self.day(2026, 9, 15))
        let expenses = [
            ExpenseSnapshot(amount: 50, date: Self.day(2026, 9, 10), category: "Comida", merchant: "WONG"),
            ExpenseSnapshot(amount: 200, date: Self.day(2026, 9, 10), category: Accounting.unclassified,
                            merchant: "PLIN - YO", isTransfer: true)
        ]
        let incomes = [
            IncomeSnapshot(amount: 1000, date: Self.day(2026, 9, 1)),
            IncomeSnapshot(amount: 200, date: Self.day(2026, 9, 10), isTransfer: true)
        ]
        let totals = Accounting.totals(expenses: expenses, incomes: incomes, period: period, usdToPen: 3.7)
        #expect(Money.cents(totals.spent) == 5000)
        #expect(Money.cents(totals.income) == 100000)
        #expect(Money.isZero(totals.unclassifiedTotal))
        #expect(Money.isZero(Accounting.netCost(of: expenses[1])))
    }
}

extension MoneyAccountsTests {
    @Test("Una tarjeta sin banco con los dígitos de una de banco es esa tarjeta")
    func tarjetaSueltaSeUne() {
        let now = Self.day(2026, 9, 10)
        let catalog = AccountCatalog(touches: [
            AccountTouch(origin: "o:bcp:4016", payee: nil, date: now),
            AccountTouch(origin: "o:tarjeta:4016", payee: nil, date: now),
            AccountTouch(origin: "o:tarjeta:8156", payee: nil, date: now)
        ])
        #expect(catalog.canonical("o:tarjeta:4016") == "o:bcp:4016")
        #expect(catalog.accounts["o:bcp:4016"]?.count == 2)
        #expect(catalog.canonical("o:tarjeta:8156") == "o:tarjeta:8156")
    }
}

// MARK: - Correo real

extension MoneyAccountsTests {

    /// «Constancia de operación transferencia PLIN» de BBVA (16/09/2026), tal
    /// como queda tras quitarle el HTML en `GmailSyncService.extractFullText`:
    /// etiquetas por espacios, `&nbsp;` por espacio, `&bull;` fuera.
    static let bbvaPlinEmail = """
        Hola, JOSEPH  &nbsp;     Plineaste S/ 100.00 a LECSSI DANIELA YUPARI ERAZO        \
        Detalles de tu plineo       Concepto:   CODEBREAK      Celular:   7209     \
        Destino:   Plin     ITF:   S/ 0.00     Fecha y hora:   16 de setiembre, 2026 19:59     \
        Número de operación:   0000000940       ¿Necesitas pagar tus servicios rápido y fácil?  \
        Hazlo con Plin BBVA.   Muchas gracias,  El equipo de BBVA.
        """

    @Test("Plin de BBVA: destinatario, monto, fecha y «Destino: Plin»")
    func plinBBVAReal() throws {
        let expense = try #require(BBVAParser().parse(cleanText: Self.bbvaPlinEmail))
        #expect(expense.merchant == "PLIN - LECSSI DANIELA YUPARI ERAZO")
        #expect(Money.cents(expense.amount) == 10000)
        #expect(expense.date == Self.day(2026, 9, 16, hour: 19, minute: 59))
        #expect(EmailAccountDetails.destinationWallet(in: Self.bbvaPlinEmail) == "Plin")
        #expect(EmailAccountDetails.payeePhone(in: Self.bbvaPlinEmail) == "7209")

        // Sale de BBVA y va a esa persona: si la marcas como tuya, es traslado.
        #expect(AccountResolver.originKey(sourceBank: "BBVA", merchant: expense.merchant,
                                          cardLastDigits: expense.cardLastDigits, fromEmail: true) == "o:bbva")
        #expect(AccountResolver.payee(merchant: expense.merchant)?.name == "LECSSI DANIELA YUPARI ERAZO")
    }

    @Test("«Destino» sólo acepta bancos y billeteras conocidos")
    func destinoDesconocido() {
        #expect(EmailAccountDetails.destinationWallet(in: "Destino: Yape  ITF") == "Yape")
        #expect(EmailAccountDetails.destinationWallet(in: "Destino: Caja Arequipa  ITF") == nil)
        #expect(EmailAccountDetails.destinationWallet(in: "Sin ese campo") == nil)
    }
}

extension MoneyAccountsTests {

    @Test("Celular: los tres formatos de máscara, y sólo los cuatro últimos")
    func celulares() {
        #expect(EmailAccountDetails.payeePhone(in: "Celular del Beneficiario *** *** 913 Destino") == "913")
        #expect(EmailAccountDetails.payeePhone(in: "Enviado a: Johel Mac*** *** *** 913 Con Plin enviaste") == "913")
        #expect(EmailAccountDetails.payeePhone(in: "Celular: 987 654 321  Fecha") == "4321")
        // El número de operación que viene detrás no se pega al celular.
        #expect(EmailAccountDetails.payeePhone(in: "Celular:   7209     0000000940") == "7209")
        #expect(EmailAccountDetails.payeePhone(in: "Sin ese campo") == nil)
    }

    @Test("Débito o crédito sólo junto a los mismos dígitos")
    func tipoDeTarjeta() {
        let bcp = "Realizaste un consumo con tu Tarjeta de Crédito BCP ****4016 en WONG"
        #expect(EmailAccountDetails.cardKind(in: bcp, digits: "4016") == "Crédito")
        #expect(EmailAccountDetails.cardKind(in: bcp, digits: "9999") == nil)
        #expect(EmailAccountDetails.cardKind(in: "Pide tu Tarjeta de Débito hoy. tarjeta terminada en *8156",
                                             digits: "8156") == nil)
    }

    @Test("Dos tarjetas del mismo banco se nombran por su tipo; el celular va al destinatario")
    func nombresPorTipo() {
        let now = Self.day(2026, 9, 10)
        let catalog = AccountCatalog(touches: [
            AccountTouch(origin: "o:bbva:2368", payee: nil, date: now, cardKind: "Débito"),
            AccountTouch(origin: "o:bbva:8156", payee: nil, date: now, cardKind: "Crédito"),
            AccountTouch(origin: "o:bbva", payee: ("LECSSI DANIELA YUPARI ERAZO", .plin), date: now,
                         payeePhone: "7209")
        ])
        let prefs = AccountPreferences()
        #expect(catalog.accounts["o:bbva:2368"].map(prefs.name(for:)) == "BBVA Débito")
        #expect(catalog.accounts["o:bbva:8156"].map(prefs.name(for:)) == "BBVA Crédito")
        #expect(catalog.accounts[AccountResolver.payeeKey("LECSSI DANIELA YUPARI ERAZO")]?.phone == "7209")
    }

    @Test("Con dos tarjetas del banco, el Plin sin dígitos va a la de débito")
    func plinALaDeDebito() {
        let now = Self.day(2026, 9, 10)
        let catalog = AccountCatalog(touches: [
            AccountTouch(origin: "o:bbva:2368", payee: nil, date: now, cardKind: "Débito"),
            AccountTouch(origin: "o:bbva:8156", payee: nil, date: now, cardKind: "Crédito"),
            AccountTouch(origin: "o:bbva", payee: ("ANA", .plin), date: now)
        ])
        #expect(catalog.canonical("o:bbva") == "o:bbva:2368")
        #expect(catalog.accounts["o:bbva:2368"]?.count == 2)
    }

    @Test("Plin no es una tarjeta: un Plin recibido va al banco del último Plin enviado")
    func plinRecibido() {
        let march = Self.day(2026, 3, 10), june = Self.day(2026, 6, 10)
        let catalog = AccountCatalog(touches: [
            AccountTouch(origin: "o:bbva:2368", payee: ("ANA", .plin), date: march, isPlinSend: true),
            AccountTouch(origin: "o:scotiabank", payee: ("LUIS", .plin), date: june, isPlinSend: true),
            AccountTouch(origin: "o:plin", payee: nil, date: Self.day(2026, 4, 1)),
            AccountTouch(origin: "o:plin", payee: nil, date: Self.day(2026, 7, 1))
        ])
        #expect(catalog.accounts["o:plin"] == nil)
        #expect(catalog.resolve("o:plin", at: Self.day(2026, 4, 1)) == "o:bbva:2368")
        #expect(catalog.resolve("o:plin", at: Self.day(2026, 7, 1)) == "o:scotiabank")
        // Antes del primer Plin enviado: al primero que haya.
        #expect(catalog.resolve("o:plin", at: Self.day(2026, 1, 1)) == "o:bbva:2368")
        #expect(catalog.accounts["o:bbva:2368"]?.count == 2)
    }

    @Test("Sin ningún Plin enviado, un Plin recibido no cae en ninguna tarjeta")
    func plinSinBanco() {
        let catalog = AccountCatalog(touches: [
            AccountTouch(origin: "o:plin", payee: nil, date: Self.day(2026, 4, 1))
        ])
        #expect(catalog.accounts.isEmpty)
        #expect(catalog.resolve("o:plin", at: Self.day(2026, 4, 1)) == nil)
    }
}

// MARK: - Retiros BBVA (correos reales)

extension MoneyAccountsTests {

    /// «BBVA - Constancia Retiro sin tarjeta» (16/09/2026), sin el HTML.
    static let bbvaCardlessEmail = """
        Hola, JOSEPH ALA  &nbsp;   Tu retiro sin tarjeta de S/ 200 está listo       \
        Número de celular del retiro:&ensp; ******9621        Retira tu dinero hasta el 17 de setiembre \
        de 2026 a las 21:14. Encuentra la clave en el &#39;Historial retiro sin tarjeta&#39; en el menú \
        dentro de tu app.        Más detalles de la operación     Cuenta de Origen:     Cuenta Digital *2368    \
        Titular de la Cuenta:     JOSEPH ALA MOTTOCCANC TANTARUNA    Fecha y hora de la operación:     \
        16 de setiembre de 2026 21:14    Numero de operación:     32577005    Estado     Por cobrar     \
        Opciones de retiro     Cajeros o agentes
        """

    /// «BBVA - Constancia de Retiro en ATM» (25/07/2026, formato antiguo), sin el HTML.
    static let bbvaATMEmail = """
        Hola, Joseph   Has realizado con éxito la operación:   Retiro de efectivo    Monto de retiro   \
        S/  70.00      Comisión S/  0.00  ITF  S/  0.00   Saldo disponible  S/  68,734.03      \
        DETALLES DE LA OPERACIÓN   Titular de la cuenta   Joseph Alan Mottoccanche Tanta    Tipo de operación \
        Retiro de efectivo   Fecha y hora de la operación  25 de julio, 2026 07:57:29    Número de operación \
        000000001315   Cajero  0745   Número de tarjeta  · 8156     Número de cuenta  · 2368     \
        Nombre de la aplicación(EMV)  VISA CREDITO    Identificador AID  A0000000031010   \
        ¡Tus RETIROS SIN TARJETA son gratis! Hazlo generando la clave en tu APP BBVA
        """

    @Test("Retiro sin tarjeta: S/ 200 de la Cuenta Digital 2368, con fecha de la operación")
    func retiroSinTarjeta() throws {
        let text = Self.bbvaCardlessEmail
        let expense = try #require(BBVAParser().parse(cleanText: text))
        #expect(expense.merchant == "RETIRO - Sin tarjeta")
        #expect(Money.cents(expense.amount) == 20000)
        #expect(expense.currency == "PEN")
        #expect(expense.cardLastDigits == "2368")
        #expect(expense.date == Self.day(2026, 9, 16, hour: 21, minute: 14))
        #expect(EmailAccountDetails.cardKind(in: text, digits: "2368") == "Cuenta")
        // El celular del retiro es el tuyo, no el de un destinatario.
        #expect(EmailAccountDetails.payeePhone(in: text) == nil)
        #expect(expense.isCashWithdrawal)
        #expect(expense.payeeKey == nil)
    }

    @Test("Retiro en cajero: S/ 70 de la tarjeta de crédito 8156, no del saldo ni de la cuenta")
    func retiroEnCajero() throws {
        let text = Self.bbvaATMEmail
        let expense = try #require(BBVAParser().parse(cleanText: text))
        #expect(expense.merchant == "RETIRO - Cajero")
        #expect(Money.cents(expense.amount) == 7000)
        #expect(expense.cardLastDigits == "8156")
        #expect(expense.date == Self.day(2026, 7, 25, hour: 7, minute: 57))
        #expect(EmailAccountDetails.cardKind(in: text, digits: "8156") == "Crédito")
        #expect(AccountResolver.originKey(sourceBank: "BBVA", merchant: expense.merchant,
                                          cardLastDigits: expense.cardLastDigits, fromEmail: true) == "o:bbva:8156")
    }

    @Test("Un retiro siempre es traslado, aunque no haya destinatarios marcados")
    func retiroEsTraslado() {
        #expect(TransferDetector.isTransfer(payeeKey: nil, minePayees: [], isCashWithdrawal: true))
    }

    @Test("Con cuenta y tarjeta de crédito del mismo banco, el Plin va a la cuenta")
    func plinALaCuenta() {
        let now = Self.day(2026, 9, 10)
        let catalog = AccountCatalog(touches: [
            AccountTouch(origin: "o:bbva:2368", payee: nil, date: now, cardKind: "Cuenta"),
            AccountTouch(origin: "o:bbva:8156", payee: nil, date: now, cardKind: "Crédito"),
            AccountTouch(origin: "o:bbva", payee: ("ANA", .plin), date: now, isPlinSend: true)
        ])
        #expect(catalog.canonical("o:bbva") == "o:bbva:2368")
        let prefs = AccountPreferences()
        #expect(catalog.accounts["o:bbva:2368"].map(prefs.name(for:)) == "BBVA Cuenta")
        #expect(catalog.accounts["o:bbva:8156"].map(prefs.name(for:)) == "BBVA Crédito")
    }
}
