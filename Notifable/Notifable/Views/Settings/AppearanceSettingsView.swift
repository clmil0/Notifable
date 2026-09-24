import SwiftUI

/// Apariencia (`1c`): un mini-Resumen fijo arriba y los ajustes por pestaña.
///
/// La vista previa es una miniatura del dashboard real —cuentas, monto,
/// barras, tarjetas, Dictar y +— para que cada ajuste tenga dónde notarse, y
/// marca con un anillo lo que acaba de cambiar.
struct AppearanceSettingsView: View {

    enum Tab: String, CaseIterable {
        case color = "Color"
        case text = "Texto"
        case voice = "Voz"
    }

    /// La parte de la vista previa que se ilumina tras un cambio.
    enum Flash { case surface, cats, type, dict }

    @Environment(\.colorScheme) private var scheme
    @AppStorage(AppThemeColor.storageKey) private var appAccentColor = AppThemeColor.blue.rawValue
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.dark.rawValue
    @AppStorage(AppTextSize.storageKey) private var appTextSize = AppTextSize.sistema.rawValue
    @AppStorage(AppFontDesign.storageKey) private var appFontDesign = AppFontDesign.sistema.rawValue
    @AppStorage(AppThemeColor.intenseTintKey) private var intenseThemeTint = false
    @AppStorage(AppThemeColor.themedCategoryColorsKey) private var themedCategoryColors = false
    @AppStorage(DictationStyle.storageKey) private var dictationStyle = DictationStyle.bars.rawValue

    @State private var tab: Tab = .color
    @State private var flash: Flash?
    @State private var flashTask: Task<Void, Never>?
    @State private var recentThemes = AppThemeColor.recent()
    @State private var showsThemeGallery = false

    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .blue }
    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRaw) ?? .dark }
    private var palette: Palette { Palette(scheme, accent: accent, intense: intenseThemeTint) }
    private var textSize: AppTextSize { AppTextSize(rawValue: appTextSize) ?? .sistema }
    private var fontDesign: AppFontDesign { AppFontDesign(rawValue: appFontDesign) ?? .sistema }

    var body: some View {
        VStack(spacing: 0) {
            AppearancePreview(palette: palette, flash: flash, dictationStyle: dictationStyle,
                              amountScale: textSize.amountScale)
                .padding(.horizontal, 16)
                .padding(.top, 6)

            ShellSegment(items: Tab.allCases, selection: $tab) { $0.rawValue }
                .padding(.horizontal, 16)
                .padding(.top, 14)

            ScrollView {
                Group {
                    switch tab {
                    case .color: colorTab
                    case .text: textTab
                    case .voice: voiceTab
                    }
                }
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .background(palette.background)
        .navigationTitle("Apariencia")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut(duration: 0.3), value: appAccentColor)
        .animation(.easeInOut(duration: 0.3), value: intenseThemeTint)
        .onChange(of: appAccentColor) { _, raw in
            if let theme = AppThemeColor(rawValue: raw) { AppThemeColor.noteUsed(theme) }
            recentThemes = AppThemeColor.recent()
            ring(.surface)
        }
        .onChange(of: intenseThemeTint) { _, _ in ring(.surface) }
        .onChange(of: themedCategoryColors) { _, _ in ring(.cats) }
        .onChange(of: appFontDesign) { _, _ in ring(.type) }
        .onChange(of: appTextSize) { _, _ in ring(.type) }
        .onChange(of: dictationStyle) { _, _ in ring(.dict) }
        .onDisappear { flashTask?.cancel() }
        .fullScreenCover(isPresented: $showsThemeGallery) {
            ThemeGalleryView(current: accent) { theme in
                withAnimation(.easeInOut(duration: 0.2)) { appAccentColor = theme.rawValue }
            }
            .appAppearance()
            .appTextSize()
        }
    }

    /// Enciende el anillo de una parte de la vista previa durante un segundo.
    private func ring(_ part: Flash) {
        withAnimation(.easeOut(duration: 0.25)) { flash = part }
        flashTask?.cancel()
        flashTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1100))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.35)) { flash = nil }
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

    private func block<Content: View>(_ title: String, spacing: CGFloat = 8,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            sectionTitle(title)
            content()
        }
    }

    // MARK: - Color

    private var colorTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("TEMA · " + accent.rawValue.uppercased(),
                             trailing: ("Ver todos", { showsThemeGallery = true }))
                themeRow
            }

            block("TARJETAS") {
                ShellSegment(items: [false, true], selection: $intenseThemeTint) { $0 ? "Con tinte" : "Neutras" }
                    .overlay { segmentChips(count: 2) { index in intenseChip(index == 1) } }
                    .padding(.horizontal, 16)
            }

            block("CATEGORÍAS") {
                ShellSegment(items: [false, true], selection: $themedCategoryColors) { $0 ? "Del tema" : "Propios" }
                    .overlay { segmentChips(count: 2) { index in categoryDots(themed: index == 1) } }
                    .padding(.horizontal, 16)
            }

            block("MODO") {
                ShellSegment(items: AppAppearance.allCases, selection: appearanceBinding) { option in
                    option == .system ? "Auto" : option.rawValue
                }
                .padding(.horizontal, 16)
            }
        }
    }

    /// Los seis temas usados más recientemente, en círculo; el elegido con
    /// anillo. El resto, en «Ver todos».
    private var themeRow: some View {
        HStack {
            ForEach(recentThemes) { theme in
                let selected = theme == accent
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { appAccentColor = theme.rawValue }
                } label: {
                    ThemeSwatch(theme: theme, size: 36)
                        .padding(4)
                        .overlay(Circle().stroke(selected ? theme.onSurface(scheme) : .clear, lineWidth: 2))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(theme.rawValue)
                .accessibilityAddTraits(selected ? .isSelected : [])
                if theme != recentThemes.last { Spacer(minLength: 0) }
            }
        }
        .padding(.horizontal, 18)
    }

    /// La muestra va dentro del segmento, delante del texto: se superpone en
    /// la mitad que le toca a cada opción.
    private func segmentChips<Chip: View>(count: Int, @ViewBuilder chip: @escaping (Int) -> Chip) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                chip(index)
                    .padding(.leading, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(4)
        .allowsHitTesting(false)
    }

    private func intenseChip(_ tinted: Bool) -> some View {
        let sample = Palette(scheme, accent: accent, intense: tinted)
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(sample.surface)
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(tinted ? accent.color.opacity(0.6) : palette.label.opacity(0.18), lineWidth: 1))
            .frame(width: 12, height: 12)
    }

    private func categoryDots(themed: Bool) -> some View {
        let ramp = accent.categoryRamp(scheme)
        let own: [Color] = ["Comida", "Supermercado", "Transporte"]
            .map { CategoryStyle.defaultColor(for: $0, accent: accent.color) }
        let colors = themed ? Array(ramp.prefix(3)) : own
        return HStack(spacing: -3) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(palette.surface, lineWidth: 1.5))
            }
        }
    }

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(get: { appearance }, set: { appearanceRaw = $0.rawValue })
    }

    // MARK: - Texto

    private var textTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            block("TIPO DE LETRA", spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(AppFontDesign.allCases) { option in
                        fontTile(option)
                    }
                }
                .padding(.horizontal, 16)
            }

            block("TAMAÑO DE TEXTO", spacing: 10) {
                ShellSegment(items: AppTextSize.allCases.map(\.rawValue), selection: $appTextSize) { $0 }
                    .padding(.horizontal, 16)

                Text(textSize == .sistema
                     ? "Se usa el tamaño de letra que tengas configurado en iOS."
                     : "Este tamaño manda sobre el que tengas configurado en iOS.")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                    .padding(.horizontal, 20)
            }
        }
    }

    /// Cada opción escrita en su propio diseño: se elige viendo la letra.
    private func fontTile(_ option: AppFontDesign) -> some View {
        let selected = fontDesign == option
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { appFontDesign = option.rawValue }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Aa")
                    .font(.system(size: 26, weight: .semibold, design: option.design))
                Text(option.rawValue)
                    .font(.system(size: 13, weight: .semibold, design: option.design))
            }
            .foregroundStyle(palette.label)
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

    // MARK: - Voz

    private var voiceTab: some View {
        block("ANIMACIÓN AL ESCUCHAR", spacing: 10) {
            HStack(spacing: 10) {
                dictationTile(.bars, name: "Barras", detail: "Siguen el volumen de tu voz.")
                dictationTile(.blob, name: "Orgánica", detail: "Una forma que respira tras el micrófono.")
            }
            .padding(.horizontal, 16)

            Text("También se ve en la píldora «Dictar» de la vista previa.")
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
                .padding(.horizontal, 20)
        }
    }

    private func dictationTile(_ style: DictationStyle, name: String, detail: String) -> some View {
        let selected = dictationStyle == style.rawValue
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { dictationStyle = style.rawValue }
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.background)
                    DictationIndicator(style: style, size: .tile)
                        .padding(.horizontal, 12)
                }
                .frame(height: 74)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(palette.label)
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.secondaryLabel)
                        .lineLimit(2, reservesSpace: true)
                }
                .padding(.horizontal, 2)
            }
            .padding(10)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? accent.color : palette.hairline, lineWidth: selected ? 2 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name): \(detail)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Indicador de dictado en miniatura

/// Las mismas animaciones de la hoja de dictado, a escala de muestra.
struct DictationIndicator: View {
    enum Size { case pill, tile }

    let style: DictationStyle
    let size: Size

    private var accent: AppThemeColor { .current }

    var body: some View {
        switch style {
        case .bars:
            DictationBars(level: 0.55, isActive: true,
                          count: size == .pill ? 5 : 14,
                          height: size == .pill ? 18 : 40,
                          spacing: 3)
                .frame(width: size == .pill ? 26 : nil)
        case .blob:
            let diameter: CGFloat = size == .pill ? 26 : 44
            ZStack {
                DictationBlob(level: 0.3, isActive: true, size: diameter)
                Circle()
                    .fill(accent.color)
                    .frame(width: diameter * 0.72, height: diameter * 0.72)
                Image(systemName: "mic.fill")
                    .font(.system(size: diameter * 0.33, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Vista previa

/// Mini-Resumen: chip de cuentas, monto con su delta, barras, dos tarjetas,
/// la píldora de Dictar y el +. Cifras de muestra fijas.
private struct AppearancePreview: View {
    let palette: Palette
    let flash: AppearanceSettingsView.Flash?
    let dictationStyle: String
    let amountScale: CGFloat

    private static let bars: [Double] = [64, 92, 38, 12, 71, 55, 84]

    private var scheme: ColorScheme { palette.scheme }
    private var accent: AppThemeColor { palette.accent }
    private var month: String { Period.spanishMonthName(for: Date()).uppercased() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                accountChip
                Spacer()
                Text("VISTA PREVIA")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(palette.tertiaryLabel)
            }

            amount
                .ringed(flash == .type, color: accent.color)

            bars

            HStack(spacing: 10) {
                categoriesCard
                    .ringed(flash == .cats, color: accent.color, radius: 16)
                pendingCard
                    .ringed(flash == .surface, color: accent.color, radius: 16)
            }
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                dictationPill
                    .ringed(flash == .dict, color: accent.color, radius: 19)
                Spacer()
                Circle()
                    .fill(accent.color)
                    .frame(width: 42, height: 42)
                    .overlay(Image(systemName: "plus").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white))
                    .shadow(color: accent.color.opacity(0.38), radius: 11)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(palette.background, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .stroke(palette.label.opacity(0.09), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vista previa del resumen con la apariencia elegida")
    }

    private var accountChip: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(accent.softFill(scheme))
                .frame(width: 18, height: 18)
                .overlay(Image(systemName: "building.columns.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(accent.onSurface(scheme)))
            Text("Todas las cuentas")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(palette.label)
        }
        .padding(.leading, 5)
        .padding(.trailing, 10)
        .frame(height: 28)
        .background(palette.surface, in: Capsule())
        .overlay(Capsule().stroke(palette.hairline, lineWidth: 0.5))
    }

    private var amount: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("GASTADO EN " + month)
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.25)
                .foregroundStyle(palette.secondaryLabel)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("S/ 2,612")
                    .font(.system(size: 34 * amountScale, weight: .bold))
                    .tracking(-1.2)
                    .foregroundStyle(palette.label)
                Text(".40")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.secondaryLabel)
                Text("↑ S/ 318 vs. mes anterior")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent.isDuotone ? accent.secondaryOnSurface(scheme) : accent.onSurface(scheme))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(accent.isDuotone ? accent.secondarySoftFill(scheme) : palette.expenseSoft,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .padding(.leading, 4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(2)
    }

    private var bars: some View {
        let top = palette.expense.mixed(with: .white, amount: 0.28, scheme: scheme)
        let peak = Self.bars.max() ?? 1
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(Self.bars.enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(LinearGradient(colors: [palette.expense, top], startPoint: .bottom, endPoint: .top))
                    .frame(height: max(4, 58 * value / peak))
                    .opacity(index == Self.bars.count - 1 ? 1 : 0.55)
            }
        }
        .frame(height: 58)
    }

    private var categoriesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Categorías")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(palette.label)
            ForEach(["Comida", "Transporte"], id: \.self) { name in
                let color = CategoryStyle.color(for: name, accent: accent.color)
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(color.opacity(0.22))
                        .frame(width: 22, height: 22)
                        .overlay(Image(systemName: CategoryStyle.icon(for: name))
                            .font(.system(size: 11))
                            .foregroundStyle(color))
                    Text(name)
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.label)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(palette.hairline, lineWidth: 0.5))
    }

    private var pendingCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pendientes")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(palette.label)
            Text("3")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(accent.secondaryOnSurface(scheme))
            Text("de este mes")
                .font(.system(size: 11))
                .foregroundStyle(palette.secondaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(palette.hairline, lineWidth: 0.5))
    }

    private var dictationPill: some View {
        HStack(spacing: 8) {
            DictationIndicator(style: DictationStyle(rawValue: dictationStyle) ?? .bars, size: .pill)
                .frame(width: 30, height: 30)
            Text("Escuchando…")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(accent.onSurface(scheme))
        }
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .frame(height: 38)
        .background(palette.surface, in: Capsule())
        .overlay(Capsule().stroke(palette.hairline, lineWidth: 0.5))
    }
}

private extension View {
    /// El anillo de «esto cambió»: borde del acento con un halo suave.
    func ringed(_ on: Bool, color: Color, radius: CGFloat = 10) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(color, lineWidth: 2)
                .padding(-2)
                .background(
                    RoundedRectangle(cornerRadius: radius + 5, style: .continuous)
                        .stroke(color.opacity(0.22), lineWidth: 5)
                        .padding(-4.5)
                )
                .opacity(on ? 1 : 0)
                .allowsHitTesting(false)
        )
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
