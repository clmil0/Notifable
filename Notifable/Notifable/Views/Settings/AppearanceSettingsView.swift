import SwiftUI

/// Apariencia, con vista previa en vivo (`1e`).
///
/// Elegir un color mirando un círculo de 12 pt no dice cómo se verá el monto
/// grande, la barra ni la pestaña activa. La vista previa de arriba sí, y
/// "Ver todos" abre una galería donde cada tema es un mini-Resumen real.
struct AppearanceSettingsView: View {

    @Environment(\.colorScheme) private var scheme
    @AppStorage(AppThemeColor.storageKey) private var appAccentColor = AppThemeColor.blue.rawValue
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.dark.rawValue
    @AppStorage(AppTextSize.storageKey) private var appTextSize = AppTextSize.sistema.rawValue
    @AppStorage(AppThemeColor.intenseTintKey) private var intenseThemeTint = false
    @AppStorage(AppThemeColor.themedCategoryColorsKey) private var themedCategoryColors = false

    @State private var showsThemeGallery = false

    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .blue }
    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRaw) ?? .dark }
    private var palette: Palette { Palette(scheme, accent: accent, intense: intenseThemeTint) }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                preview
                colorThemeRow
                themePicker
                textSizePicker
                intenseTintSection
                categoryColorsSection
            }
            .padding(.vertical, 16)
        }
        .background(palette.background)
        .navigationTitle("Apariencia")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showsThemeGallery) {
            ThemeGalleryView(current: accent) { theme in
                withAnimation(.easeInOut(duration: 0.2)) { appAccentColor = theme.rawValue }
            }
            .appAppearance()
            .appTextSize()
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(palette.secondaryLabel)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Vista previa

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("VISTA PREVIA")

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("GASTADO ESTE MES")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(accent.onSurface(scheme))
                        Spacer()
                        Text("quedan 18 días")
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryLabel)
                    }

                    Text(Money.format(1842.50))
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.label)
                        .padding(.top, 4)

                    previewBar
                        .padding(.top, 10)

                    HStack(spacing: 6) {
                        previewChip("Comida 34%", fill: accent.softFill(scheme), ink: accent.onSurface(scheme))
                        previewChip("Ingresos", fill: accent.secondarySoftFill(scheme), ink: accent.secondaryOnSurface(scheme))
                        previewChip("Transporte", fill: palette.track, ink: palette.secondaryLabel)
                    }
                    .padding(.top, 11)

                    previewBanner
                        .padding(.top, 11)
                }
                .padding(14)

                previewTabBar
            }
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
            .animation(.easeInOut(duration: 0.2), value: appAccentColor)
        }
    }

    /// La barra con su marca de ritmo, igual que en Resumen.
    private var previewBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.track)
                Capsule()
                    .fill(accent.color)
                    .frame(width: geo.size.width * 0.77)
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2)
                    .offset(x: geo.size.width * 0.60)
            }
        }
        .frame(height: 10)
        .clipShape(Capsule())
    }

    private func previewChip(_ text: String, fill: Color, ink: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(fill)
            .clipShape(Capsule())
            .lineLimit(1)
    }

    private var previewBanner: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent.color)
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: "tray.full.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text("3 comercios sin clasificar")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(palette.label)
                Text(Money.format(214.90) + " sin categoría")
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryLabel)
            }
            Spacer(minLength: 0)
            Text("Clasificar")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(accent.color)
                .clipShape(Capsule())
        }
        .padding(9)
        .background(accent.softFill(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var previewTabBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: AppTab.home.icon)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 16)
                    .background(accent.color)
                    .clipShape(Capsule())
                Text(AppTab.home.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(accent.onSurface(scheme))
            }
            ForEach([AppTab.categories, AppTab.trends], id: \.self) { tab in
                HStack(spacing: 5) {
                    Image(systemName: tab.icon)
                        .font(.caption2)
                    Text(tab.title)
                        .font(.caption2)
                }
                .foregroundStyle(palette.secondaryLabel)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(palette.surfaceElevated.opacity(0.6))
        .overlay(alignment: .top) {
            Rectangle().fill(palette.separator).frame(height: 0.5)
        }
    }

    // MARK: - Tema de color

    private var colorThemeRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("TEMA DE COLOR")

            Button { showsThemeGallery = true } label: {
                HStack(spacing: 12) {
                    ThemeSwatch(theme: accent, size: 30)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(accent.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.label)
                        Text(accent.themeKindLabel + " · \(AppThemeColor.allCases.count) temas disponibles")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryLabel)
                    }

                    Spacer(minLength: 8)

                    Text("Ver todos")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent.onSurface(scheme))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(accent.softFill(scheme))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(palette.hairline, lineWidth: 0.5)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .accessibilityLabel("Tema de color: \(accent.rawValue). Ver todos los temas")
        }
    }

    // MARK: - Tema claro / oscuro

    private var themePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("TEMA")

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

    /// La opción elegida se marca con el tinte del tema, sin borde de color.
    private func themeCard(_ option: AppAppearance) -> some View {
        let selected = appearance == option

        return VStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(sample(option))
                .frame(height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(palette.hairline, lineWidth: 0.5)
                )

            Text(option.rawValue)
                .font(.caption.weight(selected ? .semibold : .regular))
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
                .stroke(palette.hairline, lineWidth: 0.5)
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
            sectionTitle("TAMAÑO DE TEXTO")

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

    // MARK: - Intensificar el color

    private var intenseTintSection: some View {
        TailoredToggleSection(title: "Intensidad del tema",
                              isOn: $intenseThemeTint,
                              label: "Intensificar el color del tema",
                              detail: intenseThemeTint
                                ? "Las tarjetas y sus bordes llevan un tinte del tema en toda la app."
                                : "Tarjetas en gris neutro; el tema se ve en botones, barras y acentos.",
                              tint: accent.color)
            .animation(.easeInOut(duration: 0.2), value: intenseThemeTint)
    }

    // MARK: - Colores de categoría

    private var categoryColorsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TailoredToggleSection(title: "Colores de categoría",
                                  isOn: $themedCategoryColors,
                                  label: "Usar los colores del tema",
                                  detail: themedCategoryColors
                                    ? "Las categorías toman tonos armonizados del tema. Las que tengan un color elegido a mano lo conservan."
                                    : "Cada categoría usa su propio color.",
                                  tint: accent.color)

            if themedCategoryColors {
                HStack(spacing: 6) {
                    ForEach(Array(accent.categoryRamp(scheme).prefix(5).enumerated()), id: \.offset) { _, color in
                        Circle().fill(color).frame(width: 14, height: 14)
                    }
                }
                .padding(.horizontal, 20)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: themedCategoryColors)
    }
}

// MARK: - Muestra de tema

/// Círculo del tema: entero en los de un color, partido a la mitad en los de
/// dos, para que se note de un vistazo.
struct ThemeSwatch: View {
    let theme: AppThemeColor
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            if theme.isDuotone {
                Circle()
                    .trim(from: 0, to: 0.5)
                    .fill(theme.color)
                    .rotationEffect(.degrees(90))
                Circle()
                    .trim(from: 0.5, to: 1)
                    .fill(theme.secondaryColor)
                    .rotationEffect(.degrees(90))
            } else {
                Circle().fill(theme.color)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Galería de temas

/// Modal a pantalla completa con todos los temas (`1e`). Cada tarjeta es un
/// mini-Resumen con los colores de ese tema; elegir uno sólo lo marca, y
/// "Usar …" lo aplica y cierra.
struct ThemeGalleryView: View {

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Todos"
        case single = "Un color"
        case duo = "Dos colores"
        var id: String { rawValue }
    }

    let current: AppThemeColor
    var onApply: (AppThemeColor) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var draft: AppThemeColor
    @State private var filter: Filter = .all

    init(current: AppThemeColor, onApply: @escaping (AppThemeColor) -> Void) {
        self.current = current
        self.onApply = onApply
        _draft = State(initialValue: current)
    }

    /// La galería se pinta con el tema que se está probando, no con el guardado.
    private var palette: Palette { Palette(scheme, accent: draft) }

    private var themes: [AppThemeColor] {
        let filtered = AppThemeColor.allCases.filter { theme in
            switch filter {
            case .all: return true
            case .single: return !theme.isDuotone
            case .duo: return theme.isDuotone
            }
        }
        // El tema en uso va primero.
        return filtered.filter { $0 == current } + filtered.filter { $0 != current }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Picker("Filtro", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)],
                          spacing: 11) {
                    ForEach(themes) { theme in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { draft = theme }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            ThemeGalleryCard(theme: theme, isSelected: draft == theme, palette: palette)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(theme.rawValue)
                        .accessibilityAddTraits(draft == theme ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .animation(.easeInOut(duration: 0.2), value: filter)
            }

            footer
        }
        .background(palette.background.ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            Text("Temas")
                .font(.title2.bold())
                .foregroundStyle(palette.label)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(palette.secondaryLabel)
                    .frame(width: 30, height: 30)
                    .background(palette.track)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cerrar")
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var footer: some View {
        VStack(spacing: 9) {
            Text(draft.isDuotone
                 ? "El segundo color se usa en ingresos, “hoy” y lo que baja."
                 : "Un solo color para gasto, ingresos y “hoy”.")
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
                .multilineTextAlignment(.center)

            Button {
                onApply(draft)
                dismiss()
            } label: {
                Text(draft == current ? "Seguir con " + draft.rawValue : "Usar " + draft.rawValue)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(draft.color)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(
            palette.surfaceElevated.opacity(0.92)
                .overlay(alignment: .top) {
                    Rectangle().fill(palette.separator).frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

/// Mini-Resumen con los colores de un tema.
private struct ThemeGalleryCard: View {

    let theme: AppThemeColor
    let isSelected: Bool
    let palette: Palette

    private var scheme: ColorScheme { palette.scheme }
    private var dark: Bool { scheme == .dark }
    private var miniTrack: Color { dark ? Color.white.opacity(0.14) : Color(red: 0.890, green: 0.890, blue: 0.909) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text("GASTADO")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(theme.onSurface(scheme))
                Text("S/ 1,842")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(dark ? Color.white : Color.black)
                    .padding(.top, 2)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(miniTrack)
                        Capsule()
                            .fill(theme.color)
                            .frame(width: geo.size.width * 0.72)
                    }
                }
                .frame(height: 5)
                .padding(.top, 6)

                HStack(spacing: 4) {
                    Capsule().fill(theme.color)
                    Capsule().fill(theme.isDuotone ? theme.secondaryColor : theme.color.opacity(0.45))
                    Capsule().fill(miniTrack)
                }
                .frame(height: 12)
                .padding(.top, 7)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (dark ? Color(red: 0.082, green: 0.082, blue: 0.090) : Color.white)
                    .mixed(with: theme.color, amount: dark ? 0.08 : 0.05, scheme: scheme)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 6) {
                ThemeSwatch(theme: theme, size: 14)
                Text(theme.rawValue)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.label)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(theme.onSurface(scheme))
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(9)
        // Seleccionado = tinte del propio tema, sin borde de color.
        .background(isSelected ? theme.softFill(scheme) : Palette(scheme, accent: theme).surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Palette(scheme, accent: theme).hairline, lineWidth: 0.5)
        )
    }
}
