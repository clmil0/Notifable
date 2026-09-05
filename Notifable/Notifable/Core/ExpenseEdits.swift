import Foundation
import SwiftData

/// Lo que el usuario cambió a mano en un gasto que vino del correo.
///
/// El problema que resuelve: esos gastos **no se respaldan** —se reconstruyen
/// releyendo Gmail— pero las decisiones que el usuario tomó sobre ellos no
/// están en ningún correo. Si cambia "YAPE - JORGE M." por "Cena con Jorge",
/// lo mueve a Salud o corrige el monto, al releer el correo vuelve todo como
/// lo mandó el banco.
///
/// Antes esto se intentaba **deducir** comparando la categoría del gasto con
/// la regla de comercio. Deducir falla en los dos sentidos: no ve un cambio de
/// nombre o de fecha, y se equivoca cuando la regla coincide por casualidad.
/// Aquí se registra en el momento en que el usuario lo hace, que es la única
/// fuente fiable de "esto lo decidí yo".
///
/// La llave es `TransactionKey`, no el `UUID`: el gasto se borra y se vuelve a
/// crear en cada relectura, pero su correo es siempre el mismo.
struct ExpenseEdit: Codable, Equatable {

    var markKey: String
    /// `nil` en cada campo significa "esto no lo tocó": se respeta lo que diga
    /// el correo. Guardar el valor original sería congelar un dato que el
    /// parser puede mejorar en la siguiente versión.
    var category: String?
    var merchant: String?
    var amount: Double?
    var occurredAt: Date?
    var notes: String?
    var isSubscription: Bool?
    var isDebt: Bool?
    var cardLastDigits: String?
    var updatedAt: Date = Date()

    var isEmpty: Bool {
        category == nil && merchant == nil && amount == nil && occurredAt == nil
            && notes == nil && isSubscription == nil && isDebt == nil && cardLastDigits == nil
    }

    /// Lo nuevo pisa a lo viejo campo por campo: dos ediciones distintas del
    /// mismo gasto se acumulan en vez de perderse la primera.
    func merged(with newer: ExpenseEdit) -> ExpenseEdit {
        ExpenseEdit(markKey: markKey,
                    category: newer.category ?? category,
                    merchant: newer.merchant ?? merchant,
                    amount: newer.amount ?? amount,
                    occurredAt: newer.occurredAt ?? occurredAt,
                    notes: newer.notes ?? notes,
                    isSubscription: newer.isSubscription ?? isSubscription,
                    isDebt: newer.isDebt ?? isDebt,
                    cardLastDigits: newer.cardLastDigits ?? cardLastDigits,
                    updatedAt: max(updatedAt, newer.updatedAt))
    }

    enum CodingKeys: String, CodingKey {
        case markKey, category, merchant, amount, occurredAt, notes
        case isSubscription, isDebt, cardLastDigits, updatedAt
    }

    init(markKey: String, category: String? = nil, merchant: String? = nil,
         amount: Double? = nil, occurredAt: Date? = nil, notes: String? = nil,
         isSubscription: Bool? = nil, isDebt: Bool? = nil,
         cardLastDigits: String? = nil, updatedAt: Date = Date()) {
        self.markKey = markKey
        self.category = category
        self.merchant = merchant
        self.amount = amount.map(Money.normalized)
        self.occurredAt = occurredAt
        self.notes = notes
        self.isSubscription = isSubscription
        self.isDebt = isDebt
        self.cardLastDigits = cardLastDigits
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        markKey = try c.decode(String.self, forKey: .markKey)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        merchant = try c.decodeIfPresent(String.self, forKey: .merchant)
        // El monto viaja como texto decimal exacto (ver MoneyCoding); se
        // aceptan las dos formas para no romper respaldos anteriores.
        if let text = try? c.decodeIfPresent(String.self, forKey: .amount) {
            // `Double(text)`, no `text.flatMap(Double.init)`: sobre un String ya
            // desenvuelto, flatMap recorre sus caracteres y devuelve [Double].
            amount = Double(text).map(Money.normalized)
        } else if let number = try? c.decodeIfPresent(Double.self, forKey: .amount) {
            amount = Money.normalized(number)
        } else {
            amount = nil
        }
        occurredAt = try c.decodeIfPresent(Date.self, forKey: .occurredAt)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        isSubscription = try c.decodeIfPresent(Bool.self, forKey: .isSubscription)
        isDebt = try c.decodeIfPresent(Bool.self, forKey: .isDebt)
        cardLastDigits = try c.decodeIfPresent(String.self, forKey: .cardLastDigits)
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(markKey, forKey: .markKey)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(merchant, forKey: .merchant)
        try c.encodeIfPresent(amount.map(Money.decimalText), forKey: .amount)
        try c.encodeIfPresent(occurredAt, forKey: .occurredAt)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(isSubscription, forKey: .isSubscription)
        try c.encodeIfPresent(isDebt, forKey: .isDebt)
        try c.encodeIfPresent(cardLastDigits, forKey: .cardLastDigits)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

/// El registro de ediciones, en `UserDefaults`.
///
/// Vive fuera de SwiftData a propósito: tiene que sobrevivir a "Volver a leer
/// el correo desde cero", que borra los gastos precisamente para rearmarlos.
enum ExpenseEditStore {

    static let key = "expenseEdits"

    // MARK: - Leer

    static func all(_ defaults: UserDefaults = .standard) -> [String: ExpenseEdit] {
        guard let data = defaults.data(forKey: key),
              let list = try? decoder.decode([ExpenseEdit].self, from: data) else { return [:] }
        return Dictionary(list.map { ($0.markKey, $0) }, uniquingKeysWith: { $1 })
    }

    static func list(_ defaults: UserDefaults = .standard) -> [ExpenseEdit] {
        all(defaults).values.sorted { $0.markKey < $1.markKey }
    }

    // MARK: - Escribir

    /// Registra una edición. Sólo para gastos con correo detrás: los creados a
    /// mano se respaldan enteros, así que anotar sus cambios sería duplicar.
    static func record(_ expense: Expense,
                       category: String? = nil,
                       merchant: String? = nil,
                       amount: Double? = nil,
                       occurredAt: Date? = nil,
                       notes: String? = nil,
                       isSubscription: Bool? = nil,
                       isDebt: Bool? = nil,
                       cardLastDigits: String? = nil,
                       defaults: UserDefaults = .standard) {
        guard expense.emailID != nil else { return }
        let edit = ExpenseEdit(markKey: TransactionKey.key(for: expense),
                               category: category, merchant: merchant, amount: amount,
                               occurredAt: occurredAt, notes: notes,
                               isSubscription: isSubscription, isDebt: isDebt,
                               cardLastDigits: cardLastDigits)
        guard !edit.isEmpty else { return }
        save(edit, defaults: defaults)
    }

    static func save(_ edit: ExpenseEdit, defaults: UserDefaults = .standard) {
        var current = all(defaults)
        current[edit.markKey] = current[edit.markKey]?.merged(with: edit) ?? edit
        persist(current, defaults: defaults)
    }

    /// Lo que llega de un respaldo se funde con lo local en vez de sustituirlo:
    /// restaurar no puede borrar una edición hecha en este teléfono.
    static func merge(_ incoming: [ExpenseEdit], defaults: UserDefaults = .standard) {
        var current = all(defaults)
        for edit in incoming {
            if let existing = current[edit.markKey] {
                current[edit.markKey] = existing.updatedAt >= edit.updatedAt
                    ? existing.merged(with: edit)
                    : edit.merged(with: existing)
            } else {
                current[edit.markKey] = edit
            }
        }
        persist(current, defaults: defaults)
    }

    static func removeAll(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    private static func persist(_ edits: [String: ExpenseEdit], defaults: UserDefaults) {
        let encoded = (try? encoder.encode(edits.values.sorted { $0.markKey < $1.markKey })) ?? Data()
        defaults.set(encoded, forKey: key)
    }

    // MARK: - Aplicar

    /// Vuelve a poner las ediciones sobre los gastos que existan ahora. Es
    /// barata e idempotente: la llama `GmailSyncService` al terminar cada
    /// lectura, que es cuando los gastos acaban de rearmarse.
    @discardableResult
    static func apply(in modelContext: ModelContext, defaults: UserDefaults = .standard) -> Int {
        let edits = all(defaults)
        guard !edits.isEmpty else { return 0 }

        let expenses = (try? modelContext.fetch(FetchDescriptor<Expense>())) ?? []
        guard !expenses.isEmpty else { return 0 }

        var applied = 0
        for expense in expenses {
            guard let edit = edits[TransactionKey.key(for: expense)] else { continue }
            var touched = false
            if let value = edit.category, expense.category != value { expense.category = value; touched = true }
            if let value = edit.merchant, expense.merchant != value { expense.merchant = value; touched = true }
            if let value = edit.amount, Money.cents(expense.amount) != Money.cents(value) {
                expense.amount = value; touched = true
            }
            if let value = edit.occurredAt, expense.date != value { expense.date = value; touched = true }
            if let value = edit.notes, expense.notes != value { expense.notes = value; touched = true }
            if let value = edit.isSubscription, expense.isSubscription != value {
                expense.isSubscription = value; touched = true
            }
            if let value = edit.isDebt, expense.isDebt != value { expense.isDebt = value; touched = true }
            if let value = edit.cardLastDigits, expense.cardLastDigits != value {
                expense.cardLastDigits = value; touched = true
            }
            if touched { applied += 1 }
        }
        if applied > 0 { try? modelContext.save() }
        return applied
    }

    // MARK: - Codificación

    private static var encoder: JSONEncoder { ConfigBackupManager.makeEncoder() }
    private static var decoder: JSONDecoder { ConfigBackupManager.makeDecoder() }
}
