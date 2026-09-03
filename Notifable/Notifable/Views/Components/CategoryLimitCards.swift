import SwiftUI

/// Envoltorio para presentar `6b` desde una fila.
struct CategoryWrapper: Identifiable, Equatable {
    let id: String
}

/// Un tramo de la barra de reparto de gasto.
struct DistributionSegment: Identifiable, Equatable {
    let category: String
    let amount: Double
    let color: Color
    var id: String { category }
}

/// Barra de reparto de gasto — reemplaza la dona.
///
/// La dona pedía comparar ángulos; aquí el orden es el mismo que el de la
/// lista de abajo y el color es el único código que hay que aprender. Tocar un
/// segmento o su chip aísla esa categoría en la lista; "Ver todo" lo suelta.
struct SpendingDistributionCard: View {

    let monthLabel: String
    let total: Double
    let segments: [DistributionSegment]
    let focusedCategory: String?
    var onToggleFocus: (String) -> Void
    var onClearFocus: () -> Void

    @Environment(\.colorScheme) private var scheme
    private var palette: Palette { Palette(scheme) }

    private var scale: Double { max(total, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("GASTO DE " + monthLabel.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.secondaryLabel)
                    Text(Money.formatCompact(total))
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.label)
                }

                Spacer(minLength: 0)

                if focusedCategory != nil {
                    Button("Ver todo", action: onClearFocus)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accentColor)
                }
            }

            bar
                .padding(.top, 14)

            legend
                .padding(.top, 11)
        }
        .padding(.horizontal, 14)
        .padding(.top, 15)
        .padding(.bottom, 14)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(palette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }

    private var bar: some View {
        HStack(spacing: 2) {
            ForEach(segments) { segment in
                Button { onToggleFocus(segment.category) } label: {
                    Rectangle().fill(segment.color)
                }
                .buttonStyle(.plain)
                .frame(width: max(2, CGFloat(segment.amount / scale) * 300))
                .opacity(dimmed(segment.category) ? 0.25 : 1)
            }
        }
        .frame(height: 14)
        .clipShape(Capsule())
        // El ancho real lo decide el `HStack` padre; el 300 de arriba sólo
        // fija la proporción entre segmentos, `frame(maxWidth: .infinity)`
        // en el contenedor la estira al ancho de la tarjeta.
        .frame(maxWidth: .infinity)
    }

    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(segments) { segment in
                    Button { onToggleFocus(segment.category) } label: {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(segment.color)
                                .frame(width: 8, height: 8)
                            Text(segment.category)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.label)
                            Text(Money.formatPercent(segment.amount, of: total))
                                .font(.caption)
                                .foregroundStyle(palette.secondaryLabel)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(focusedCategory == segment.category ? segment.color.opacity(0.18) : palette.track.opacity(0.5))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func dimmed(_ category: String) -> Bool {
        guard let focusedCategory else { return false }
        return focusedCategory != category
    }

    private var accentColor: Color {
        AppThemeColor(rawValue: UserDefaults.standard.string(forKey: "appAccentColor") ?? "")?.onSurface(scheme) ?? .purple
    }
}

/// Sólo aparece si alguna categoría se pasó. Un aviso permanente que nunca
/// cambia deja de leerse.
struct OverLimitAlert: View {

    let statuses: [CategoryLimitStatus]
    var onOpen: (String) -> Void

    @Environment(\.colorScheme) private var scheme
    private var palette: Palette { Palette(scheme) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(palette.negative)

            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(palette.negative)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if let first = statuses.first {
                Button("Ver") { onOpen(first.category) }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.negative)
            }
        }
        .padding(11)
        .background(palette.negative.opacity(scheme == .dark ? 0.14 : 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.negative.opacity(0.32), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }

    private var message: String {
        if statuses.count > 1 {
            return "\(statuses.count) categorías pasaron su límite"
        }
        guard let one = statuses.first else { return "" }
        return one.category + " pasó su límite — " + Money.formatCompact(one.overBy) + " arriba"
    }
}

/// Fila unificada de `6d`: sustituye a `CategoryLimitRow` + la tarjeta de
/// categoría expandible que existían por separado. Antes cada categoría se
/// pintaba dos veces —una fila de límite arriba, una tarjeta abajo—; ahora es
/// una sola fila que, al expandirse, enseña sus comercios.
struct UnifiedCategoryRow: View {

    let category: String
    let status: CategoryLimitStatus
    let spent: Double
    let merchants: [PeriodTotals.MerchantTotal]
    let color: Color
    let isExpanded: Bool
    var onToggleExpand: () -> Void
    var onRemoveMerchant: (String) -> Void
    var onEditLimit: () -> Void
    var onIsolate: () -> Void

    @Environment(\.colorScheme) private var scheme
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.purple.rawValue

    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .purple }
    private var palette: Palette { Palette(scheme) }

    /// Sin límite y sin gasto este mes: la fila no dice nada nuevo, se atenúa
    /// igual que hacía la tarjeta de categoría de siempre.
    private var isDim: Bool { !status.hasLimit && Money.isZero(spent) }

    var body: some View {
        VStack(spacing: 0) {
            header

            if status.hasLimit {
                LimitBar(fraction: status.fraction,
                         paceFraction: status.elapsedFraction,
                         color: status.level.color(palette),
                         height: 6)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 13)
            }

            if isExpanded {
                expandedContent
            }
        }
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.hairline, lineWidth: 0.5)
        )
        .opacity(isDim ? 0.45 : 1)
        .padding(.horizontal, 16)
    }

    private var header: some View {
        Button(action: onToggleExpand) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(color.opacity(0.22))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: CategoryStyle.icon(for: category))
                            .font(.footnote)
                            .foregroundStyle(color)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(category)
                        .font(.headline)
                        .foregroundStyle(palette.label)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(status.hasLimit ? status.level.color(palette) : palette.secondaryLabel)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if status.hasLimit {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(palette.secondaryLabel)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                } else {
                    Button(action: onEditLimit) {
                        Text("Poner límite")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(accent.onSurface(scheme))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .overlay(
                                Capsule().stroke(accent.onSurface(scheme).opacity(0.5), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        guard status.hasLimit else {
            return Money.isZero(spent)
                ? "Sin gasto este mes · sin límite"
                : Money.formatCompact(spent) + " este mes · sin límite"
        }
        return status.longLabel
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            Rectangle()
                .fill(palette.separator)
                .frame(height: 0.5)

            if merchants.isEmpty {
                Text("Ningún comercio este periodo.")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
            } else {
                ForEach(merchants) { merchant in
                    HStack(spacing: 10) {
                        Text(Accounting.displayName(merchant.merchant))
                            .font(.caption)
                            .foregroundStyle(palette.label)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(Money.format(merchant.total))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(palette.secondaryLabel)
                        Button { onRemoveMerchant(merchant.merchant) } label: {
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(palette.negative)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 8) {
                Button(action: onEditLimit) {
                    Text(status.hasLimit ? "Editar límite" : "Poner límite")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent.onSurface(scheme))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(palette.track.opacity(0.7))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onIsolate) {
                    Text("Aislar en el gráfico")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent.onSurface(scheme))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(palette.track.opacity(0.7))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 13)
    }
}
