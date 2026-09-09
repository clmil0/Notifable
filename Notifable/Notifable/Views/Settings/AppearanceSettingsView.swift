import SwiftUI

/// Apariencia, con vista previa en vivo.
///
/// Elegir un color mirando un círculo de 12 pt en un `Picker` no dice cómo se
/// verá el monto grande ni el chip de categoría. La miniatura sí.
struct AppearanceSettingsView: View {

    @Environment(\.colorScheme) private var scheme
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.dark.rawValue
    @AppStorage(AppTextSize.storageKey) private var appTextSize = AppTextSize.sistema.rawValue
    @AppStorage(DashboardView.tapTitleFiltersKey) private var tapTitleFilters = true

    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .purple }
    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRaw) ?? .dark }
    private var palette: Palette { Palette(scheme) }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                preview
                accentPicker
                themePicker
                textSizePicker
                activityTitleTapSection
            }
            .padding(.vertical, 16)
        }
        .background(palette.background)
        .navigationTitle("Apariencia")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Toque en el título de Actividad Reciente

    private var activityTitleTapSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ACTIVIDAD RECIENTE")
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
                .padding(.horizontal, 20)

            Toggle(isOn: $tapTitleFilters) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tocar el nombre filtra por ese comercio")
                        .foregroundStyle(palette.label)
                    Text(tapTitleFilters
                         ? "Al tocar el nombre de un movimiento, la lista se filtra por ese comercio."
                         : "Al tocar el nombre se abre el detalle, igual que al tocar el resto de la fila.")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                }
            }
            .tint(accent.color)
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

    // MARK: - Vista previa

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("VISTA PREVIA")
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 12) {
                Text("GASTADO ESTE MES")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.secondaryLabel)

                Text(Money.format(1842.50))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.label)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.track)
                        Capsule().fill(accent.color).frame(width: geo.size.width * 0.77)
                    }
                }
                .frame(height: 10)

                Rectangle().fill(palette.separator).frame(height: 0.5)

                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.orange.opacity(0.2))
                            .frame(width: 34, height: 34)
                        Image(systemName: "fork.knife").foregroundStyle(.orange)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Metro")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.label)
                        Text("Comida · 19:04")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryLabel)
                    }
                    Spacer()
                    Text("- " + Money.format(86.40))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(palette.label)
                }
            }
            .padding(16)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Acento

    private var accentPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COLOR DE ACENTO")
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                ForEach(AppThemeColor.allCases) { theme in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { appAccentColor = theme.rawValue }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                if theme.isDuotone {
                                    // Medio círculo por acento, para que se
                                    // note de un vistazo que es un tema de
                                    // dos colores y no uno solo.
                                    Circle()
                                        .trim(from: 0, to: 0.5)
                                        .fill(theme.color)
                                        .rotationEffect(.degrees(-90))
                                        .frame(width: 46, height: 46)
                                    Circle()
                                        .trim(from: 0.5, to: 1)
                                        .fill(theme.secondaryColor)
                                        .rotationEffect(.degrees(-90))
                                        .frame(width: 46, height: 46)
                                } else {
                                    Circle()
                                        .fill(theme.color)
                                        .frame(width: 46, height: 46)
                                }
                                if appAccentColor == theme.rawValue {
                                    Circle()
                                        .stroke(Color.white, lineWidth: 2.5)
                                        .frame(width: 46, height: 46)
                                    Image(systemName: "checkmark")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            Text(theme.rawValue)
                                .font(.caption2)
                                .foregroundStyle(palette.secondaryLabel)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(width: 60, height: 72)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(theme.rawValue)
                    .accessibilityAddTraits(appAccentColor == theme.rawValue ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Tema

    private var themePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TEMA")
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
                .padding(.horizontal, 20)

            HStack(spacing: 10) {
                ForEach(AppAppearance.allCases) { option in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            appearanceRaw = option.rawValue
                        }
                    } label: {
                        themeCard(option)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(appearance == option ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func themeCard(_ option: AppAppearance) -> some View {
        let selected = appearance == option

        return VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(sample(option))
                .frame(height: 46)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(palette.hairline, lineWidth: 0.5)
                )

            Text(option.rawValue)
                .font(.caption)
                .foregroundStyle(selected ? accent.onSurface(scheme) : palette.secondaryLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(selected ? accent.softFill(scheme) : palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(selected ? accent.color.opacity(0.6) : palette.hairline, lineWidth: selected ? 1 : 0.5)
        )
    }

    private func sample(_ option: AppAppearance) -> AnyShapeStyle {
        switch option {
        case .system:
            return AnyShapeStyle(LinearGradient(colors: [.white, .black],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .light:
            return AnyShapeStyle(Color.white)
        case .dark:
            return AnyShapeStyle(Color.black)
        }
    }

    // MARK: - Tamaño de texto

    private var textSizePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TAMAÑO DE TEXTO")
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
                .padding(.horizontal, 20)

            Picker("Tamaño de letra", selection: $appTextSize) {
                ForEach(AppTextSize.allCases) { size in
                    Text(size.rawValue).tag(size.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            Text(appTextSize == AppTextSize.sistema.rawValue
                 ? "Se usa el tamaño de letra que tengas configurado en iOS."
                 : "Este tamaño manda sobre el que tengas configurado en iOS.")
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
                .padding(.horizontal, 20)
        }
    }
}
