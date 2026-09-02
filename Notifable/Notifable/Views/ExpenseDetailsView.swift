import SwiftUI
import SwiftData

/// Detalle de un movimiento, con las acciones a la vista.
///
/// Antes las tres acciones —marcar deuda, ver detalles, eliminar— vivían en un
/// context menu: sólo aparecían con una pulsación larga, que no se anuncia en
/// ninguna parte. Aquí son tres botones, y el menú `ellipsis` de cada fila hace
/// lo mismo desde la lista.
struct ExpenseDetailsView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("isDarkMode") private var isDarkMode = true
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.purple.rawValue

    @Bindable var expense: Expense

    @Query private var allExpenses: [Expense]

    @State private var showingCategoryPicker = false
    @State private var showingEditor = false
    @State private var showingDeleteConfirmation = false

    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .purple }
    private var themeColor: Color { accent.color }
    private var palette: Palette { Palette(colorScheme) }

    var allCategories: [String] {
        let defaults = ["Comida", "Transporte", "Entretenimiento", "Supermercado", "Otros"]
        let existing = Set(allExpenses.map { $0.category }.filter { $0 != Accounting.unclassified })
        return Array(existing.union(defaults)).sorted()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    actionRow
                    foreignPaymentsWarning
                    properties

                    if expense.isDebt || !(expense.payments ?? []).isEmpty {
                        paymentsSection
                    }

                    merchantHistory

                    Spacer(minLength: 24)
                }
                .padding(.top, 24)
            }
            .background(palette.background)
            .navigationTitle("Movimiento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCategoryPicker) {
                AssignCategoryView(merchant: expense.merchant, existingCategories: allCategories) { newCategory in
                    // Se guarda también la regla: si no, el siguiente correo del
                    // mismo comercio volvería a caer sin clasificar.
                    MerchantRules.apply(newCategory, to: expense.merchant, in: allExpenses)
                    try? modelContext.save()
                }
                .presentationDetents([.fraction(0.8)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
            }
            .sheet(isPresented: $showingEditor) {
                EditExpenseSheet(expense: expense)
            }
            .alert("¿Eliminar movimiento?", isPresented: $showingDeleteConfirmation) {
                Button("Cancelar", role: .cancel) {}
                Button("Eliminar", role: .destructive) { delete() }
            } message: {
                Text("Se borrará de tus cuentas. Esto no se puede deshacer.")
            }
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .presentationCornerRadius(32)
    }

    // MARK: - Cabecera

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(iconColor.opacity(0.2))
                    .frame(width: 64, height: 64)
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundStyle(iconColor)
            }

            Text(Money.format(expense.amount, currency: expense.currency))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(palette.label)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(subtitle)
                .font(.headline)
                .foregroundStyle(palette.secondaryLabel)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
    }

    private var subtitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_PE")
        f.dateFormat = "EEEE d, HH:mm"
        return Accounting.displayName(expense.merchant) + " · " + f.string(from: expense.date)
    }

    private var iconName: String {
        switch expense.category {
        case "Comida": return "fork.knife"
        case "Transporte": return "car.fill"
        case "Entretenimiento": return "play.tv.fill"
        default: return "bag.fill"
        }
    }

    private var iconColor: Color {
        switch expense.category {
        case "Comida": return .orange
        case "Transporte": return .blue
        case "Entretenimiento": return themeColor
        case "Supermercado": return .teal
        case Accounting.unclassified: return .gray
        default: return .green
        }
    }

    // MARK: - Acciones

    private var actionRow: some View {
        HStack(spacing: 12) {
            actionButton(title: expense.isDebt ? "Saldada" : "Es deuda",
                         icon: expense.isDebt ? "checkmark.circle" : "exclamationmark.circle",
                         tint: palette.warning) {
                toggleDebt()
            }

            actionButton(title: "Editar", icon: "pencil", tint: themeColor) {
                showingEditor = true
            }

            actionButton(title: "Eliminar", icon: "trash", tint: palette.negative) {
                showingDeleteConfirmation = true
            }
        }
        .padding(.horizontal, 16)
    }

    private func actionButton(title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.footnote.bold())
                    .foregroundStyle(palette.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Aviso de multimoneda

    @ViewBuilder
    private var foreignPaymentsWarning: some View {
        if Accounting.hasForeignPayments(expense) {
            Label("Hay abonos en otra moneda. El saldo no se puede calcular con ellos, así que quedan fuera de esta cuenta.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(palette.warning)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(palette.warning.opacity(colorScheme == .dark ? 0.16 : 0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
        }
    }

    // MARK: - Propiedades

    private var properties: some View {
        VStack(spacing: 0) {
            Button { showingCategoryPicker = true } label: {
                propertyRow(title: "Categoría") {
                    HStack(spacing: 6) {
                        Text(expense.category)
                            .fontWeight(.semibold)
                            .foregroundStyle(accent.onSurface(colorScheme))
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryLabel)
                    }
                }
            }
            .buttonStyle(.plain)

            divider

            propertyRow(title: "Origen") {
                Text(origin)
                    .foregroundStyle(palette.secondaryLabel)
            }

            divider

            propertyRow(title: "Moneda") {
                Text(expense.currency == "PEN" ? "Soles (PEN)" : "Dólares (USD)")
                    .foregroundStyle(palette.secondaryLabel)
            }

            if expense.currency != "PEN", let fx = expense.fxRateAtCapture {
                divider
                propertyRow(title: "Tipo de cambio") {
                    // El del día del movimiento, no el de hoy: por eso el total
                    // de un mes cerrado ya no se mueve.
                    Text("S/ " + String(format: "%.3f", fx) + " por $ 1")
                        .foregroundStyle(palette.secondaryLabel)
                }
            }

            divider

            Toggle(isOn: subscriptionBinding) {
                Text("Es suscripción")
                    .foregroundStyle(palette.label)
            }
            .tint(themeColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }

    private var subscriptionBinding: Binding<Bool> {
        Binding(
            get: { expense.isSubscription },
            set: { newValue in
                expense.isSubscription = newValue
                try? modelContext.save()
            }
        )
    }

    private var origin: String {
        if let card = expense.cardLastDigits {
            return "Correo · *" + card
        }
        return expense.emailID == nil ? "Manual" : "Correo"
    }

    private var divider: some View {
        Rectangle()
            .fill(palette.separator)
            .frame(height: 0.5)
            .padding(.leading, 16)
    }

    private func propertyRow<Value: View>(title: String, @ViewBuilder value: () -> Value) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(palette.label)
            Spacer()
            value()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    // MARK: - Deuda

    @ViewBuilder
    private var paymentsSection: some View {
        let paid = Accounting.paid(of: expense)
        let pending = Accounting.outstanding(of: expense)
        let ratio = min(Money.ratio(paid, to: expense.amount) ?? 0, 1.0)

        VStack(alignment: .leading, spacing: 12) {
            Text("Estado de la deuda")
                .font(.headline)
                .foregroundStyle(palette.label)

            HStack {
                Text(Money.format(paid, currency: expense.currency) + " pagado")
                    .font(.subheadline)
                    .foregroundStyle(palette.positive)
                Spacer()
                Text("faltan " + Money.format(pending, currency: expense.currency))
                    .font(.subheadline)
                    .foregroundStyle(Money.isZero(pending) ? palette.positive : palette.warning)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.track)
                    Capsule()
                        .fill(palette.positive)
                        .frame(width: geo.size.width * CGFloat(ratio))
                }
            }
            .frame(height: 8)

            ForEach((expense.payments ?? []).sorted(by: { $0.date > $1.date })) { payment in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(payment.source)
                            .font(.subheadline)
                            .foregroundStyle(palette.label)
                        Text(payment.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(palette.secondaryLabel)
                    }
                    Spacer()
                    Text("+" + Money.format(payment.amount, currency: payment.currency))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.positive)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(radius: 16)
        .padding(.horizontal, 16)
    }

    // MARK: - Historial del comercio

    /// Las últimas compras del mismo comercio. Da contexto —"¿esto es lo normal
    /// o me pasé?"— sin salir de la pantalla.
    @ViewBuilder
    private var merchantHistory: some View {
        let recent = recentAtMerchant
        if recent.count > 1 {
            let maxAmount = recent.map(\.amount).max() ?? 0

            VStack(alignment: .leading, spacing: 12) {
                Text(Accounting.displayName(expense.merchant))
                    .font(.headline)
                    .foregroundStyle(palette.label)

                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(recent) { item in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(item.id == expense.id ? themeColor : palette.track)
                                .frame(height: barHeight(item.amount, max: maxAmount))
                            Text("\(Period.calendar.component(.day, from: item.date))")
                                .font(.caption2)
                                .foregroundStyle(palette.secondaryLabel)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 76, alignment: .bottom)

                Text(historySummary(recent))
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCard(radius: 16)
            .padding(.horizontal, 16)
        }
    }

    private var recentAtMerchant: [Expense] {
        allExpenses
            .filter { $0.merchant == expense.merchant }
            .sorted { $0.date > $1.date }
            .prefix(5)
            .sorted { $0.date < $1.date }
    }

    private func barHeight(_ amount: Double, max maxAmount: Double) -> CGFloat {
        guard let ratio = Money.ratio(amount, to: maxAmount) else { return 4 }
        return Swift.max(4, 60 * CGFloat(min(1, ratio)))
    }

    private func historySummary(_ recent: [Expense]) -> String {
        let count = recent.count
        let compras = count == 1 ? "1 compra" : "\(count) compras"
        guard let highest = recent.max(by: { Money.cents($0.amount) < Money.cents($1.amount) }) else {
            return compras
        }
        if highest.id == expense.id { return compras + " · ésta es la más alta" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_PE")
        f.dateFormat = "d MMM"
        return compras + " · la más alta fue el " + f.string(from: highest.date)
    }

    // MARK: - Acciones

    private func toggleDebt() {
        withAnimation {
            expense.isDebt.toggle()
            try? modelContext.save()

            let descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.isDebt == true })
            let hasDebts = ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
            NotificationManager.shared.updateDebtNotification(hasDebts: hasDebts)
        }
    }

    private func delete() {
        if let emailID = expense.emailID {
            var recoveryIDs = UserDefaults.standard.stringArray(forKey: "pendingRecoveryIDs") ?? []
            if !recoveryIDs.contains(emailID) {
                recoveryIDs.append(emailID)
                UserDefaults.standard.set(recoveryIDs, forKey: "pendingRecoveryIDs")
            }
        }
        modelContext.delete(expense)
        try? modelContext.save()
        dismiss()
    }
}

/// Edición mínima de un movimiento: lo que un parser puede haber leído mal.
struct EditExpenseSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("isDarkMode") private var isDarkMode = true

    @Bindable var expense: Expense

    @State private var amountText = ""
    @State private var merchant = ""
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Monto") {
                    HStack {
                        Text(Money.symbol(for: expense.currency))
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                    }
                }
                Section("Comercio") {
                    TextField("Comercio", text: $merchant)
                        .disableAutocorrection(true)
                }
                Section("Fecha") {
                    DatePicker("Fecha", selection: $date)
                        .datePickerStyle(.compact)
                }
            }
            .navigationTitle("Editar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(merchant.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                amountText = String(format: "%.2f", expense.amount)
                merchant = expense.merchant
                date = expense.date
            }
            .preferredColorScheme(isDarkMode ? .dark : .light)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        let cleaned = amountText.replacingOccurrences(of: ",", with: ".")
        if let value = Double(cleaned), value > 0 {
            // Céntimos enteros, igual que en el init del modelo.
            expense.amount = Money.normalized(value)
        }
        expense.merchant = merchant.trimmingCharacters(in: .whitespaces)
        expense.date = date
        try? modelContext.save()
        dismiss()
    }
}
