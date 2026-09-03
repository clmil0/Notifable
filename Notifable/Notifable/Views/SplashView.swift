import SwiftUI

/// Color e identidad de marca del ícono y el splash: azul, acabado plano.
/// Vive en un solo lugar porque el glifo, la tarjeta del ícono y el splash
/// tienen que verse siempre iguales.
enum AppBrand {
    static let accent = Color(red: 0.180, green: 0.357, blue: 1.0) // #2E5BFF
}

/// El glifo de marca: el sobre con la moneda del sol saliendo por la
/// esquina. Es el mismo dibujo que el ícono de la app (`Icono y Splash`,
/// handoff de identidad) — aquí se redibuja en SwiftUI para poder animarlo
/// en el splash sin depender de un asset rasterizado.
///
/// `detail` sigue la regla del handoff: a 40pt las dos barritas del recibo
/// no se ven (se pierden), así que sólo se dibujan cuando el glifo es lo
/// bastante grande para que se lean.
struct AppIconGlyph: View {

    var size: CGFloat
    var accent: Color = AppBrand.accent
    var coinFace: Color = .white
    var detail: Bool = true

    var body: some View {
        let scale = size / 100
        let strokeWidth = (detail ? 7 : 8) * scale
        let coinRadius = (detail ? 21 : 27) * scale
        let coinCenter = CGPoint(x: (detail ? 78 : 72) * scale, y: (detail ? 71 : 68) * scale)

        ZStack {
            // El sobre: un rectángulo redondeado con la solapa en "V".
            RoundedRectangle(cornerRadius: 13 * scale, style: .continuous)
                .stroke(Color.white, lineWidth: strokeWidth)
                .frame(width: 68 * scale, height: 52 * scale)
                .overlay(
                    Path { path in
                        path.move(to: CGPoint(x: 8 * scale, y: 9 * scale))
                        path.addLine(to: CGPoint(x: 34 * scale, y: 29 * scale))
                        path.addLine(to: CGPoint(x: 60 * scale, y: 9 * scale))
                    }
                    .stroke(Color.white, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))
                )
                .overlay(alignment: .topLeading) {
                    if detail {
                        HStack(spacing: 4 * scale) {
                            Capsule().fill(Color.white)
                                .frame(width: 17 * scale, height: 8 * scale)
                            Capsule().fill(Color.white.opacity(0.6))
                                .frame(width: 10 * scale, height: 8 * scale)
                        }
                        .offset(x: 10 * scale, y: 35 * scale)
                    }
                }
                .position(x: 50 * scale, y: 48 * scale)
                .frame(width: 100 * scale, height: 100 * scale)

            // La moneda: aro del color de marca con la cara blanca y "S/".
            ZStack {
                Circle().fill(accent).frame(width: coinRadius * 2, height: coinRadius * 2)
                Circle().fill(coinFace).frame(width: (coinRadius - 3.5 * scale) * 2, height: (coinRadius - 3.5 * scale) * 2)
                Text("S/")
                    .font(.system(size: (detail ? 23 : 31) * scale, weight: .heavy, design: .rounded))
                    .tracking(-0.5 * scale)
                    .foregroundStyle(accent)
            }
            .position(coinCenter)
            .frame(width: 100 * scale, height: 100 * scale)
        }
        .frame(width: size, height: size)
    }
}

/// La tarjeta redondeada de fondo del ícono, en el acabado "plano" del
/// handoff: color sólido, sin degradado ni bisel. Se usa para previsualizar
/// el ícono dentro de la propia app (p. ej. en Ajustes); el .png que ve el
/// sistema se generó aparte, sin este marco, porque iOS aplica su propia máscara.
struct AppIconTile: View {

    var size: CGFloat
    var accent: Color = AppBrand.accent
    var coinFace: Color = .white
    var detail: Bool = true

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
            .fill(accent)
            .frame(width: size, height: size)
            .overlay(AppIconGlyph(size: size * 0.58, accent: accent, coinFace: coinFace, detail: detail))
    }
}

/// Pantalla de bienvenida: la barra de reparto (el mismo lenguaje visual que
/// usa Categorías) se arma gota a gota, y luego entran el ícono y el nombre.
///
/// No es el launch screen del sistema — ese sigue siendo instantáneo y en
/// blanco, como lo pide Apple — sino lo que se ve encima mientras la app
/// termina de montar su primera pantalla real. Dura ~1.7s y sólo una vez
/// por lanzamiento.
struct SplashView: View {

    var onFinished: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var dropsStarted = false
    @State private var showIcon = false
    @State private var showWordmark = false

    private var palette: Palette { Palette(scheme) }

    /// Ancho final, arrastre horizontal de caída y color — un segmento por
    /// gota, con los mismos cinco colores del sistema que usa `Palette`
    /// para las categorías (naranja, azul, celeste, verde, índigo).
    private let drops: [DropSpec] = [
        DropSpec(width: 62.6, cx: 20.3,
                 light: Color(red: 1, green: 0.584, blue: 0), dark: Color(red: 1, green: 0.624, blue: 0.039),
                 delay: 0.04),
        DropSpec(width: 44.2, cx: 11.1,
                 light: Color(red: 0.039, green: 0.518, blue: 1), dark: Color(red: 0.251, green: 0.612, blue: 1),
                 delay: 0.15),
        DropSpec(width: 33.1, cx: 5.6,
                 light: Color(red: 0.188, green: 0.690, blue: 0.780), dark: Color(red: 0.353, green: 0.784, blue: 0.871),
                 delay: 0.255),
        DropSpec(width: 25.8, cx: 1.9,
                 light: Color(red: 0.204, green: 0.780, blue: 0.349), dark: Color(red: 0.188, green: 0.820, blue: 0.345),
                 delay: 0.345),
        DropSpec(width: 18.4, cx: -1.8,
                 light: AppBrand.accent, dark: Color(red: 0.463, green: 0.573, blue: 1),
                 delay: 0.425)
    ]

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()

            VStack(spacing: 30) {
                ZStack {
                    if showIcon {
                        // El glifo necesita su fondo azul detrás: sin la
                        // tarjeta, el sobre (blanco) desaparece sobre el
                        // fondo claro y la moneda queda flotando sola.
                        AppIconTile(size: 132,
                                    coinFace: scheme == .dark ? Color(red: 0.969, green: 0.969, blue: 0.976) : .white)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.74).combined(with: .opacity),
                                removal: .identity))
                    }
                }
                .frame(height: 132)

                HStack(spacing: 3) {
                    ForEach(drops.indices, id: \.self) { i in
                        DropSegment(spec: drops[i], scheme: scheme, start: dropsStarted)
                    }
                }
                .frame(height: 16)

                Text("AgruPay")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .tracking(-0.7)
                    .foregroundStyle(palette.label)
                    .opacity(showWordmark ? 1 : 0)
                    .offset(y: showWordmark ? 0 : 9)
            }
        }
        .onAppear { play() }
    }

    private func play() {
        dropsStarted = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.02) {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { showIcon = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.21) {
            withAnimation(.easeOut(duration: 0.38)) { showWordmark = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.75) {
            onFinished()
        }
    }
}

/// Ancho final, arrastre horizontal de caída y color de una gota de la barra.
private struct DropSpec {
    let width: CGFloat
    let cx: CGFloat
    let light: Color
    let dark: Color
    let delay: Double
}

/// Una gota de la barra de reparto: entra como un puntito arriba, cae
/// acelerando y estirándose, choca contra la base y se aplasta hasta
/// esparcirse en su tramo final — el mismo tramo que después queda fijo
/// como segmento de la barra.
private struct DropSegment: View {

    fileprivate enum Phase { case hidden, falling, landed }

    let spec: DropSpec
    let scheme: ColorScheme
    let start: Bool

    @State private var phase: Phase = .hidden

    private var color: Color { scheme == .dark ? spec.dark : spec.light }

    private var width: CGFloat {
        switch phase {
        case .hidden: return 20
        case .falling: return 14
        case .landed: return spec.width
        }
    }

    private var height: CGFloat {
        switch phase {
        case .hidden: return 20
        case .falling: return 34
        case .landed: return 16
        }
    }

    private var yOffset: CGFloat {
        switch phase {
        case .hidden: return -230
        case .falling: return -2
        case .landed: return 0
        }
    }

    private var xOffset: CGFloat { phase == .landed ? 0 : spec.cx }

    var body: some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: height)
            .offset(x: xOffset, y: yOffset)
            .opacity(phase == .hidden ? 0 : 1)
            .onChange(of: start) { _, newValue in
                guard newValue else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + spec.delay) {
                    withAnimation(.timingCurve(0.6, 0, 0.95, 0.5, duration: 0.30)) { phase = .falling }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.62)) { phase = .landed }
                    }
                }
            }
    }
}
