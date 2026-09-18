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

/// El splash (`5l`).
///
/// Sólo se ve cuando hay algo que esperar: si al abrir hay correos nuevos por
/// leer, muestra el progreso; si no, dura un fotograma y no se ve. Antes
/// reproducía una animación de 1.75 s en cada arranque — casi dos segundos
/// de espera cada vez que se abría la app para mirar una cifra.
struct SplashView: View {

    var onFinished: () -> Void

    @StateObject private var sync = GmailSyncService.shared
    @State private var isReading = false
    @State private var didFinish = false

    /// Tope de espera: una lectura larga sigue en segundo plano, y Hoy la
    /// muestra en su chip. El splash no puede secuestrar la app.
    private static let maxWait: Duration = .seconds(6)

    var body: some View {
        ZStack {
            AppBrand.accent.ignoresSafeArea()

            if isReading {
                VStack(spacing: 18) {
                    Spacer()

                    AppIconTile(size: 88, coinFace: .white)
                        .overlay(RoundedRectangle(cornerRadius: 88 * 0.225, style: .continuous)
                            .stroke(Color.white.opacity(0.9), lineWidth: 3))

                    Text("AgruPay")
                        .font(.system(size: 28, weight: .bold))
                        .tracking(-0.6)
                        .foregroundStyle(Color.white)

                    Spacer()

                    VStack(spacing: 10) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(Color.white)
                            .frame(width: 140)
                        Text("Leyendo tus correos nuevos…")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    .padding(.bottom, 60)
                }
                .transition(.opacity)
            }
        }
        .task { await run() }
        .onChange(of: sync.isSyncing) { _, syncing in
            if !syncing && isReading { finish() }
        }
    }

    private var progress: Double {
        guard sync.totalEmailsToProcess > 0 else { return 0.1 }
        return min(1, Double(sync.emailsProcessed) / Double(sync.totalEmailsToProcess))
    }

    private func run() async {
        // Un respiro para que la lectura del arranque, si la hay, se anuncie.
        try? await Task.sleep(for: .milliseconds(120))
        guard sync.isSyncing else {
            finish()
            return
        }
        withAnimation(.easeOut(duration: 0.2)) { isReading = true }
        try? await Task.sleep(for: Self.maxWait)
        finish()
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        onFinished()
    }
}
