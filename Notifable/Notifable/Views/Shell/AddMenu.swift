import SwiftUI

/// El menú del `+` (`4a`): dos destinos, no un popover.
///
/// Sustituye a la cajita de dos íconos que salía a la derecha. Dos tarjetas
/// anchas al alcance del pulgar, cada una con una línea que dice **cuándo** se
/// usa: la app registra casi todo sola desde el correo, así que la pregunta
/// real al tocar `+` no es «¿gasto o ingreso?» sino «¿esto es de lo que no
/// llega por correo?».
struct AddMenu: View {
    let onPick: (TransactionType) -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var scheme
    private var palette: Palette { Palette(scheme) }
    private var accent: AppThemeColor { .current }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Velo con desenfoque: lo de atrás se sigue intuyendo —sabes en qué
            // pantalla estabas—, pero deja de competir con las dos opciones.
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(scheme == .dark ? 0.35 : 0.12))
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
                .transition(.opacity)

            VStack(spacing: 10) {
                option(title: "Gasto",
                       detail: "Lo que pagaste en efectivo o no llegó por correo",
                       icon: "arrow.down.left",
                       tint: accent.color,
                       type: .gasto)

                option(title: "Ingreso",
                       detail: "Sueldo, transferencia o un cobro que te devolvieron",
                       icon: "arrow.up.right",
                       tint: accent.incomeFillColor,
                       type: .ingreso)
            }
            .padding(.horizontal, 16)
            // Por encima de las píldoras: el `+` —ahora ✕— tiene que seguir a
            // la vista para cerrar con el mismo toque que abrió.
            .padding(.bottom, 92)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func option(title: String, detail: String, icon: String,
                        tint: Color, type: TransactionType) -> some View {
        Button {
            onPick(type)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.label)
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(palette.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surfaceElevated,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(palette.hairline, lineWidth: 0.5))
            .shadow(color: Color.black.opacity(0.10), radius: 14, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(detail)
    }
}
