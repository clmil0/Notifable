import SwiftUI

/// `2c` — Un pago dividido en Movimientos: la cabecera con el pago original y,
/// debajo, sus partes unidas por un riel.
///
/// La cabecera va en pequeño y con el monto en gris: es la referencia, no un
/// gasto. Tocarla pliega las partes; plegado, el subtítulo dice en qué se
/// dividió. Cada parte lleva el logo del canal de pago pegado a su ícono, que
/// es lo que la ata al pago a simple vista aunque el riel no se vea.
struct SplitGroupRows: View {
    let parent: Expense
    let parts: [Expense]
    let isExpanded: Bool
    var onToggle: () -> Void
    var onOpenPart: (Expense) -> Void
    var onOpenParent: () -> Void
    var onEditSplit: () -> Void

    @Environment(\.colorScheme) private var scheme
    private var palette: Palette { Palette(scheme) }
    private var accent: AppThemeColor { .current }

    var body: some View {
        if parent.isDeleted || parent.modelContext == nil {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                header
                if isExpanded {
                    partsList
                        .transition(.opacity)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            MovementIcon(icon: MovementStyle.icon(for: parent),
                         color: MovementStyle.color(for: parent, accent: accent.color, scheme: scheme),
                         size: 26)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 0) {
                    Text(Accounting.displayName(parent.merchant))
                        .fontWeight(.semibold)
                        .foregroundStyle(palette.label)
                    Text(" · " + origin)
                        .foregroundStyle(palette.secondaryLabel)
                }
                .font(.system(size: 13))
                .lineLimit(1)

                Label(subtitle, systemImage: "arrow.triangle.branch")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(accent.onSurface(scheme))
                    .labelStyle(TightLabelStyle())
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(Money.format(parent.amount, currency: parent.currency))
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(palette.secondaryLabel)

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.secondaryLabel)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, isExpanded ? 6 : 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .contextMenu {
            Button(action: onOpenParent) {
                Label("Ver pago original", systemImage: "doc.text")
            }
            Button(action: onEditSplit) {
                Label("Editar división", systemImage: "slider.horizontal.3")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isExpanded ? "Pliega las partes" : "Muestra las partes")
    }

    /// «Yape 14:20»; con tarjeta, «•8156 13:18»: la línea es corta y el nombre
    /// va primero.
    private var origin: String {
        let time = parent.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()
            .locale(Locale(identifier: "es_ES")))
        let source = SplitStyle.channelName(for: parent) ?? parent.cardLastDigits.map { "•" + $0 }
        return [source, time].compactMap { $0 }.joined(separator: " ")
    }

    private var subtitle: String {
        if isExpanded { return "Dividido en \(parts.count)" }
        return "\(parts.count) partes · " + parts.map(\.category).joined(separator: ", ")
    }

    private var partsList: some View {
        VStack(spacing: 0) {
            ForEach(parts) { part in
                SplitPartRow(part: part, parentName: Accounting.displayName(parent.merchant),
                             channelLogo: SplitStyle.channelLogo(for: parent))
                    .onTapGesture { onOpenPart(part) }
            }
        }
        .padding(.bottom, 4)
        // El riel: del pie de la cabecera al centro del último ícono.
        .background(alignment: .topLeading) {
            GeometryReader { geo in
                Capsule()
                    .fill(accent.color.opacity(0.28))
                    .frame(width: 2, height: max(0, geo.size.height - 26))
                    .offset(x: 33, y: -4)
            }
        }
    }
}

/// Una parte en la lista: ícono de su categoría con el logo del canal, su
/// categoría como título y «Parte de Juan Pérez · ●etiqueta» debajo.
struct SplitPartRow: View {
    let part: Expense
    let parentName: String
    let channelLogo: String?

    @Environment(\.colorScheme) private var scheme
    private var palette: Palette { Palette(scheme) }
    private var accent: AppThemeColor { .current }

    var body: some View {
        if part.isDeleted || part.modelContext == nil {
            EmptyView()
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                MovementIcon(icon: CategoryStyle.icon(for: part.category),
                             color: CategoryStyle.color(for: part.category, accent: accent.color),
                             size: 40)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 11.8, style: .continuous))
                if let channelLogo {
                    Image(channelLogo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 16, height: 16)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(palette.surface, lineWidth: 2))
                        .offset(x: 4, y: 4)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(part.category)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(palette.label)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text("Parte de " + parentName)
                        .foregroundStyle(palette.secondaryLabel)
                        .lineLimit(1)
                    if let tag = part.tags.first {
                        Text("·").foregroundStyle(palette.secondaryLabel)
                        Circle()
                            .fill(TagCatalog.shared.color(for: tag))
                            .frame(width: 7, height: 7)
                        Text(tag)
                            .fontWeight(.semibold)
                            .foregroundStyle(palette.label)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                }
                .font(.system(size: 12.5))

                if part.isDebt {
                    Text("Por cobrar · falta " + Money.format(Accounting.outstanding(of: part), currency: part.currency))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.warning)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text("–" + Money.format(part.isDebt ? Accounting.outstanding(of: part) : part.amount,
                                    currency: part.currency))
                .font(.system(size: 15.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(palette.label)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

/// Ícono pegado al texto, sin el hueco ancho de `Label`.
private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 11, weight: .semibold))
            configuration.title
        }
    }
}
