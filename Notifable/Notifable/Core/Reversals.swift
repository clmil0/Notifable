import Foundation
import SwiftData

extension Expense {
    /// Suma como gasto: no es un traslado, ni un aviso de anulación, ni una
    /// compra que el banco anuló. Lo que Pendientes y las listas «a
    /// clasificar» deben mirar.
    var countsAsSpending: Bool { !isTransfer && !isReversal && !isVoided }
}

/// Qué compra anuló el banco.
///
/// El correo de anulación sólo dice monto, moneda, tarjeta y hora. Con dos
/// compras iguales seguidas —una máquina expendedora que falla y se vuelve a
/// intentar— no hay forma segura de saber cuál fue, así que **decide el
/// usuario**: el aviso llega como un movimiento, al tocarlo se listan las
/// candidatas y la más probable va primero.
///
/// Candidata: misma moneda y monto, hasta 7 días antes **o después** del
/// aviso (el correo de la compra puede llegar tarde), y la misma tarjeta si
/// los dos la dicen. La sugerida es la más cercana **anterior** al aviso: no
/// se anula lo que todavía no se había comprado. Si el aviso nombra el
/// comercio (la devolución de BCP lo hace; la anulación de BBVA dice
/// «REVERSO TOTAL»), manda la anterior de ese mismo comercio.
enum ReversalMatcher {

    static let merchantPrefix = "ANULACIÓN - "
    static let window: TimeInterval = 7 * 24 * 3600

    struct Charge: Equatable {
        let id: UUID
        let cents: Int
        let currency: String
        let date: Date
        let digits: String?
        /// El comercio, sin el prefijo del aviso. Sólo desempata la sugerida.
        var merchant: String? = nil
    }

    /// Las candidatas en orden: la sugerida primero (si la hay), luego por
    /// cercanía en el tiempo.
    static func candidates(for reversal: Charge, among charges: [Charge]) -> (ordered: [UUID], suggested: UUID?) {
        let matching = charges.filter { charge in
            charge.id != reversal.id
                && charge.cents == reversal.cents
                && charge.currency == reversal.currency
                && abs(charge.date.timeIntervalSince(reversal.date)) <= window
                && (charge.digits == nil || reversal.digits == nil || charge.digits == reversal.digits)
        }
        let before = matching.filter { $0.date <= reversal.date }
        let sameMerchant = before.filter { $0.merchant != nil && $0.merchant == reversal.merchant }
        let suggested = (sameMerchant.isEmpty ? before : sameMerchant)
            .max { $0.date < $1.date }?.id
        let ordered = matching
            .sorted { abs($0.date.timeIntervalSince(reversal.date)) < abs($1.date.timeIntervalSince(reversal.date)) }
            .map(\.id)
        guard let suggested else { return (ordered, nil) }
        return ([suggested] + ordered.filter { $0 != suggested }, suggested)
    }

    static func charge(_ expense: Expense) -> Charge {
        var name = expense.merchant
        if expense.isReversal, name.hasPrefix(merchantPrefix) { name.removeFirst(merchantPrefix.count) }
        return Charge(id: expense.id, cents: Money.cents(expense.amount), currency: expense.currency,
                      date: expense.date, digits: expense.cardLastDigits,
                      merchant: name.trimmingCharacters(in: .whitespaces).uppercased())
    }

    /// Anula la compra elegida y borra el aviso. La anulación queda anotada
    /// en `ExpenseEditStore` y el aviso en «borrados», así que releer el
    /// correo no devuelve ni la compra viva ni el aviso. Los datos del aviso
    /// viajan con la anulación para que «Deshacer» pueda recrearlo.
    @MainActor
    static func resolve(_ reversal: Expense, voiding purchase: Expense, in context: ModelContext) {
        purchase.isVoided = true
        ExpenseEditStore.save(ExpenseEdit(markKey: TransactionKey.key(for: purchase),
                                          isVoided: true, voidedBy: ReversalNotice(reversal)))
        reversal.deleteRecordingRecovery(in: context)
        try? context.save()
    }

    /// Deshace una anulación elegida por error: la compra vuelve a contar y
    /// el aviso reaparece en Movimientos para elegir otra.
    @MainActor
    static func restore(_ purchase: Expense, in context: ModelContext) {
        let edits = ExpenseEditStore.all()
        let notice = TransactionKey.lookupKeys(for: purchase).lazy.compactMap { edits[$0]?.voidedBy }.first
        purchase.isVoided = false
        ExpenseEditStore.save(ExpenseEdit(markKey: TransactionKey.key(for: purchase), isVoided: false))
        if let notice { reinsert(notice, in: context) }
        try? context.save()
    }

    /// Vuelve a crear el aviso y lo saca de «borrados», o la siguiente
    /// lectura del correo lo daría por descartado.
    @MainActor
    private static func reinsert(_ notice: ReversalNotice, in context: ModelContext) {
        if let emailID = notice.emailID {
            let descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.emailID == emailID })
            if ((try? context.fetchCount(descriptor)) ?? 0) > 0 { return }
            var deleted = UserDefaults.standard.stringArray(forKey: "pendingRecoveryIDs") ?? []
            deleted.removeAll { $0 == emailID }
            UserDefaults.standard.set(deleted, forKey: "pendingRecoveryIDs")
        }
        let reversal = Expense(amount: notice.amount, merchant: notice.merchant, date: notice.date,
                               category: Accounting.unclassified, currency: notice.currency,
                               emailID: notice.emailID, cardLastDigits: notice.cardLastDigits)
        reversal.isReversal = true
        context.insert(reversal)
    }
}

/// Lo necesario para recrear un aviso de anulación ya borrado.
struct ReversalNotice: Codable, Equatable {
    var emailID: String?
    var merchant: String
    var amount: Double
    var currency: String
    var date: Date
    var cardLastDigits: String?

    init(_ reversal: Expense) {
        emailID = reversal.emailID
        merchant = reversal.merchant
        amount = reversal.amount
        currency = reversal.currency
        date = reversal.date
        cardLastDigits = reversal.cardLastDigits
    }
}
