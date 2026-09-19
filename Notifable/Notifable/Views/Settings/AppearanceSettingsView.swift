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
    @AppStorage(AppFontDesign.storageKey) private var appFontDesign = AppFontDesign.sistema.rawValue
    @AppStorage(AppThemeColor.intenseTintKey) private var intenseThemeTint = false
    @AppStorage(AppThemeColor.themedCategoryColorsKey) private var themedCategoryColors = false
    @AppStorage(DictationStyle.storageKey) private var dictationStyle = DictationStyle.bars.rawValue

    @State private var showsThemeGallery = false

    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .blue }
    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRaw) ?? .dark }
    private var palette: Palette { Palette(scheme, accent: accent, intense: intenseThemeTint) }

    var body: some View {
        VStack(spacing: 0) {
            // Fija arriba y siempre visible (`5b`): cada cambio se ve sin
            // volver a subir.
            preview
                .padding(.vertical, 12)
                .background(palette.background)

            ScrollView {
                VStack(spacing: 22) {
                    colorThemeRow
                    themePicker
                    fontDesignPicker
                    textSizePicker
                    intenseTintSection
                    categoryColorsSection
                    dictationSection
                }
                .padding(.vertical, 12)
            }
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

    private func sectionTitle(_ text: String, trailing: (String, () -> Void)? = nil) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 11.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(palette.secondaryLabel)
            Spacer()
            if let trailing {
                Button(trailing.0, action: trailing.1)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent.onSurface(scheme))
            }
        }
        .padding(.horizontal, 20)
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
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(accent.onSurface(scheme))
                        .padding(.top, 4)

                    previewBar
                        .padding(.top, 10)

                    HStack(spacing: 6) {
                        previewChip("Comida 34%", fill: accent.color, ink: .white)
                        previewChip("Ingresos", fill: accent.secondarySoftFill(scheme), ink: accent.secondaryOnSurface(scheme))
                        previewChip("Transporte", fill: palette.track, ink: palette.secondaryLabel)
                    }
                    .padding(.top, 11)
                }
                .padding(14)
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

    // MARK: - Tema de color

    /// Los temas son pares de color —gasto e ingreso—, no un swatch suelto
    /// (`5b`). Tres a la vista: el actual y dos más; el resto en «Ver todos».
    private var colorThemeRow: some View {
        let others = AppThemeColor.allCases.filter { $0 != accent }
        let shown = [accent] + Array(others.prefix(2))

        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("TEMA DE COLOR", trailing: ("Ver todos", { showsThemeGallery = true }))

            HStack(spacing: 10) {
                ForEach(shown, id: \.self) { theme in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { appAccentColor = theme.rawValue }
                    } label: {
                        VStack(spacing: 6) {
                            HStack(spacing: -6) {
                                Circle().fill(theme.color).frame(width: 22, height: 22)
                                Circle().fill(theme.incomeFillColor).frame(width: 22, height: 22)
                            }
                            Text(theme.rawValue)
                                .font(.system(size: 12.5, weight: theme == accent ? .semibold : .regular))
                                .foregroundStyle(palette.label)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(theme == accent ? accent.color : palette.hairline, lineWidth: theme == accent ? 1.5 : 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(theme == accent ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Tema claro / oscuro

    private var themePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("MODO")

            ShellSegment(items: AppAppearance.allCases, selection: appearanceBinding) { option in
                option == .system ? "Auto" : option.rawValue
            }
            .padding(.horizontal, 16)
        }
    }

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(get: { appearance }, set: { appearanceRaw = $0.rawValue })
    }

    // MARK: - Tipo de letra

    /// Cada opción se muestra escrita en su propio diseño: se elige viendo la
    /// letra, no leyendo su nombre.
    private var fontDesignPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("TIPO DE LETRA")

            HStack(spacing: 10) {
                ForEach(AppFontDesign.allCases) { option in
                    let selected = appFontDesign == option.rawValue
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { appFontDesign = option.rawValue }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Aa")
                                .font(.system(size: 28, weight: .semibold, design: option.design))
                                .foregroundStyle(palette.label)
                            Text(option.rawValue)
                                .font(.system(size: 13.5, weight: .semibold, design: option.design))
                                .foregroundStyle(palette.label)
                            Text(option.detail)
                                .font(.system(size: 11.5, design: option.design))
                                .foregroundStyle(palette.secondaryLabel)
                                .lineLimit(2, reservesSpace: true)
                        }
                        .fontDesign(option.design)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(selected ? accent.color : palette.hairline, lineWidth: selected ? 2 : 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(option.rawValue): \(option.detail)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Tamaño de texto

    private var textSizePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("TAMAÑO DE TEXTO")

            ShellSegment(items: AppTextSize.allCases.map(\.rawValue), selection: $appTextSize) { $0 }
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

// MARK: - Dictado

extension AppearanceSettingsView {
    /// Barras (`1a`) por defecto; la forma orgánica (`1c`) es la alternativa.
    fileprivate var dictationSection: some View {
        let organic = Binding(
            get: { dictationStyle == DictationStyle.blob.rawValue },
            set: { dictationStyle = ($0 ? DictationStyle.blob : .bars).rawValue }
        )
        return TailoredToggleSection(title: "Dictado por voz",
                                     isOn: organic,
                                     label: "Animación orgánica al escuchar",
                                     detail: organic.wrappedValue
                                        ? "Una forma que respira detrás del micrófono mientras hablas."
                                        : "Barras que siguen el volumen de tu voz.",
                                     tint: accent.color)
            .animation(.easeInOut(duration: 0.2), value: dictationStyle)
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
