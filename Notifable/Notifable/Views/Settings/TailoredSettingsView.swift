import SwiftUI

/// Ajustes › A tu medida.
///
/// El sitio para los ajustes muy específicos —cómo responde un toque, qué
/// hace un gesto— que no cambian cómo se ve la app sino cómo se comporta para
/// quien la usa. Apariencia se queda con lo visual; cada ajuste nuevo de este
/// estilo entra aquí como una sección más, agrupada por la pantalla que toca.
struct TailoredSettingsView: View {

    @Environment(\.colorScheme) private var scheme
    @AppStorage(AppThemeColor.storageKey) private var appAccentColor = AppThemeColor.blue.rawValue
    @AppStorage(AppThemeColor.intenseTintKey) private var intenseThemeTint = false
    @AppStorage(DashboardView.tapTitleFiltersKey) private var tapTitleFilters = true
    @AppStorage(PeriodHeader.pinnedBarKey) private var pinsPeriodBar = true

    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .blue }
    private var palette: Palette { Palette(scheme, accent: accent) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Pequeños detalles de comportamiento para que AgruPay funcione a tu manera.")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
                    .padding(.horizontal, 20)

                pinnedPeriodBarSection

                activityTitleTapSection
            }
            .padding(.vertical, 16)
        }
        .background(palette.background)
        .navigationTitle("A tu medida")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Resumen, Categorías y Ritmo › Barra de periodo

    private var pinnedPeriodBarSection: some View {
        TailoredToggleSection(title: "Resumen, Categorías y Ritmo · Periodo",
                              isOn: $pinsPeriodBar,
                              label: "Fijar la barra de periodo arriba",
                              detail: pinsPeriodBar
                                ? "Las flechas, la fecha y el selector de día, semana o mes se quedan fijos bajo la cabecera al desplazarte."
                                : "La barra de periodo se desplaza con el resto del contenido.",
                              tint: accent.color)
    }

    // MARK: - Resumen › Actividad Reciente

    private var activityTitleTapSection: some View {
        TailoredToggleSection(title: "Resumen · Actividad reciente",
                              isOn: $tapTitleFilters,
                              label: "Tocar el nombre filtra por ese comercio",
                              detail: tapTitleFilters
                                ? "Al tocar el nombre de un movimiento, la lista se filtra por ese comercio."
                                : "Al tocar el nombre se abre el detalle, igual que al tocar el resto de la fila.",
                              tint: accent.color)
    }
}

/// Valor de la fila en la raíz de Configuración: cuántos ajustes se apartan
/// del comportamiento por defecto.
enum TailoredSettings {
    static func summary(tapTitleFilters: Bool, pinsPeriodBar: Bool) -> String {
        let changed = [tapTitleFilters != true, pinsPeriodBar != true].filter { $0 }.count
        if changed == 0 { return "Por defecto" }
        return changed == 1 ? "1 cambio" : "\(changed) cambios"
    }
}

/// Sección de un solo interruptor con título fuera y explicación que cambia
/// según el estado. Compartida por Apariencia y A tu medida.
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
