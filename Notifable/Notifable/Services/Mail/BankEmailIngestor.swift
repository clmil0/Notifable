import Foundation
import SwiftData

/// Lo que hay que hacer con el texto de un correo, venga de donde venga.
///
/// Se separó de `GmailSyncService` al añadir iCloud: interpretar el aviso,
/// aplicar la regla de categoría y decidir si se inserta o se funde con un
/// gasto que ya estaba es idéntico para los dos proveedores, y tenerlo dos
/// veces habría hecho que las reglas se separaran a la primera corrección.
/// El proveedor sólo aporta **cómo se consiguen los correos**; a partir del
/// texto, todo pasa por aquí.
enum BankEmailIngestor {

    /// Los parsers de banco. Única lista: añadir un banco lo activa en Gmail y
    /// en iCloud a la vez.
    static let parsers: [BankEmailParser] = [
        BBVAParser(),
        BCPParser(),
        YapeParser(),
        InterbankParser(),
        ScotiabankParser(),
        AppleParser()
    ]

    /// Todas las direcciones que interesan, para preguntar por ellas.
    static var senderEmails: [String] {
        parsers.flatMap(\.senderEmails)
    }

    struct Parsed {
        var expense: Expense?
        var income: Income?
        var bankName: String
    }

    // MARK: - Interpretar

    /// Prueba el texto contra cada parser. Devuelve `nil` si ninguno lo
    /// reconoce, que es lo normal: al buzón llegan muchos correos del banco que
    /// no son un movimiento.
    static func parse(_ text: String) -> Parsed? {
        let cleanText = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")

        for parser in parsers {
            if let expense = parser.parse(cleanText: cleanText) {
                return Parsed(expense: autoCategorize(expense), income: nil, bankName: parser.bankName)
            }
        }

        // Un correo no puede ser gasto e ingreso a la vez: sólo se prueba
        // parseIncome cuando ningún parser lo reconoció como gasto.
        for parser in parsers {
            if let income = parser.parseIncome(cleanText: cleanText) {
                return Parsed(expense: nil, income: income, bankName: parser.bankName)
            }
        }
        return nil
    }

    // MARK: - Clasificar

    static func autoCategorize(_ expense: Expense) -> Expense {
        // Una regla que el usuario ya definió en la Bandeja manda sobre todo lo
        // demás: para eso la definió.
        if let rule = MerchantRules.category(for: expense.merchant) {
            expense.category = rule
            expense.isSubscription = rule == "Entretenimiento"
            return expense
        }

        var autoCategory = Accounting.unclassified
        let lowerMerchant = expense.merchant.lowercased()
        if lowerMerchant.contains("starbucks") || lowerMerchant.contains("eats")
            || lowerMerchant.contains("tambo") || lowerMerchant.contains("sharethemeal") {
            autoCategory = "Comida"
        } else if lowerMerchant.contains("uber") || lowerMerchant.contains("lyft")
            || lowerMerchant.contains("didi") || lowerMerchant.contains("cabify")
            || lowerMerchant.contains("yango") {
            autoCategory = "Transporte"
        } else if lowerMerchant.contains("netflix") || lowerMerchant.contains("spotify")
            || lowerMerchant.contains("apple") || lowerMerchant.contains("disney")
            || lowerMerchant.contains("prime") {
            autoCategory = "Entretenimiento"
        }

        expense.category = autoCategory
        expense.isSubscription = autoCategory == "Entretenimiento"
        return expense
    }

    // MARK: - Guardar

    /// Inserta el gasto, o lo funde con el que ya existe si son las dos caras
    /// del mismo cobro de Apple (el recibo de Apple y el cargo del banco).
    /// - Important: el `ModelContext` llega por parámetro y **el llamador es
    ///   responsable de invocar esto en el hilo del contexto**. No se marca
    ///   `@MainActor` a propósito: Gmail entra desde un `DispatchQueue.main.sync`
    ///   dentro de un callback de red, que está en el hilo principal pero fuera
    ///   del ejecutor del actor, y exigir el actor ahí obligaría a un
    ///   `assumeIsolated` que en ese contexto aborta el proceso.
    @discardableResult
    static func insert(expense newExpense: Expense,
                       bankName: String,
                       emailID: String,
                       context: ModelContext) -> Bool {

        let isAppleReceipt = bankName == "Apple"
        let isAppleBankBill = !isAppleReceipt && newExpense.merchant.lowercased().contains("apple")

        if isAppleReceipt || isAppleBankBill {
            let amount = newExpense.amount
            let date = newExpense.date
            let allExpenses = (try? context.fetch(FetchDescriptor<Expense>())) ?? []

            if let match = allExpenses.first(where: {
                $0.id != newExpense.id &&
                $0.relatedEmailID == nil &&
                $0.amount == amount &&
                abs($0.date.timeIntervalSince(date)) <= 48 * 3600 &&
                ($0.merchant.lowercased().contains("apple") || $0.merchant == "Apple")
            }) {
                if isAppleReceipt {
                    match.merchant = newExpense.merchant == "Apple" ? match.merchant : "Apple: \(newExpense.merchant)"
                    if let notes = newExpense.notes { match.notes = notes }
                    match.isSubscription = newExpense.isSubscription
                    match.category = newExpense.category
                    match.relatedEmailID = emailID
                } else {
                    // La factura de Apple sólo trae el día —sin hora, queda en
                    // 00:00—, así que la hora real la pone el correo del banco.
                    match.date = date
                    if let card = newExpense.cardLastDigits { match.cardLastDigits = card }
                    match.relatedEmailID = emailID
                }
                try? context.save()
                return true
            }
        }

        if isAppleReceipt {
            // Sin el prefijo "Apple:", este gasto se guarda con el nombre del
            // plan y, cuando el cargo del banco llegue después, la búsqueda por
            // `merchant.contains("apple")` no lo encuentra y se duplica.
            newExpense.merchant = newExpense.merchant == "Apple" ? newExpense.merchant : "Apple: \(newExpense.merchant)"
        }

        newExpense.emailID = emailID
        context.insert(newExpense)
        try? context.save()
        return true
    }

    /// Constancias de dinero recibido. No hay vínculo con Apple ni
    /// deduplicación especial: el `emailID` ya evita procesarlo dos veces.
    @discardableResult
    static func insert(income: Income, emailID: String, context: ModelContext) -> Bool {
        income.emailID = emailID
        context.insert(income)
        try? context.save()
        return true
    }

    /// Correos que ya se convirtieron en un movimiento que sigue en la base.
    ///
    /// La deduplicación no puede depender sólo de la lista de procesados: esa
    /// se borra al restablecer la sincronización o al reinstalar, y entonces el
    /// mismo rango se importaría dos veces.
    static func existingEmailIDs(in context: ModelContext) -> Set<String> {
        let expenses = (try? context.fetch(FetchDescriptor<Expense>())) ?? []
        let incomes = (try? context.fetch(FetchDescriptor<Income>())) ?? []
        return Set(expenses.compactMap(\.emailID)).union(incomes.compactMap(\.emailID))
    }
}
