import SwiftUI

/// Contexto del movimiento que se está clasificando.
///
/// Un solo componente sirve a los tres puntos de entrada —detalle del gasto,
/// Bandeja y modal de alta—; lo único que cambia entre ellos es esta cabecera.
/// Si el sheet acabara duplicado, la sugerencia y el saldo del límite se
/// desincronizarían entre puntos de entrada, que es justo el problema que
/// venimos a resolver.
struct AssignCategoryContext: Equatable, Identifiable {

    var id: String { (merchant ?? "") + "|" + title }

    /// `nil` en el modal de alta cuando aún no se escribió el comercio: sin
    /// comercio no hay regla que crear.
    var merchant: String?
    var title: String
    var subtitle: String
    var amount: Double?
    var currency: String = "PEN"
    /// Categoría actual, para preseleccionarla.
    var current: String?

    static func expense(_ expense: Expense) -> AssignCategoryContext {
        AssignCategoryContext(
            merchant: expense.merchant,
            title: Accounting.displayName(expense.merchant),
            subtitle: expense.date.formatted(.dateTime.day().month(.abbreviated).hour().minute()),
            amount: expense.amount,
            currency: expense.currency,
            current: expense.category == Accounting.unclassified ? nil : expense.category
        )
    }

    /// Desde la Bandeja: el "movimiento" es el grupo entero del comercio.
    static func merchant(_ merchant: String, movements: Int, total: Double) -> AssignCategoryContext {
        let count = movements == 1 ? "1 movimiento" : "\(movements) movimientos"
        return AssignCategoryContext(
            merchant: merchant,
            title: Accounting.displayName(merchant),
            subtitle: count + " · " + Money.format(total),
            amount: nil
        )
    }

    /// Desde el modal de alta: todavía no existe el gasto.
    static func draft(merchant: String, amount: Double, currency: String, current: String?) -> AssignCategoryContext {
        let clean = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        return AssignCategoryContext(
            merchant: clean.isEmpty ? nil : clean,
            title: clean.isEmpty ? "Nuevo gasto" : Accounting.displayName(clean),
            subtitle: "Sin guardar todavía",
            amount: Money.cents(amount) > 0 ? amount : nil,
            currency: currency,
            current: current
        )
    }
}

/// `6a` — Asignar categoría, con el saldo del límite a la vista.
///
/// Las tres piezas que cambian la decisión están en la misma pantalla: la
/// sugerencia del motor como acción de un toque, el saldo del límite **dentro**
/// de cada celda —asignar es el único momento en que ese dato cambia algo— y la
/// regla opcional para que el comercio no vuelva a preguntar.
struct AssignCategorySheet: View {

    let context: AssignCategoryContext
    let history: [Expense]
    /// Se llama con la categoría elegida y si hay que crear la regla del comercio.
    var onAssign: (String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.purple.rawValue
    @AppStorage("period") private var period = Period()

    @StateObject private var budgets = CategoryBudgetStore.shared
    @StateObject private var catalog = CategoryCatalog.shared
    @StateObject private var rates = ExchangeRateService.shared

    @State private var selected: String?
    @State private var search = ""
    @State private var ruleEnabled = false
    @State private var creating: String?

    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .purple }
    private var palette: Palette { Palette(scheme) }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        if let hint = suggestion, hint.confidence >= 0.45 {
                            suggestionRow(hint)
                        }
                        searchField
                        gridSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }

                footer
            }
            .background(palette.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .navigationDestination(item: $creating) { name in
                CategorySettingsView(category: name,
                                     isNew: true,
                                     history: history) { finalName in
                    selected = finalName
                    search = ""
                }
            }
            .appAppearance()
            .appTextSize()
        }
        .onAppear(perform: prepare)
    }

    // MARK: - Estado

    private var referenceDate: Date { CategoryLimits.referenceDate(for: period) }

    private var snapshots: [ExpenseSnapshot] { history.map(\.accountingSnapshot) }

    private var suggestion: CategorySuggestion? {
        guard let merchant = context.merchant else { return nil }
        return SuggestionEngine.suggest(for: merchant, rules: MerchantRules.all(), history: history)
    }

    /// Movimientos pasados del mismo comercio: lo que la regla reclasificaría.
    private var pastCount: Int {
        guard let merchant = context.merchant else { return 0 }
        return history.reduce(0) { $0 + ($1.merchant == merchant ? 1 : 0) }
    }

    /// Orden estable: primero las seis más usadas, luego el resto alfabéticas.
    /// **No** se ordena por saldo: la posición tiene que ser la misma entre
    /// aperturas o la memoria muscular no se forma.
    private var orderedCategories: [String] {
        let all = CategoryStyle.selectable(history: history)
        let frequent = SuggestionEngine.frequentCategories(history: history, excluding: nil, limit: 6)
        let rest = all.filter { !frequent.contains($0) }.sorted()
        return frequent + rest
    }

    private var visibleCategories: [String] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return orderedCategories }
        return orderedCategories.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private func status(for category: String) -> CategoryLimitStatus {
        CategoryLimits.status(category: category,
                              budget: budgets.budget(for: category),
                              expenses: snapshots,
                              on: referenceDate,
                              usdToPen: rates.usdToPenRate)
    }

    private func prepare() {
        selected = context.current
        // Encendido por defecto sólo si hay patrón: con un único movimiento no
        // hay nada que generalizar.
        ruleEnabled = context.merchant != nil && pastCount >= 2
    }

    // MARK: - Cabecera

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(palette.track)
                .frame(width: 44, height: 44)
                .overlay(headerIcon)

            VStack(alignment: .leading, spacing: 3) {
                Text(context.title)
                    .font(.title3.bold())
                    .foregroundStyle(palette.label)
                    .lineLimit(1)
                Text(context.subtitle)
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let amount = context.amount {
                Text(Money.format(amount, currency: context.currency))
                    .font(.title3.bold())
                    .foregroundStyle(palette.label)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var headerIcon: some View {
        let merchant = context.merchant ?? ""
        if merchant.hasPrefix("PLIN - ") {
            channelLogo("plin_icon")
        } else if merchant.hasPrefix("YAPE - ") {
            channelLogo("yape_icon")
        } else {
            Image(systemName: "bag.fill")
                .foregroundStyle(palette.secondaryLabel)
        }
    }

    private func channelLogo(_ name: String) -> some View {
        Image(name)
            .resizable()
            .scaledToFill()
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Sugerencia

    /// La misma fila que la Bandeja (`2d`): si aquí se viera distinta, el
    /// usuario tendría que aprender dos veces qué significa el rayo.
    private func suggestionRow(_ suggestion: CategorySuggestion) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.fill")
                .font(.footnote.weight(.bold))
                .foregroundStyle(palette.positive)

            VStack(alignment: .leading, spacing: 1) {
                Text(suggestion.category)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.label)
                Text(suggestion.reason)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Button { confirm(suggestion.category) } label: {
                Text("Aplicar")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(palette.positive)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(palette.positive.opacity(scheme == .dark ? 0.16 : 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.positive.opacity(0.5), lineWidth: 0.5)
        )
    }

    // MARK: - Búsqueda

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.secondaryLabel)
            TextField("Buscar o crear categoría", text: $search)
                .disableAutocorrection(true)
                .foregroundStyle(palette.label)
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.secondaryLabel)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    // MARK: - Rejilla

    private var gridSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(gridTitle)
                .font(.caption.weight(.medium))
                .foregroundStyle(palette.secondaryLabel)
                .padding(.horizontal, 4)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(visibleCategories, id: \.self) { category in
                    Button { select(category) } label: {
                        CategoryLimitCell(category: category,
                                          status: status(for: category),
                                          color: color(of: category),
                                          isSelected: selected == category)
                    }
                    .buttonStyle(.plain)
                }

                newCategoryCell
            }
        }
    }

    private var gridTitle: String {
        "TODAS · SALDO DEL LÍMITE DE " + monthName.uppercased()
    }

    private var monthName: String {
        Period.spanishMonthName(for: referenceDate)
    }

    private var newCategoryCell: some View {
        Button { creating = pendingName } label: {
            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.track)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(palette.label)
                    )
                Text(newCellTitle)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(palette.label)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("con límite")
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryLabel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(palette.secondaryLabel.opacity(0.5),
                                  style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
            )
        }
        .buttonStyle(.plain)
    }

    private var pendingName: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var newCellTitle: String {
        pendingName.isEmpty ? "Nueva" : "Crear «\(pendingName)»"
    }

    private func color(of category: String) -> Color {
        CategoryStyle.color(for: category, accent: accent.color)
    }

    // MARK: - Pie

    private var footer: some View {
        VStack(spacing: 11) {
            if context.merchant != nil, pastCount > 0 {
                ruleToggle
            }
            primaryButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(palette.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.hairline)
                .frame(height: 0.5)
        }
    }

    private var ruleToggle: some View {
        Toggle(isOn: $ruleEnabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text("No volver a preguntar por " + context.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(palette.label)
                Text(ruleDetail)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
            }
        }
        .tint(palette.positive)
    }

    private var ruleDetail: String {
        pastCount == 1
            ? "Crea una regla y reclasifica el anterior"
            : "Crea una regla y reclasifica los \(pastCount) anteriores"
    }

    private var primaryButton: some View {
        Button { if let selected { confirm(selected) } } label: {
            Text(primaryTitle)
                .font(.body.weight(.semibold))
                .foregroundStyle(primaryTextColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(primaryFill)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(selected == nil)
    }

    private var primaryTitle: String {
        guard let selected else { return "Elige una categoría" }
        return "Asignar a " + selected
    }

    private var primaryFill: Color {
        guard let selected else { return palette.track }
        return color(of: selected)
    }

    private var primaryTextColor: Color {
        guard selected != nil else { return palette.secondaryLabel }
        return scheme == .dark ? Color(white: 0.06) : .white
    }

    // MARK: - Acciones

    private func select(_ category: String) {
        withAnimation(.easeInOut(duration: 0.15)) {
            selected = selected == category ? nil : category
        }
    }

    /// Asignar no advierte nada antes, aunque la categoría ya esté pasada de
    /// límite: avisar antes convertiría el límite en un obstáculo. El aviso va
    /// después, en el toast que compone quien llama.
    private func confirm(_ category: String) {
        onAssign(category, ruleEnabled && context.merchant != nil)
        dismiss()
    }
}

// MARK: - Celda

/// Una categoría con el saldo de su límite. Fuera del cuerpo del sheet: el
/// comprobador de tipos de Swift no termina una expresión con la rejilla y la
/// celda juntas.
struct CategoryLimitCell: View {

    let category: String
    let status: CategoryLimitStatus
    let color: Color
    let isSelected: Bool

    @Environment(\.colorScheme) private var scheme
    private var palette: Palette { Palette(scheme) }

    private var level: CategoryLimitStatus.Level { status.level }
    private var levelColor: Color { level.color(palette) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.22))
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: CategoryStyle.icon(for: category))
                        .font(.caption)
                        .foregroundStyle(color)
                )

            Text(category)
                .font(.footnote.weight(.bold))
                .foregroundStyle(palette.label)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(status.shortLabel)
                .font(.caption2.weight(.bold))
                .foregroundStyle(levelColor)
                .lineLimit(1)

            bar
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? color.opacity(0.16) : palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? levelColor : palette.hairline,
                        lineWidth: isSelected ? 1.5 : 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(category + ", " + status.shortLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var bar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.track.opacity(status.hasLimit ? 1 : 0.6))
                if status.hasLimit {
                    Capsule()
                        .fill(levelColor)
                        .frame(width: max(2, geo.size.width * CGFloat(status.fraction)))
                }
            }
        }
        .frame(height: 4)
    }
}
