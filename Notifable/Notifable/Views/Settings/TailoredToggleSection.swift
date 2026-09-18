import SwiftUI

/// Sección de un interruptor con su explicación debajo, la del bloque
/// "Apariencia". Vivía en `TailoredSettingsView`, que desapareció con el
/// rediseño: sus dos ajustes —filtrar al tocar el nombre y fijar la barra de
/// periodo— eran de pantallas que ya no existen.

struct TailoredToggleSection: View {

    let title: String
    @Binding var isOn: Bool
    let label: String
    let detail: String
    let tint: Color

    @Environment(\.colorScheme) private var scheme
    @AppStorage(AppThemeColor.storageKey) private var appAccentColor = AppThemeColor.blue.rawValue
    @AppStorage(AppThemeColor.intenseTintKey) private var intenseThemeTint = false
    private var palette: Palette { Palette(scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
                .padding(.horizontal, 20)

            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .foregroundStyle(palette.label)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                }
            }
            .tint(tint)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
        }
    }
}
