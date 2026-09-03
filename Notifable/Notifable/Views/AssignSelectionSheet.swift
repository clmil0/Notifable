import SwiftUI

/// "Asignar a…" para una selección de Pendientes — uno o varios comercios,
/// mezclados o no con movimientos sueltos.
///
/// A diferencia de `AssignCategorySheet` (`6a`, una rejilla de 3 columnas para
/// clasificar un solo movimiento con su contexto a la vista), aquí lo que
/// importa es recorrer la lista completa de categorías rápido: una fila por
/// categoría, con su estado de límite y, si el motor coincide en todas las
/// piezas seleccionadas, la etiqueta "sugerida".
struct AssignSelectionSheet: View {

    let title: String
    let subtitle: String
    let categories: [String]
    let statuses: [String: CategoryLimitStatus]
    let suggestedCategory: String?
    var onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue

    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .purple }
    private var palette: Palette { Palette(scheme) }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(palette.secondaryLabel.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.bold())
                        .foregroundStyle(palette.label)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryLabel)

                    VStack(spacing: 8) {
                        ForEach(categories, id: \.self) { category in
                            row(for: category)
                        }
                    }
                    .padding(.top, 16)

                    Text("El límite no bloquea nada: si te pasas, la categoría se pinta en rojo y te avisa después.")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                        .padding(.top, 16)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 26)
            }
        }
        .background(palette.background)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(28)
    }

    private func row(for category: String) -> some View {
        let status = statuses[category]
        let color = CategoryStyle.color(for: category, accent: accent.color)

        return Button {
            onPick(category)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.22))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: CategoryStyle.icon(for: category))
                            .font(.footnote)
                            .foregroundStyle(color)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(category)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.label)
                    Text(status?.shortLabel ?? "Sin límite")
                        .font(.caption)
                        .foregroundStyle(status?.level.color(palette) ?? palette.secondaryLabel)
                }

                Spacer(minLength: 0)

                if category == suggestedCategory {
                    Text("sugerida")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(palette.positive)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(palette.positive.opacity(0.16))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .background(palette.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
