import SwiftUI

/// Cuánto llevas clasificado y el atajo para acabar de una vez.
struct InboxProgressCard: View {

    let classified: Int
    let total: Int
    var onClassifyAll: () -> Void

    @Environment(\.colorScheme) private var scheme
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.purple.rawValue

    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .purple }
    private var palette: Palette { Palette(scheme) }
    private var pending: Int { max(0, total - classified) }
    private var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(classified) / Double(total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(classified) de \(total) comercios clasificados")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.label)
                Spacer()
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(accent.onSurface(scheme))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.track)
                    Capsule()
                        .fill(accent.color)
                        .frame(width: geo.size.width * CGFloat(fraction))
                }
            }
            .frame(height: 8)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: fraction)

            if pending > 0 {
                Button(action: onClassifyAll) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                        Text(pending == 1 ? "Clasificar el que queda" : "Clasificar los \(pending) restantes")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(accent.color)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .surfaceCard(radius: 20)
        .padding(.horizontal, 16)
    }
}

/// Un lote de comercios a los que el motor propone la misma categoría con
/// confianza alta. Aparece sólo con 2 o más: con uno solo ya está la fila de
/// sugerencia normal, no hace falta un bloque aparte.
struct SuggestionBucket: Identifiable {
    let category: String
    let merchants: [InboxGroup]
    var id: String { category }
    var total: Double { Money.sum(merchants) { $0.total } }
}

struct SuggestionBucketCard: View {

    let bucket: SuggestionBucket
    var onAccept: () -> Void

    @Environment(\.colorScheme) private var scheme
    private var palette: Palette { Palette(scheme) }

    private var names: String {
        bucket.merchants.prefix(3).map { Accounting.displayName($0.merchant) }.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(palette.positive)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(bucket.merchants.count) comercios parecen \(bucket.category)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.label)
                Text(names + " · " + Money.format(bucket.total))
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button(action: onAccept) {
                Text("Aceptar \(bucket.merchants.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(palette.positive)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(palette.positive.opacity(scheme == .dark ? 0.12 : 0.09))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.positive.opacity(0.4), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }
}

/// Tarjeta de un comercio de Pendientes.
///
/// El cambio que importa está en la fila de sugerencia: el motor propone y el
/// usuario confirma con **un** toque, en la propia tarjeta. Antes eran cuatro
/// por comercio —abrir el sheet, buscar, elegir, cerrar—; con doce comercios,
/// cuarenta y ocho toques.
///
/// Suma un checkbox de comercio completo, un chevron para expandir sin
/// seleccionar, y un checkbox por movimiento dentro del comercio expandido —
/// el caso de un Yape/Plin donde el resto de movimientos del mismo remitente
/// puede ir a otra categoría, y por eso hace falta poder soltar uno solo.
struct InboxMerchantCard: View {

    let group: InboxGroup
    let suggestion: CategorySuggestion?
    let frequentCategories: [String]
    let isSelected: Bool
    let selectedMovementIDs: Set<Expense.ID>
    let isExpanded: Bool
    let isHighlighted: Bool
    let isOutOfPeriod: Bool
    var onToggleSelect: () -> Void
    var onToggleExpand: () -> Void
    var onToggleMovement: (Expense.ID) -> Void
    var onPick: (String) -> Void
    var onOther: () -> Void

    @Environment(\.colorScheme) private var scheme
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.purple.rawValue

    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .purple }
    private var palette: Palette { Palette(scheme) }

    /// Por debajo de este umbral la sugerencia no se muestra: proponer con poca
    /// confianza enseña al usuario a desconfiar del botón.
    private var showsSuggestion: Bool { (suggestion?.confidence ?? 0) >= 0.45 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if showsSuggestion, let suggestion {
                suggestionRow(suggestion)
            }

            chips

            if isExpanded {
                movements
            }
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? accent.color.opacity(0.6) : palette.hairline, lineWidth: isSelected ? 1.2 : 0.5)
        )
        .padding(.horizontal, 16)
    }

    private var cardBackground: Color {
        if isHighlighted { return accent.color.opacity(0.15) }
        if isSelected { return accent.softFill(scheme) }
        return palette.surface
    }

    // MARK: - Cabecera

    private var header: some View {
        HStack(spacing: 12) {
            checkbox

            Button(action: onToggleSelect) {
                HStack(spacing: 12) {
                    logo

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(Accounting.displayName(group.merchant))
                                .font(.headline)
                                .foregroundStyle(palette.label)
                                .lineLimit(1)
                            if isOutOfPeriod {
                                Text("anterior")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(palette.warning)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(palette.warning.opacity(0.16))
                                    .clipShape(Capsule())
                            }
                        }
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(palette.secondaryLabel)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onToggleExpand) {
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.secondaryLabel)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var checkbox: some View {
        Button(action: onToggleSelect) {
            ZStack {
                Circle()
                    .strokeBorder(isSelected ? accent.color : palette.secondaryLabel.opacity(0.6), lineWidth: 1.6)
                    .background(Circle().fill(isSelected ? accent.color : Color.clear))
                    .frame(width: 24, height: 24)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        let count = group.expenses.count
        let movements = count == 1 ? "1 movimiento" : "\(count) movimientos"
        let amount = Money.format(group.total)
        if let channel = channelName {
            return channel + " · " + movements + " · " + amount
        }
        return movements + " · " + amount
    }

    private var channelName: String? {
        if group.merchant.hasPrefix("YAPE - ") { return "Yape" }
        if group.merchant.hasPrefix("PLIN - ") { return "Plin" }
        return nil
    }

    @ViewBuilder
    private var logo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.track)
                .frame(width: 42, height: 42)

            if group.merchant.hasPrefix("PLIN - ") {
                assetLogo("plin_icon")
            } else if group.merchant.hasPrefix("YAPE - ") {
                assetLogo("yape_icon")
            } else {
                Image(systemName: "bag.fill")
                    .foregroundStyle(palette.secondaryLabel)
            }
        }
    }

    private func assetLogo(_ name: String) -> some View {
        Image(name)
            .resizable()
            .scaledToFill()
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Sugerencia

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

            Button {
                onPick(suggestion.category)
            } label: {
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

    // MARK: - Chips

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(frequentCategories, id: \.self) { category in
                    Button { onPick(category) } label: {
                        chipLabel(category, filled: false)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onOther) {
                    chipLabel("Otra +", filled: true)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 1)
        }
    }

    private func chipLabel(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(filled ? accent.onSurface(scheme) : palette.label)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(filled ? accent.softFill(scheme) : palette.track)
            .clipShape(Capsule())
    }

    // MARK: - Movimientos

    /// Cada movimiento lleva su propio checkbox: permite soltar uno suelto sin
    /// arrastrar todo el comercio.
    private var movements: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().background(palette.separator)

            ForEach(group.expenses) { expense in
                Button { onToggleMovement(expense.id) } label: {
                    HStack(spacing: 9) {
                        movementCheckbox(selectedMovementIDs.contains(expense.id))
                        Text(expense.date.formatted(.dateTime.day().month().hour().minute()))
                            .font(.caption)
                            .foregroundStyle(palette.secondaryLabel)
                        Spacer()
                        Text(Money.format(expense.amount, currency: expense.currency))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(palette.label)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isSelected)
            }

            Text(movementsNote)
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
                .padding(.top, 2)
        }
    }

    private func movementCheckbox(_ checked: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(checked || isSelected ? accent.color : palette.secondaryLabel.opacity(0.5), lineWidth: 1.5)
                .background(Circle().fill(checked || isSelected ? accent.color : Color.clear))
                .frame(width: 19, height: 19)
            if checked || isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    /// Si el comercio completo ya está seleccionado, todos sus movimientos
    /// viajan con él y crearán regla; si no, los sueltos que se marquen se
    /// reclasifican sin tocar la regla del comercio.
    private var movementsNote: String {
        isSelected
            ? "El comercio completo está seleccionado: se creará una regla para todos."
            : "Los movimientos sueltos se reclasifican sin crear una regla."
    }
}
