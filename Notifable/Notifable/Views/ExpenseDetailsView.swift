import SwiftUI
import SwiftData

struct ExpenseDetailsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage("isDarkMode") private var isDarkMode = true
    
    @Bindable var expense: Expense
    
    // Para obtener todas las categorías existentes
    @Query private var allExpenses: [Expense]
    
    @State private var showingCategoryPicker = false
    @State private var showingCancelDebtConfirmation = false
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.purple.rawValue
    
    var themeColor: Color { AppThemeColor(rawValue: appAccentColor)?.color ?? .purple }

    @Environment(\.colorScheme) private var colorScheme

    /// Paleta con contraste verificado. Sustituye a `Color.primary.opacity(0.05)`,
    /// que en modo claro es #F2F2F2 sobre blanco: 4 % de diferencia de luminancia,
    /// invisible al sol o con el brillo bajo.
    private var palette: Palette { Palette(colorScheme) }

    
    var allCategories: [String] {
        let defaults = ["Comida", "Transporte", "Entretenimiento", "Supermercado", "Otros"]
        let existing = Set(allExpenses.map { $0.category }.filter { $0 != "Sin Clasificar" })
        return Array(existing.union(defaults)).sorted()
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header con Monto
                    VStack(spacing: 8) {
                        Text(Money.format(expense.amount, currency: expense.currency))
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        
                        Text(expense.merchant)
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 32)
                    
                    // Tarjeta de Detalles
                    VStack(spacing: 0) {
                        detailRow(title: "Fecha", value: expense.date.formatted(date: .abbreviated, time: .shortened))
                        
                        Divider().padding(.leading, 16)
                        
                        detailRow(title: "Moneda", value: expense.currency == "PEN" ? "Soles (PEN)" : "Dólares (USD)")
                        
                        Divider().padding(.leading, 16)
                        
                        if expense.currency != "PEN", let fx = expense.fxRateAtCapture {
                            // El tipo de cambio del día del movimiento, no el de hoy.
                            detailRow(title: "Tipo de cambio", value: "S/ " + String(format: "%.3f", fx) + " por $ 1")
                            
                            Divider().padding(.leading, 16)
                        }
                        
                        if let card = expense.cardLastDigits {
                            detailRow(title: "Tarjeta", value: "*\(card)")
                            
                            Divider().padding(.leading, 16)
                        }
                        
                        Button {
                            showingCategoryPicker = true
                        } label: {
                            HStack {
                                Text("Categoría")
                                    .foregroundStyle(.primary)
                                Spacer()
                                HStack(spacing: 6) {
                                    Text(expense.category)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(themeColor)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding()
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .surfaceCard(radius: 16, padding: 0)
                    .padding(.horizontal)
                    
                    if expense.isDebt || !(expense.payments ?? []).isEmpty {
                        paymentsSection
                    }
                    
                    Button {
                        withAnimation {
                            expense.isDebt.toggle()
                            try? modelContext.save()
                        }
                    } label: {
                        Text(expense.isDebt ? "Marcar como Deuda Saldada" : "Marcar como Deuda Activa")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(expense.isDebt ? Color.green : Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    Spacer()
                }
            }
            .navigationTitle("Detalles de Transacción")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingCategoryPicker) {
                AssignCategoryView(merchant: expense.merchant, existingCategories: allCategories) { newCategory in
                    expense.category = newCategory
                    try? modelContext.save()
                }
                .presentationDetents([.fraction(0.8)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
            }
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }
    
    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
    
    @ViewBuilder
    private var paymentsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Estado de la Deuda")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            // Sólo cuentan los abonos en la moneda del gasto: un abono de $ 40
            // no salda 40 soles (ACCOUNTING.md §5).
            let paid = Accounting.paid(of: expense)
            let total = expense.amount
            let pending = Accounting.outstanding(of: expense)
            let ratio = min(Money.ratio(paid, to: total) ?? 0, 1.0)
            
            VStack(alignment: .leading, spacing: 8) {
                if Accounting.hasForeignPayments(expense) {
                    Label("Hay abonos en otra moneda. El saldo no se puede calcular con ellos y quedan fuera de esta cuenta.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.bottom, 4)
                }
                
                HStack {
                    Text(Money.format(paid, currency: expense.currency) + " pagado")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                    Spacer()
                    Text(Money.format(total, currency: expense.currency) + " total")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Pendiente")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Money.format(pending, currency: expense.currency))
                        .font(.caption.bold())
                        .foregroundStyle(Money.isZero(pending) ? .green : .orange)
                }
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(palette.track)
                            .frame(height: 8)
                        
                        Capsule()
                            .fill(Color.green)
                            .frame(width: geo.size.width * CGFloat(ratio), height: 8)
                    }
                }
                .frame(height: 8)
            }
            .padding()
            .surfaceCard(radius: 16, padding: 0)
            .padding(.horizontal)
            
            if let payments = expense.payments, !payments.isEmpty {
                VStack(spacing: 0) {
                    ForEach(payments.sorted(by: { $0.date > $1.date })) { payment in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(payment.source)
                                    .fontWeight(.medium)
                                Text(payment.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("+" + Money.format(payment.amount, currency: payment.currency))
                                .fontWeight(.bold)
                                .foregroundStyle(.green)
                        }
                        .padding()
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button(role: .destructive) {
                                withAnimation {
                                    payment.debtReference = nil
                                    payment.isFinalDebtPayment = false
                                    try? modelContext.save()
                                }
                            } label: {
                                Label("Desvincular de la deuda", systemImage: "link.badge.minus")
                            }
                        }
                        
                        if payment.id != payments.sorted(by: { $0.date > $1.date }).last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .surfaceCard(radius: 16, padding: 0)
                .padding(.horizontal)
            } else {
                Text("Aún no hay pagos registrados.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
    }
}
