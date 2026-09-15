import SwiftUI

// MARK: - Cabeceras

/// Las ocho cabeceras con textura de "Tu perfil". Los cuatro primeros índices
/// conservan el color de los degradados lisos que había antes (azul, violeta,
/// verde, naranja), para que quien ya había elegido uno no vea otro color.
enum SocialBanner: Int, CaseIterable {
    case blue, violet, stripes, arcs, dots, grid, waves, confetti

    var name: String {
        switch self {
        case .blue: return "Degradado azul"
        case .violet: return "Degradado violeta"
        case .stripes: return "Rayas"
        case .arcs: return "Arcos"
        case .dots: return "Puntos"
        case .grid: return "Cuadrícula"
        case .waves: return "Olas"
        case .confetti: return "Confeti"
        }
    }

    static func at(_ index: Int?) -> SocialBanner {
        SocialBanner(rawValue: (index ?? 0) % allCases.count) ?? .blue
    }

    var colors: [Color] {
        func c(_ hex: String) -> Color { RGBColor(hex: hex).color }
        switch self {
        case .blue, .dots: return [c("#0A84FF"), c("#32ADE6")]
        case .violet: return [c("#5E5CE6"), c("#AF52DE")]
        case .stripes: return [c("#34C759"), c("#1D7F3C")]
        case .arcs: return [c("#FF9500"), c("#B36A00")]
        case .grid: return [c("#1C1C1E"), c("#48484A")]
        case .waves: return [c("#30B0C7"), c("#0A84FF")]
        case .confetti: return [c("#FF2D55"), c("#FF9500")]
        }
    }
}

struct SocialBannerView: View {
    let banner: SocialBanner

    init(_ banner: SocialBanner) { self.banner = banner }
    init(index: Int?) { self.banner = .at(index) }

    var body: some View {
        LinearGradient(colors: banner.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                Canvas { context, size in drawTexture(in: &context, size: size) }
                    .allowsHitTesting(false)
            }
            .clipped()
    }

    private func drawTexture(in context: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        switch banner {
        case .blue, .violet:
            break
        case .dots:
            var path = Path()
            for x in stride(from: 2.0, to: w, by: 13) {
                for y in stride(from: 2.0, to: h, by: 13) {
                    path.addEllipse(in: CGRect(x: x - 1.6, y: y - 1.6, width: 3.2, height: 3.2))
                }
            }
            context.fill(path, with: .color(.white.opacity(0.30)))
        case .stripes:
            // Franjas de 7 pt cada 15 pt a 45°.
            var path = Path()
            let step = 15.0 * 2.squareRoot()
            for offset in stride(from: -h, to: w + h, by: step) {
                let band = 7.0 * 2.squareRoot()
                path.move(to: CGPoint(x: offset, y: 0))
                path.addLine(to: CGPoint(x: offset + band, y: 0))
                path.addLine(to: CGPoint(x: offset + band + h, y: h))
                path.addLine(to: CGPoint(x: offset + h, y: h))
                path.closeSubpath()
            }
            context.fill(path, with: .color(.white.opacity(0.18)))
        case .arcs:
            let center = CGPoint(x: w * 0.08, y: h * 1.3)
            let far = hypot(w - center.x, center.y)
            var path = Path()
            for radius in stride(from: 16.0, to: far, by: 16) {
                path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            }
            context.stroke(path, with: .color(.white.opacity(0.22)), lineWidth: 1.5)
        case .grid:
            var path = Path()
            for x in stride(from: 0.0, to: w, by: 11) {
                path.move(to: CGPoint(x: x + 0.5, y: 0)); path.addLine(to: CGPoint(x: x + 0.5, y: h))
            }
            for y in stride(from: 0.0, to: h, by: 11) {
                path.move(to: CGPoint(x: 0, y: y + 0.5)); path.addLine(to: CGPoint(x: w, y: y + 0.5))
            }
            context.stroke(path, with: .color(.white.opacity(0.14)), lineWidth: 1)
        case .waves:
            for (cx, cy, share, opacity) in [(0.5, 1.3, 0.22, 0.28), (0.12, 1.5, 0.26, 0.20)] {
                let center = CGPoint(x: w * cx, y: h * cy)
                let far = max(hypot(center.x, center.y), hypot(w - center.x, center.y))
                let radius = far * share
                context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                     width: radius * 2, height: radius * 2)),
                             with: .color(.white.opacity(opacity)))
            }
        case .confetti:
            for x in stride(from: 0.0, to: w, by: 44) {
                for y in stride(from: 0.0, to: h, by: 44) {
                    context.fill(Path(ellipseIn: CGRect(x: x + 8.8 - 3, y: y + 13.2 - 3, width: 6, height: 6)),
                                 with: .color(.white.opacity(0.35)))
                    context.fill(Path(ellipseIn: CGRect(x: x + 30.8 - 4, y: y + 30.8 - 4, width: 8, height: 8)),
                                 with: .color(.white.opacity(0.25)))
                }
            }
        }
    }
}
