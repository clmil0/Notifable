import SwiftUI
import SwiftData

/// Al tocar un aviso de anulación: ¿qué compra anuló el banco?
///
/// Se listan las candidatas (`ReversalMatcher`) con la más probable arriba.
/// Al elegir una, esa compra queda tachada y deja de contar, y el aviso
/// desaparece. Si ninguna encaja, el aviso se puede descartar.
struct ReversalResolveView: View {
    let reversal: Expense

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]

    @State private var pending: Expense?
    @State private var confirmsDiscard = false

    private var palette: Palette { Palette(scheme) }
    private var accent: AppThemeColor { .current }

    private var candidates: (list: [Expense], suggested: UUID?) {
        let pool = expenses.filter { !$0.isReversal && !$0.isVoided && !$0.isTransfer }
        let byID = Dictionary(pool.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let result = ReversalMatcher.candidates(for: ReversalMatcher.charge(reversal),
                                                among: pool.map(ReversalMatcher.charge))
        return (result.ordered.compactMap { byID[$0] }, result.suggested)
    }

    var body: some View {
        let candidates = self.candidates

        NavigationStack {
            List {
                Section {
                    header
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
                }

                if candidates.list.isEmpty {
                    Section {
                        Text("No hay una compra de " + Money.format(reversal.amount, currency: reversal.currency)
                             + " con esta tarjeta entre 7 días antes y 7 días después. Puede que el correo de la compra aún no haya llegado.")
                            .font(.subheadline)
                            .foregroundStyle(palette.secondaryLabel)
                    }
                } else {
                    Section {
                        ForEach(candidates.list) { purchase in
                            Button { pending = purchase } label: {
                                row(purchase, suggested: purchase.id == candidates.suggested)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("¿Cuál se anuló?")
                    } footer: {
                        Text("La que elijas quedará tachada y no contará en tus gastos. Este aviso desaparece.")
                    }
                }

                Section {
                    Button("Descartar aviso", role: .destructive) { confirmsDiscard = true }
                } footer: {
                    Text("Si ninguna es la compra anulada. El aviso se borra y no vuelve al releer el correo.")
                }
            }
            .navigationTitle("Anulación")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            // Alerta y no `confirmationDialog`: puesto en toda la hoja, en
            // iOS 26 el diálogo sale como globo colgado de la barra de arriba.
            .alert(pendingTitle, isPresented: Binding(get: { pending != nil },
                                                      set: { if !$0 { pending = nil } })) {
                Button("Marcar como anulada", role: .destructive) {
                    guard let purchase = pending else { return }
                    ReversalMatcher.resolve(reversal, voiding: purchase, in: modelContext)
                    dismiss()
                }
                Button("Cancelar", role: .cancel) { pending = nil }
            } message: {
                Text(pendingMessage)
            }
            .alert("¿Descartar este aviso?", isPresented: $confirmsDiscard) {
                Button("Descartar", role: .destructive) {
                    reversal.deleteRecordingRecovery(in: modelContext)
                    dismiss()
                }
                Button("Cancelar", role: .cancel) {}
            }
        }
        .tint(accent.onSurface(scheme))
    }

    private var pendingTitle: String {
        guard let purchase = pending else { return "" }
        return "¿Anular «" + Accounting.displayName(purchase.merchant) + "» del " + stamp(purchase.date) + "?"
    }

    private var pendingMessage: String {
        "Quedará tachada y no contará en tus gastos. Puedes deshacerlo desde la compra."
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("El banco anuló una compra", systemImage: "arrow.uturn.backward.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.warning)
            Text(Money.format(reversal.amount, currency: reversal.currency))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(palette.label)
            Text(detailLine(reversal))
                .font(.subheadline)
                .foregroundStyle(palette.secondaryLabel)
        }
    }

    private func row(_ purchase: Expense, suggested: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(Accounting.displayName(purchase.merchant))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.label)
                        .lineLimit(1)
                    if suggested {
                        Text("Sugerida")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(accent.onSurface(scheme))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(accent.color.opacity(0.14), in: Capsule())
                    }
                }
                Text(detailLine(purchase) + relativeNote(purchase))
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Money.format(purchase.amount, currency: purchase.currency))
                .font(.body.weight(.semibold))
                .foregroundStyle(palette.label)
        }
        .contentShape(Rectangle())
    }

    /// «21 set 14:24 · •••• 8156».
    private func detailLine(_ expense: Expense) -> String {
        var line = stamp(expense.date)
        if let digits = expense.cardLastDigits { line += " · •••• " + digits }
        return line
    }

    /// Cuánto antes o después del aviso: ayuda a elegir entre dos iguales.
    private func relativeNote(_ purchase: Expense) -> String {
        let seconds = purchase.date.timeIntervalSince(reversal.date)
        let minutes = Int(abs(seconds) / 60)
        let amount = minutes < 60 ? "\(max(minutes, 1)) min"
            : minutes < 60 * 48 ? "\(minutes / 60) h" : "\(minutes / 1440) días"
        return seconds <= 0 ? " · " + amount + " antes" : " · " + amount + " después"
    }

    private func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "d MMM HH:mm"
        return f.string(from: date).replacingOccurrences(of: ".", with: "")
    }
}
