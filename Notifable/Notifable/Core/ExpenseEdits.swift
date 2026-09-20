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
    /// Las etiquetas del gasto, **enteras**. Sin esto, etiquetar un gasto que
    /// vino del correo se perdía en la siguiente lectura: el gasto se borra y
    /// se rearma, y la etiqueta no está en ningún correo.
    var tags: [String]?
    var merchant: String?
    var amount: Double?
    var occurredAt: Date?
    var notes: String?
    var isSubscription: Bool?
    var isDebt: Bool?
    var debtSettled: Bool?
    var cardLastDigits: String?
    /// Soles por dólar con que se registró el gasto la primera vez. No es una
    /// edición del usuario sino un dato que el correo no trae: al releerlo en
    /// otro teléfono el gasto nacería con el tipo de cambio de ese día y los
    /// meses pasados en USD cambiarían. Viaja por el mismo camino que las
    /// ediciones porque usa la misma llave. Ver `recordFxRate`.
    var fxRate: Double?
    var updatedAt: Date = Date()

    var isEmpty: Bool { !isUserEdit && fxRate == nil }

    /// Algo que el usuario cambió a mano. Lo que cuenta Ajustes y la
    /// advertencia de reemplazar la copia: el tipo de cambio no lo es.
    var isUserEdit: Bool {
        category != nil || tags != nil || merchant != nil || amount != nil || occurredAt != nil
            || notes != nil || isSubscription != nil || isDebt != nil || debtSettled != nil
            || cardLastDigits != nil
    }

    /// Lo nuevo pisa a lo viejo campo por campo: dos ediciones distintas del
    /// mismo gasto se acumulan en vez de perderse la primera.
    func merged(with newer: ExpenseEdit) -> ExpenseEdit {
        ExpenseEdit(markKey: markKey,
                    category: newer.category ?? category,
                    // La lista más nueva gana **entera**, no elemento a
                    // elemento: unir las dos haría que quitar una etiqueta
                    // perdiera siempre contra haberla puesto antes.
                    tags: newer.tags ?? tags,
                    merchant: newer.merchant ?? merchant,
                    amount: newer.amount ?? amount,
                    occurredAt: newer.occurredAt ?? occurredAt,
                    notes: newer.notes ?? notes,
                    isSubscription: newer.isSubscription ?? isSubscription,
                    isDebt: newer.isDebt ?? isDebt,
                    debtSettled: newer.debtSettled ?? debtSettled,
                    cardLastDigits: newer.cardLastDigits ?? cardLastDigits,
                    // Al revés que el resto: gana el **primero**. El tipo de
                    // cambio que vale es el del día del gasto, no el de una
                    // relectura posterior en otro teléfono.
                    fxRate: fxRate ?? newer.fxRate,
                    updatedAt: max(updatedAt, newer.updatedAt))
    }

    enum CodingKeys: String, CodingKey {
        case markKey, category, tags, merchant, amount, occurredAt, notes
        case isSubscription, isDebt, debtSettled, cardLastDigits, fxRate, updatedAt
    }

    init(markKey: String, category: String? = nil, tags: [String]? = nil, merchant: String? = nil,
         amount: Double? = nil, occurredAt: Date? = nil, notes: String? = nil,
         isSubscription: Bool? = nil, isDebt: Bool? = nil, debtSettled: Bool? = nil,
         cardLastDigits: String? = nil, fxRate: Double? = nil, updatedAt: Date = Date()) {
        self.markKey = markKey
        self.category = category
        self.tags = tags
        self.merchant = merchant
        self.amount = amount.map(Money.normalized)
        self.occurredAt = occurredAt
        self.notes = notes
        self.isSubscription = isSubscription
        self.isDebt = isDebt
        self.debtSettled = debtSettled
        self.cardLastDigits = cardLastDigits
        self.fxRate = fxRate
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        markKey = try c.decode(String.self, forKey: .markKey)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        tags = try c.decodeIfPresent([String].self, forKey: .tags)
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
        debtSettled = try c.decodeIfPresent(Bool.self, forKey: .debtSettled)
        cardLastDigits = try c.decodeIfPresent(String.self, forKey: .cardLastDigits)
        fxRate = (try? c.decodeIfPresent(RateCoded.self, forKey: .fxRate))??.wrappedValue
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(markKey, forKey: .markKey)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(tags, forKey: .tags)
        try c.encodeIfPresent(merchant, forKey: .merchant)
        try c.encodeIfPresent(amount.map(Money.decimalText), forKey: .amount)
        try c.encodeIfPresent(occurredAt, forKey: .occurredAt)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(isSubscription, forKey: .isSubscription)
        try c.encodeIfPresent(isDebt, forKey: .isDebt)
        try c.encodeIfPresent(debtSettled, forKey: .debtSettled)
        try c.encodeIfPresent(cardLastDigits, forKey: .cardLastDigits)
        try c.encodeIfPresent(fxRate.map { RateCoded(wrappedValue: $0) }, forKey: .fxRate)
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
                       tags: [String]? = nil,
                       merchant: String? = nil,
                       amount: Double? = nil,
                       occurredAt: Date? = nil,
                       notes: String? = nil,
                       isSubscription: Bool? = nil,
                       isDebt: Bool? = nil,
                       debtSettled: Bool? = nil,
                       cardLastDigits: String? = nil,
                       defaults: UserDefaults = .standard) {
        guard expense.emailID != nil else { return }
        let edit = ExpenseEdit(markKey: TransactionKey.key(for: expense),
                               category: category, tags: tags, merchant: merchant, amount: amount,
                               occurredAt: occurredAt, notes: notes,
                               isSubscription: isSubscription, isDebt: isDebt,
                               debtSettled: debtSettled,
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

    /// Anota el tipo de cambio de un gasto del correo en otra moneda, **sólo
    /// si no había uno**: el primero que se registró es el del día del gasto.
    /// Tras restaurar, el respaldado ya está aquí antes de releer el correo,
    /// así que el que traería la relectura (el de hoy) no lo pisa.
    static func recordFxRate(for expense: Expense, defaults: UserDefaults = .standard) {
        guard expense.emailID != nil, expense.currency != "PEN",
              let rate = expense.fxRateAtCapture, rate.isFinite, rate > 0 else { return }
        let key = TransactionKey.key(for: expense)
        var current = all(defaults)
        if current[key]?.fxRate != nil { return }
        current[key] = current[key]?.merged(with: ExpenseEdit(markKey: key, fxRate: rate))
            ?? ExpenseEdit(markKey: key, fxRate: rate)
        persist(current, defaults: defaults)
    }

    /// `recordFxRate` para todos los gastos en otra moneda que aún no lo
    /// tengan. Cubre los que existían antes de esta versión y los que llegan
    /// en cada lectura del correo; va antes de `apply` para que un tipo de
    /// cambio ya respaldado gane al de la relectura.
    static func captureFxRates(in modelContext: ModelContext, defaults: UserDefaults = .standard) {
        let descriptor = FetchDescriptor<Expense>(predicate: #Predicate {
            $0.emailID != nil && $0.currency != "PEN"
        })
        let expenses = (try? modelContext.fetch(descriptor)) ?? []
        guard !expenses.isEmpty else { return }
        var current = all(defaults)
        var changed = false
        for expense in expenses {
            guard let rate = expense.fxRateAtCapture, rate.isFinite, rate > 0 else { continue }
            let key = TransactionKey.key(for: expense)
            if current[key]?.fxRate != nil { continue }
            current[key] = current[key]?.merged(with: ExpenseEdit(markKey: key, fxRate: rate))
                ?? ExpenseEdit(markKey: key, fxRate: rate)
            changed = true
        }
        if changed { persist(current, defaults: defaults) }
    }

    /// Renombrar, fusionar o borrar una categoría cambia los gastos de hoy,
    /// pero las ediciones guardadas seguían apuntando al nombre viejo: tras
    /// reinstalar, `apply` devolvía esos gastos a una categoría que ya no
    /// existe y el nombre reaparecía. `nil` como destino no se usa: borrar
    /// manda a `Sin Clasificar`, que también es un nombre.
    static func replaceCategory(_ old: String, with new: String, defaults: UserDefaults = .standard) {
        var current = all(defaults)
        var changed = false
        for (key, edit) in current where edit.category == old {
            var updated = edit
            updated.category = new
            updated.updatedAt = Date()
            current[key] = updated
            changed = true
        }
        if changed { persist(current, defaults: defaults) }
    }

    /// Lo mismo que `replaceCategory` para las etiquetas: renombrar, fusionar
    /// o borrar una etiqueta tiene que alcanzar también a las ediciones
    /// guardadas, o tras reinstalar `apply` devolvería el nombre viejo.
    /// `nil` como destino = la etiqueta se quita.
    static func replaceTag(_ old: String, with new: String?, defaults: UserDefaults = .standard) {
        let oldKey = TagCatalog.normalized(old)
        let newKey = new.map(TagCatalog.normalized)
        var current = all(defaults)
        var changed = false
        for (key, edit) in current {
            guard let tags = edit.tags,
                  tags.contains(where: { TagCatalog.normalized($0) == oldKey }) else { continue }
            var list = tags.filter { TagCatalog.normalized($0) != oldKey }
            if let new, let newKey, !list.contains(where: { TagCatalog.normalized($0) == newKey }) {
                list.append(new)
            }
            var updated = edit
            updated.tags = list
            updated.updatedAt = Date()
            current[key] = updated
            changed = true
        }
        if changed { persist(current, defaults: defaults) }
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
            // Por las dos llaves de un gasto unido; si hay edición en ambas, se
            // funden con la más reciente encima.
            let found = TransactionKey.lookupKeys(for: expense).compactMap { edits[$0] }
                .sorted { $0.updatedAt < $1.updatedAt }
            guard var edit = found.first else { continue }
            for newer in found.dropFirst() { edit = edit.merged(with: newer) }
            var touched = false
            if let value = edit.category, expense.category != value { expense.category = value; touched = true }
            if let value = edit.tags, expense.tags != value { expense.tags = value; touched = true }
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
            if let value = edit.debtSettled, expense.debtSettled != value {
                expense.debtSettled = value; touched = true
            }
            if let value = edit.cardLastDigits, expense.cardLastDigits != value {
                expense.cardLastDigits = value; touched = true
            }
            if let value = edit.fxRate, expense.currency != "PEN", expense.fxRateAtCapture != value {
                expense.fxRateAtCapture = value; touched = true
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
