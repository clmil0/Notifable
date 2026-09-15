import SwiftUI

/// Dibuja un `PenguinLook` con los mismos trazos del kit en SVG
/// (`output/pinguinos`). Vectorial: se ve nítido de 38 a 120 pt sin assets.
struct PenguinView: View {
    let look: PenguinLook

    /// El `viewBox` del SVG original.
    static let viewBox = CGRect(x: 140, y: 170, width: 470, height: 460)

    var body: some View {
        Canvas { context, size in
            let box = Self.viewBox
            let scale = min(size.width / box.width, size.height / box.height)
            context.translateBy(x: (size.width - box.width * scale) / 2, y: (size.height - box.height * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -box.minX, y: -box.minY)
            PenguinDrawing(look: look).draw(in: &context)
        }
        .aspectRatio(Self.viewBox.width / Self.viewBox.height, contentMode: .fit)
        .accessibilityLabel("Pingüino \(look.breedStyle.name)")
    }
}

/// El pingüino dentro de un círculo, con el cuerpo cortado abajo como en la
/// tarjeta de Amigos: la cabeza asoma entera y el círculo recorta la panza.
struct PenguinAvatar: View {
    let look: PenguinLook
    let size: CGFloat
    var background: Color

    var body: some View {
        ZStack(alignment: .bottom) {
            Circle().fill(background)
            PenguinView(look: look)
                .frame(width: size * 1.15, height: size * 1.13)
                .offset(y: size * 0.02)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

// MARK: - Dibujo

private struct PenguinDrawing {
    let look: PenguinLook

    private static let navy = RGBColor(hex: "#1e1a6b").color
    private static let round = StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)

    private enum P {
        static let body = SVGPath.parse("M215 560 C205 470 200 390 222 320 C245 250 310 228 370 228 C440 228 500 250 515 320 C530 390 525 470 520 560 C520 600 460 616 370 616 C280 616 215 600 215 560 Z")
        static let faceHigh = SVGPath.parse("M370 302 C350 270 298 262 264 290 C236 316 232 380 236 450 C240 520 242 580 246 630 L496 630 C498 580 500 520 502 450 C504 380 500 316 476 290 C442 262 390 270 370 302 Z")
        static let faceLow = SVGPath.parse("M240 480 C262 436 320 420 370 420 C420 420 478 436 500 480 C502 540 500 590 496 630 L246 630 C242 590 238 540 240 480 Z")
        static let tuftLeaf = SVGPath.parse("M386 238 C368 228 352 212 362 202 C372 193 390 206 398 220 C406 204 426 196 436 206 C444 218 428 232 410 238 Z")
        static let tuftSpikes = SVGPath.parse("M356 240 L346 196 L372 222 L382 182 L398 220 L424 190 L416 240 Z")
        static let wingLeft = SVGPath.parse("M248 445 C212 428 172 385 166 342 C162 318 180 310 202 322 C238 342 258 372 264 402 Z")
        static let wingLeftShine = SVGPath.parse("M200 332 C222 350 240 380 246 420 C226 400 204 370 196 340 C195 333 197 330 200 332 Z")
        static let wingRight = SVGPath.parse("M502 448 C540 468 576 508 586 544 C591 566 576 574 554 563 C530 550 512 532 500 522 Z")
        static let wingRightShine = SVGPath.parse("M520 480 C545 500 566 526 574 550 C556 540 536 520 522 500 Z")
        static let headShine = SVGPath.parse("M268 272 C310 246 432 240 488 272 C440 260 320 260 268 272 Z")
        static let emperorWash = SVGPath.parse("M262 452 C300 428 440 428 478 452 C440 440 300 440 262 452 Z")
        static let emperorPatches = SVGPath.parse("M226 360 C250 370 268 410 262 452 C250 440 236 420 228 400 Z M514 360 C490 370 472 410 478 452 C490 440 504 420 512 400 Z")
        static let chinstrap = SVGPath.parse("M250 392 C298 452 452 456 500 394")
        static let gentoo = SVGPath.parse("M282 322 C290 300 322 294 344 310 C328 314 312 318 294 328 Z M476 322 C468 300 436 294 414 310 C430 314 446 318 464 328 Z")
        static let magellanicWide = SVGPath.parse("M232 500 C290 566 450 566 508 500")
        static let magellanicThin = SVGPath.parse("M236 548 C290 600 450 600 504 548")
        static let crests = SVGPath.parse("M336 326 C308 314 268 300 214 286 C238 300 236 302 206 310 C236 314 240 318 214 334 C258 326 290 330 334 338 Z M422 326 C450 314 490 300 544 286 C520 300 522 302 552 310 C522 314 518 318 544 334 C500 326 468 330 424 338 Z")
        static let beak = SVGPath.parse("M346 374 C348 360 408 358 412 374 C414 394 396 408 379 408 C361 408 344 394 346 374 Z")
        static let beakShade = SVGPath.parse("M352 390 C362 402 396 402 406 390 C400 402 390 405 379 405 C366 405 356 400 352 390 Z")
        static let mouth = SVGPath.parse("M368 386 C374 380 386 380 392 386 C388 395 372 395 368 386 Z")
        static let scarfBand = SVGPath.parse("M244 470 C290 520 470 520 512 470 C508 512 250 512 244 470 Z")
        static let scarfTail = SVGPath.parse("M470 500 C500 516 512 566 496 592 C468 580 452 536 452 506 Z")
        static let hatDome = SVGPath.parse("M246 288 C258 210 490 210 500 288 C430 258 318 258 246 288 Z")
        static let hatBrim = SVGPath.parse("M236 288 C300 258 450 258 510 288 C510 306 236 306 236 288 Z")
        static let glassesBridge = SVGPath.parse("M358 353 L400 354 M278 348 L242 336 M480 351 L516 340")
    }

    private static let eyes = [CGPoint(x: 318, y: 352), CGPoint(x: 440, y: 355)]

    private func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    private func scaled(_ context: GraphicsContext, around point: CGPoint, by factor: CGFloat) -> GraphicsContext {
        var copy = context
        copy.translateBy(x: point.x, y: point.y)
        copy.scaleBy(x: factor, y: factor)
        copy.translateBy(x: -point.x, y: -point.y)
        return copy
    }

    func draw(in context: inout GraphicsContext) {
        let breed = look.breedStyle
        let young = look.age == 0
        let coatRGB = RGBColor(hex: look.coatHex)
        let beakRGB = RGBColor(hex: look.beakHex)
        let accentRGB = RGBColor(hex: look.accentHex)
        let coat = coatRGB.color
        let coatLight = coatRGB.mixed(with: .white, amount: 0.65).color
        let accent = accentRGB.color
        let navy = Self.navy

        // Un joven es un poco más bajo; sus ojos, más grandes.
        let body = scaled(context, around: CGPoint(x: 379, y: 430), by: young ? 0.94 : 1.03)

        let ctx = body
        ctx.fill(breed.tuft == .leaf ? P.tuftLeaf : P.tuftSpikes, with: .color(coat))
        ctx.stroke(breed.tuft == .leaf ? P.tuftLeaf : P.tuftSpikes, with: .color(navy), style: Self.round)

        for (wing, shine) in [(P.wingLeft, P.wingLeftShine), (P.wingRight, P.wingRightShine)] {
            ctx.fill(wing, with: .color(coat))
            ctx.stroke(wing, with: .color(navy), style: Self.round)
            ctx.fill(shine, with: .color(coatLight))
        }

        ctx.fill(P.body, with: .color(coat))
        ctx.drawLayer { inner in
            inner.clip(to: P.body)
            inner.fill(P.headShine, with: .color(coatLight))
            inner.fill(breed.face == .high ? P.faceHigh : P.faceLow, with: .color(.white))
            switch breed.extra {
            case .emperor:
                inner.fill(P.emperorWash, with: .color(accentRGB.mixed(with: .white, amount: 0.4).color))
                inner.fill(P.emperorPatches, with: .color(accent))
            case .chinstrap:
                inner.stroke(P.chinstrap, with: .color(coat), style: StrokeStyle(lineWidth: 7, lineCap: .round))
            case .gentoo:
                inner.fill(P.gentoo, with: .color(.white))
            case .magellanic:
                inner.stroke(P.magellanicWide, with: .color(coat), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                inner.stroke(P.magellanicThin, with: .color(coat), style: StrokeStyle(lineWidth: 8, lineCap: .round))
            case .none, .rockhopper:
                break
            }
            inner.fill(Path(ellipseIn: CGRect(x: 200, y: 588, width: 340, height: 60)),
                       with: .color(RGBColor(hex: "#e2e2ee").color))
        }
        ctx.stroke(P.body, with: .color(navy), style: Self.round)

        let eyeCtx = scaled(body, around: CGPoint(x: 379, y: 353), by: young ? 1.16 : 0.94)
        for eye in Self.eyes {
            switch breed.eyes {
            case .ring27: eyeCtx.fill(circle(eye, 27), with: .color(.white))
            case .ring34: eyeCtx.fill(circle(eye, 34), with: .color(.white))
            default: break
            }
            if breed.eyes == .iris {
                eyeCtx.fill(circle(eye, 24), with: .color(RGBColor(hex: "#d62839").color))
                eyeCtx.stroke(circle(eye, 24), with: .color(navy), lineWidth: 3)
                eyeCtx.fill(circle(CGPoint(x: eye.x + 1, y: eye.y + 2), 13), with: .color(navy))
            } else {
                eyeCtx.fill(circle(eye, 24), with: .color(navy))
            }
            eyeCtx.fill(circle(CGPoint(x: eye.x - 9, y: eye.y - 9), 8), with: .color(.white))
            eyeCtx.fill(circle(CGPoint(x: eye.x + 9, y: eye.y + 10), 3.5), with: .color(.white))
        }

        if breed.extra == .rockhopper {
            ctx.fill(P.crests, with: .color(accent))
            ctx.stroke(P.crests, with: .color(navy), style: StrokeStyle(lineWidth: 4, lineJoin: .round))
        }

        let beakCtx = scaled(body, around: CGPoint(x: 379, y: 384), by: young ? 0.9 : 1.04)
        beakCtx.fill(P.beak, with: .color(beakRGB.color))
        beakCtx.stroke(P.beak, with: .color(navy), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        beakCtx.fill(P.beakShade, with: .color(beakRGB.mixed(with: .black, amount: 0.78).color))
        beakCtx.fill(P.mouth, with: .color(RGBColor(hex: "#f06a7a").color))
        beakCtx.stroke(P.mouth, with: .color(navy), style: StrokeStyle(lineWidth: 3, lineJoin: .round))

        let accessoryStroke = StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
        switch look.accessoryStyle {
        case .none:
            break
        case .glasses:
            var frames = P.glassesBridge
            for eye in Self.eyes { frames.addPath(circle(eye, 40)) }
            ctx.stroke(frames, with: .color(navy), style: StrokeStyle(lineWidth: 7, lineCap: .round))
        case .scarf:
            let red = RGBColor(hex: "#e8455f").color
            for piece in [P.scarfBand, P.scarfTail] {
                ctx.fill(piece, with: .color(red))
                ctx.stroke(piece, with: .color(navy), style: accessoryStroke)
            }
        case .hat:
            let blue = RGBColor(hex: "#3d6be5").color
            for piece in [P.hatDome, P.hatBrim] {
                ctx.fill(piece, with: .color(blue))
                ctx.stroke(piece, with: .color(navy), style: accessoryStroke)
            }
            let pompom = circle(CGPoint(x: 373, y: 196), 20)
            ctx.fill(pompom, with: .color(RGBColor(hex: "#fcfcfe").color))
            ctx.stroke(pompom, with: .color(navy), style: accessoryStroke)
        }
    }
}

/// Lector mínimo de `d` de SVG: sólo `M`, `L`, `C` y `Z` absolutos, que es
/// todo lo que usa el kit de pingüinos.
enum SVGPath {
    static func parse(_ d: String) -> Path {
        var path = Path()
        var numbers: [CGFloat] = []
        var command: Character = "M"

        func flush() {
            switch command {
            case "M":
                var i = 0
                while i + 1 < numbers.count {
                    let point = CGPoint(x: numbers[i], y: numbers[i + 1])
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    i += 2
                }
            case "L":
                var i = 0
                while i + 1 < numbers.count {
                    path.addLine(to: CGPoint(x: numbers[i], y: numbers[i + 1])); i += 2
                }
            case "C":
                var i = 0
                while i + 5 < numbers.count {
                    path.addCurve(to: CGPoint(x: numbers[i + 4], y: numbers[i + 5]),
                                  control1: CGPoint(x: numbers[i], y: numbers[i + 1]),
                                  control2: CGPoint(x: numbers[i + 2], y: numbers[i + 3]))
                    i += 6
                }
            case "Z":
                path.closeSubpath()
            default:
                break
            }
            numbers.removeAll()
        }

        var token = ""
        func endToken() {
            if let value = Double(token) { numbers.append(CGFloat(value)) }
            token = ""
        }

        for char in d {
            if char.isLetter {
                endToken()
                flush()
                command = char
                if char == "Z" || char == "z" { flush(); command = " " }
            } else if char == " " || char == "," {
                endToken()
            } else if char == "-" && !token.isEmpty {
                endToken(); token = "-"
            } else {
                token.append(char)
            }
        }
        endToken()
        flush()
        return path
    }
}
