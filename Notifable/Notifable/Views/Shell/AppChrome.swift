import SwiftUI

/// Medidas del chrome flotante. Las cifras salen del documento de diseño
/// (393×852), no de tanteos: cambiarlas aquí las cambia en las tres pestañas.
enum ShellMetrics {
    /// Alto reservado bajo la barra de estado para el header flotante.
    static let headerHeight: CGFloat = 52
    /// Desde el tope del área segura hasta el contenido que se desplaza. El
    /// header flota encima, no lo empuja: este hueco es sólo para que la
    /// primera fila no nazca tapada.
    static let contentTopInset: CGFloat = 48
    /// Espacio al pie para que la última fila no quede bajo las píldoras.
    static let contentBottomInset: CGFloat = 132

    static let circleButton: CGFloat = 36
    static let pillCorner: CGFloat = 999

    /// A partir de aquí el header se apoya en un blur y dibuja su hairline.
    static let blurThreshold: CGFloat = 24
    /// A partir de aquí el monto grande ya salió de pantalla y su versión
    /// compacta aparece centrada en el header.
    static let compactTitleThreshold: CGFloat = 180
}

// MARK: - Botón circular del header

/// Ajustes y tema. Flotan sobre el contenido, sin fondo de barra.
struct ShellCircleButton: View {
    let icon: String
    let label: String
    var tint: Color?
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    private var palette: Palette { Palette(scheme) }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint ?? palette.secondaryLabel)
                .frame(width: ShellMetrics.circleButton, height: ShellMetrics.circleButton)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(palette.hairline, lineWidth: 0.5))
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Píldora de sub-navegación

/// La píldora de la derecha del header: sólo íconos, 2 a 4 (`1a`).
///
/// Es genérica sobre `AppSubtab` porque las tres pestañas la dibujan igual y
/// lo único que cambia es el juego de íconos. Así una sola definición mantiene
/// el tamaño táctil, el relleno del activo y el badge en un único sitio.
struct SubtabPill<Tab: AppSubtab>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    var badge: (Tab) -> Int? = { _ in nil }

    @Environment(\.colorScheme) private var scheme
    private var palette: Palette { Palette(scheme) }
    private var accent: AppThemeColor { .current }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                Button {
                    guard selection != tab else { return }
                    withAnimation(.easeInOut(duration: 0.26)) { selection = tab }
                } label: {
                    ZStack {
                        if selection == tab {
                            Circle().fill(accent.color)
                                .matchedGeometryEffect(id: "subtab", in: namespace)
                        }
                        Image(systemName: tab.icon)
                            .font(.system(size: 17, weight: selection == tab ? .semibold : .regular))
                            .foregroundStyle(selection == tab ? Color.white : palette.secondaryLabel)
                    }
                    .frame(width: ShellMetrics.circleButton, height: ShellMetrics.circleButton)
                    .overlay(alignment: .topTrailing) {
                        if let count = badge(tab), selection != tab {
                            Text(count > 99 ? "99+" : "\(count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(palette.negative, in: Capsule())
                                .offset(x: 3, y: -1)
                        }
                    }
                    .contentShape(Circle())
                }
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(palette.hairline, lineWidth: 0.5))
        .shadow(color: Color.black.opacity(0.06), radius: 7, y: 4)
        // Un ícono que entra o sale (Pendientes) no debe hacer saltar la
        // píldora: se anima el ancho, no un corte seco.
        .animation(.easeInOut(duration: 0.25), value: tabs.count)
    }

    @Namespace private var namespace
}

// MARK: - Header flotante

/// Transparente del todo arriba del scroll; con blur y hairline en cuanto el
/// contenido pasa por debajo; con el monto compacto cuando el grande se fue
/// de pantalla (`1h`).
struct ShellHeader<Pill: View>: View {
    let scrollOffset: CGFloat
    let compactTitle: String?
    let onSettings: () -> Void
    let onTheme: () -> Void
    @ViewBuilder var pill: Pill

    @Environment(\.colorScheme) private var scheme
    private var palette: Palette { Palette(scheme) }

    private var showsBackground: Bool { scrollOffset > ShellMetrics.blurThreshold }
    private var showsCompactTitle: Bool {
        compactTitle != nil && scrollOffset > ShellMetrics.compactTitleThreshold
    }

    var body: some View {
        HStack(spacing: 8) {
            ShellCircleButton(icon: "gearshape", label: "Configuración", action: onSettings)
            // Muestra el modo al que lleva, no el actual: luna en claro, sol
            // en oscuro.
            ShellCircleButton(icon: scheme == .dark ? "sun.max" : "moon",
                              label: scheme == .dark ? "Cambiar a modo claro" : "Cambiar a modo oscuro",
                              action: onTheme)

            Spacer(minLength: 8)

            if showsCompactTitle, let compactTitle {
                Text(compactTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .transition(.opacity.combined(with: .offset(y: 6)))

                Spacer(minLength: 8)
            }

            pill
        }
        .padding(.horizontal, 16)
        .frame(height: ShellMetrics.headerHeight)
        .background {
            if showsBackground {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .top)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(palette.hairline).frame(height: 0.5)
                    }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showsBackground)
        .animation(.easeInOut(duration: 0.2), value: showsCompactTitle)
    }
}

// MARK: - Zona inferior (variante A)

/// Píldora de tabs y píldora de acciones, lado a lado (`1f`).
///
/// Al hacer scroll hacia abajo las tabs pierden la etiqueta y conservan el
/// alto táctil; la de acciones nunca se oculta, porque registrar un gasto es
/// lo que la app pide hacer más veces al día.
struct ShellBottomBar: View {
    @Binding var selection: AppTab
    /// El objeto, no un `Bool` ya leído: quien lee `isScrollingDown` se vuelve
    /// a dibujar al desplazarse, y eso tiene que quedarse dentro de esta barra
    /// en vez de arrastrar al cuerpo que la coloca. Ver `ShellHeaderBar`.
    let progress: ScrollProgress
    /// Con el menú del `+` abierto, el `+` gira 45° y se vuelve la ✕ que lo
    /// cierra: el mismo toque que abrió, cierra.
    var isAddMenuOpen: Bool = false
    /// Con el dictado abierto, el mic se tiñe del tema.
    var isDictating: Bool = false
    /// Un número sobre el ícono de la pestaña (solicitudes de amistad en Social).
    var badge: (AppTab) -> Int? = { _ in nil }
    let onReselect: (AppTab) -> Void
    let onAdd: () -> Void
    let onDictate: () -> Void

    @Environment(\.colorScheme) private var scheme
    private var palette: Palette { Palette(scheme) }
    private var accent: AppThemeColor { .current }

    private var compact: Bool { progress.isScrollingDown }

    var body: some View {
        HStack(spacing: 10) {
            tabsPill
            actionsPill
        }
        .padding(.horizontal, 16)
    }

    private var tabsPill: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    if selection == tab {
                        onReselect(tab)
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            selection = tab
                        }
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: selection == tab ? .semibold : .regular))
                            .foregroundStyle(selection == tab ? Color.white : palette.secondaryLabel)
                            .frame(width: 50, height: 30)
                            .background {
                                if selection == tab {
                                    Capsule().fill(accent.color)
                                }
                            }
                            .overlay(alignment: .topTrailing) {
                                if let count = badge(tab), count > 0 {
                                    Text(count > 99 ? "99+" : "\(count)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color.white)
                                        .padding(.horizontal, 4)
                                        .frame(minWidth: 16, minHeight: 16)
                                        .background(palette.negative, in: Capsule())
                                        .offset(x: 3, y: -1)
                                }
                            }

                        if !compact {
                            Text(tab.title)
                                .font(.system(size: 10.5, weight: selection == tab ? .bold : .regular))
                                .foregroundStyle(selection == tab ? accent.onSurface(scheme) : palette.secondaryLabel)
                        }
                    }
                    // El alto táctil se conserva aunque se vaya la etiqueta.
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.vertical, compact ? 2 : 6)
        .padding(.horizontal, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(palette.hairline, lineWidth: 0.5))
        .shadow(color: Color.black.opacity(0.12), radius: 13, y: 8)
        .animation(.easeInOut(duration: 0.22), value: compact)
    }

    private var actionsPill: some View {
        HStack(spacing: 2) {
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .rotationEffect(.degrees(isAddMenuOpen ? 45 : 0))
                    .frame(width: 46, height: 46)
                    .background(accent.color, in: Circle())
                    .shadow(color: accent.color.opacity(0.35), radius: 5, y: 3)
            }
            .accessibilityLabel(isAddMenuOpen ? "Cerrar" : "Registrar movimiento")

            Button(action: onDictate) {
                Image(systemName: isDictating ? "mic.fill" : "mic")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isDictating ? accent.color : palette.secondaryLabel)
                    .frame(width: 36, height: 46)
            }
            .accessibilityLabel("Dictar un gasto")
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(palette.hairline, lineWidth: 0.5))
        .shadow(color: Color.black.opacity(0.12), radius: 13, y: 8)
    }
}
