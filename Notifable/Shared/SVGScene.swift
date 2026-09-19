import SwiftUI

/// Un SVG del kit de animales (`output/animales`), leído una vez y dibujado
/// en un `Canvas` con los colores de cada quien.
///
/// No es un lector de SVG general: entiende justo lo que usa el kit —
/// `path` (M/L/C/Z absolutos), `circle`, `ellipse`, `rect`, `polygon`,
/// `polyline`, `use`, `g`, `clipPath` y `rotate()` — y las clases de su
/// `<style>`, que traducen `--pelo`, `--pico`, `--acento`, `--objeto` y
/// `--objeto2` a colores. Como en CSS, una clase manda sobre el atributo:
/// `class="linea" stroke-width="5"` se dibuja con 8, igual que en el navegador.
struct SVGScene {

    indirect enum Node {
        case group(id: String?, children: [Node], clip: Path?)
        case shape(Path, Style)
    }

    /// Un color del kit: fijo, o una variable (mezclada con blanco o negro,
    /// como hacía `color-mix` en el SVG).
    enum Paint: Equatable {
        case none
        case rgb(RGBColor)
        case variable(String, mix: RGBColor? = nil, amount: Double = 1)

        func resolve(_ colors: [String: RGBColor]) -> RGBColor? {
            switch self {
            case .none: return nil
            case .rgb(let color): return color
            case .variable(let name, let mix, let amount):
                let base = colors[name] ?? .black
                guard let mix else { return base }
                return base.mixed(with: mix, amount: amount)
            }
        }
    }

    struct Style {
        var fill: Paint = .rgb(.black)
        var stroke: Paint = .none
        var strokeWidth: CGFloat = 1
        var lineCap: CGLineCap = .butt
        var lineJoin: CGLineJoin = .miter
        var dash: [CGFloat] = []
        var fillOpacity: Double = 1
        var strokeOpacity: Double = 1
        /// No se hereda: vale para el elemento que la declara.
        var opacity: Double = 1
    }

    let nodes: [Node]

    /// Si el grupo `ojos` trae aro blanco (panda, mapache): con la cara de
    /// ánimo hay que conservarlo o la X se pierde sobre la mancha oscura.
    let eyeRing: CGFloat?

    init?(svg: String) {
        guard let root = XMLTree.parse(svg) else { return nil }
        var index: [String: XMLTree] = [:]
        var clips: [String: XMLTree] = [:]
        root.visit { element in
            guard let id = element.attributes["id"] else { return }
            index[id] = element
            if element.name == "clipPath" { clips[id] = element }
        }
        let builder = Builder(index: index, clips: clips)
        nodes = builder.children(of: root, style: Style(), transform: .identity)

        let eyes = index["ojos"]?.children ?? []
        eyeRing = eyes
            .filter { $0.name == "circle" && $0.attributes["fill"]?.lowercased() == "#fff" }
            .compactMap { Double($0.attributes["r"] ?? "") }
            .filter { $0 > 24 }
            .max()
            .map { CGFloat($0) }
    }

    // MARK: - Dibujo

    func draw(in context: GraphicsContext, colors: [String: RGBColor], skipping: Set<String> = []) {
        Self.draw(nodes, in: context, colors: colors, skipping: skipping)
    }

    private static func draw(_ nodes: [Node], in context: GraphicsContext,
                             colors: [String: RGBColor], skipping: Set<String>) {
        for node in nodes {
            switch node {
            case let .group(id, children, clip):
                if let id, skipping.contains(id) { continue }
                if let clip {
                    context.drawLayer { layer in
                        layer.clip(to: clip)
                        draw(children, in: layer, colors: colors, skipping: skipping)
                    }
                } else {
                    draw(children, in: context, colors: colors, skipping: skipping)
                }
            case let .shape(path, style):
                if let fill = style.fill.resolve(colors) {
                    context.fill(path, with: .color(fill.color.opacity(style.fillOpacity * style.opacity)))
                }
                if let stroke = style.stroke.resolve(colors) {
                    context.stroke(path, with: .color(stroke.color.opacity(style.strokeOpacity * style.opacity)),
                                   style: StrokeStyle(lineWidth: style.strokeWidth, lineCap: style.lineCap,
                                                      lineJoin: style.lineJoin, dash: style.dash))
                }
            }
        }
    }

    /// Toda la figura en un solo tono (`shading`), para la pantalla bloqueada.
    /// Con `outlineOnly` se trazan sólo los bordes: sirve para recortar la
    /// nariz dentro de la silueta sin borrarla entera.
    func drawSilhouette(in context: GraphicsContext, shading: GraphicsContext.Shading,
                        only groupID: String? = nil, outlineOnly: Bool = false) {
        Self.silhouette(nodes, in: context, shading: shading, only: groupID,
                        inside: groupID == nil, outlineOnly: outlineOnly)
    }

    private static func silhouette(_ nodes: [Node], in context: GraphicsContext,
                                   shading: GraphicsContext.Shading, only groupID: String?,
                                   inside: Bool, outlineOnly: Bool) {
        for node in nodes {
            switch node {
            case let .group(id, children, clip):
                let entered = inside || (id != nil && id == groupID)
                if let clip {
                    context.drawLayer { layer in
                        layer.clip(to: clip)
                        silhouette(children, in: layer, shading: shading, only: groupID,
                                   inside: entered, outlineOnly: outlineOnly)
                    }
                } else {
                    silhouette(children, in: context, shading: shading, only: groupID,
                               inside: entered, outlineOnly: outlineOnly)
                }
            case let .shape(path, style):
                guard inside, style.opacity > 0.3 else { continue }
                if style.fill != .none && !outlineOnly { context.fill(path, with: shading) }
                if style.stroke != .none || outlineOnly {
                    context.stroke(path, with: shading,
                                   style: StrokeStyle(lineWidth: outlineOnly ? 5 : style.strokeWidth,
                                                      lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    // MARK: - Clases del kit

    /// Lo mismo que los `<style>` de `generar.py` (`ESTILO` y `ESTILO_OBJ`).
    private static let navy = RGBColor(hex: "#1e1a6b")

    private static func applyClass(_ name: String, to style: inout Style) {
        func round() { style.lineCap = .round; style.lineJoin = .round }
        switch name {
        case "pelo": style.fill = .variable("pelo")
        case "pelo-trazo": style.stroke = .variable("pelo"); style.fill = .none; round()
        case "pelo-claro": style.fill = .variable("pelo", mix: .white, amount: 0.65)
        case "pelo-oscuro": style.fill = .variable("pelo", mix: .black, amount: 0.80)
        case "pico": style.fill = .variable("pico")
        case "pico-oscuro": style.fill = .variable("pico", mix: .black, amount: 0.78)
        case "acento": style.fill = .variable("acento")
        case "acento-trazo": style.stroke = .variable("acento"); style.fill = .none; style.lineJoin = .round
        case "acento-suave": style.fill = .variable("acento", mix: .white, amount: 0.40)
        case "objeto": style.fill = .variable("objeto")
        case "objeto-claro": style.fill = .variable("objeto", mix: .white, amount: 0.60)
        case "objeto-oscuro": style.fill = .variable("objeto", mix: .black, amount: 0.75)
        case "objeto-trazo": style.stroke = .variable("objeto"); style.fill = .none; round()
        case "objeto-2": style.fill = .variable("objeto2")
        case "objeto-2-oscuro": style.fill = .variable("objeto2", mix: .black, amount: 0.70)
        case "objeto2-trazo": style.stroke = .variable("objeto2"); style.fill = .none; round()
        case "linea": style.stroke = .rgb(navy); style.strokeWidth = 8; round()
        case "trazo": style.stroke = .rgb(navy); style.fill = .none; round()
        default: break
        }
    }

    // MARK: - Construcción

    private struct Builder {
        let index: [String: XMLTree]
        let clips: [String: XMLTree]

        func children(of element: XMLTree, style: Style, transform: CGAffineTransform) -> [Node] {
            element.children.compactMap { node(for: $0, inherited: style, transform: transform) }
        }

        func node(for element: XMLTree, inherited: Style, transform parent: CGAffineTransform) -> Node? {
            switch element.name {
            case "defs", "clipPath", "style": return nil
            default: break
            }
            let transform = SVGScene.transform(element.attributes["transform"]).concatenating(parent)
            let style = resolvedStyle(element, inherited: inherited)

            if element.name == "g" || element.name == "svg" {
                var clip: Path?
                if let ref = SVGScene.reference(element.attributes["clip-path"]), let clipElement = clips[ref] {
                    clip = clipElement.children.reduce(into: Path()) { path, child in
                        if let geometry = geometry(of: child, transform: transform) { path.addPath(geometry) }
                    }
                }
                return .group(id: element.attributes["id"],
                              children: children(of: element, style: style, transform: transform),
                              clip: clip)
            }

            if element.name == "use" {
                guard let ref = SVGScene.reference(element.attributes["href"] ?? element.attributes["xlink:href"]),
                      let target = index[ref],
                      let geometry = geometry(of: target, transform: transform) else { return nil }
                return .shape(geometry, resolvedStyle(target, inherited: style))
            }

            // `geometry(of:)` ya suma la transformación propia del elemento.
            guard let geometry = geometry(of: element, transform: parent) else { return nil }
            return .shape(geometry, style)
        }

        /// Hereda del padre; encima, los atributos; encima, las clases.
        func resolvedStyle(_ element: XMLTree, inherited: Style) -> Style {
            var style = inherited
            style.opacity = 1
            let a = element.attributes
            if let fill = a["fill"] { style.fill = SVGScene.paint(fill) }
            if let stroke = a["stroke"] { style.stroke = SVGScene.paint(stroke) }
            if let width = a["stroke-width"].flatMap(Double.init) { style.strokeWidth = width }
            if let cap = a["stroke-linecap"] { style.lineCap = cap == "round" ? .round : cap == "square" ? .square : .butt }
            if let join = a["stroke-linejoin"] { style.lineJoin = join == "round" ? .round : join == "bevel" ? .bevel : .miter }
            if let dash = a["stroke-dasharray"] { style.dash = SVGScene.numbers(dash) }
            if let value = a["fill-opacity"].flatMap(Double.init) { style.fillOpacity = value }
            if let value = a["stroke-opacity"].flatMap(Double.init) { style.strokeOpacity = value }
            if let value = a["opacity"].flatMap(Double.init) { style.opacity = value }
            for name in (a["class"] ?? "").split(separator: " ") {
                SVGScene.applyClass(String(name), to: &style)
            }
            return style
        }

        func geometry(of element: XMLTree, transform parent: CGAffineTransform) -> Path? {
            let a = element.attributes
            func number(_ key: String) -> CGFloat { CGFloat(Double(a[key] ?? "") ?? 0) }
            let transform = SVGScene.transform(a["transform"]).concatenating(parent)
            let path: Path
            switch element.name {
            case "path":
                path = SVGPath.parse(a["d"] ?? "")
            case "circle":
                let r = number("r")
                path = Path(ellipseIn: CGRect(x: number("cx") - r, y: number("cy") - r, width: r * 2, height: r * 2))
            case "ellipse":
                let rx = number("rx"), ry = number("ry")
                path = Path(ellipseIn: CGRect(x: number("cx") - rx, y: number("cy") - ry, width: rx * 2, height: ry * 2))
            case "rect":
                let rect = CGRect(x: number("x"), y: number("y"), width: number("width"), height: number("height"))
                let rx = number("rx")
                path = rx > 0 ? Path(roundedRect: rect, cornerRadius: rx) : Path(rect)
            case "polygon", "polyline":
                let values = SVGScene.numbers(a["points"] ?? "")
                var poly = Path()
                stride(from: 0, to: values.count - 1, by: 2).forEach { i in
                    let point = CGPoint(x: values[i], y: values[i + 1])
                    if i == 0 { poly.move(to: point) } else { poly.addLine(to: point) }
                }
                if element.name == "polygon" { poly.closeSubpath() }
                path = poly
            default:
                return nil
            }
            return transform.isIdentity ? path : path.applying(transform)
        }
    }

    // MARK: - Atributos

    private static func paint(_ value: String) -> Paint {
        let value = value.trimmingCharacters(in: .whitespaces)
        if value == "none" { return .none }
        if value.hasPrefix("#") {
            // `#fff` → `#ffffff`
            let hex = value.dropFirst()
            return .rgb(RGBColor(hex: hex.count == 3 ? hex.map { "\($0)\($0)" }.joined() : String(hex)))
        }
        if value == "white" { return .rgb(.white) }
        return .rgb(.black)
    }

    private static func numbers(_ text: String) -> [CGFloat] {
        text.split(whereSeparator: { $0 == " " || $0 == "," })
            .compactMap { Double($0) }
            .map { CGFloat($0) }
    }

    /// `url(#id)` o `#id` → `id`.
    private static func reference(_ value: String?) -> String? {
        guard var value else { return nil }
        if value.hasPrefix("url(") { value = String(value.dropFirst(4).dropLast()) }
        return value.hasPrefix("#") ? String(value.dropFirst()) : nil
    }

    /// `rotate(a cx cy)`, `translate(x y)` y `scale(s)`, en ese orden de escritura.
    private static func transform(_ value: String?) -> CGAffineTransform {
        guard let value else { return .identity }
        var result = CGAffineTransform.identity
        let pattern = /(\w+)\(([^)]*)\)/
        for match in value.matches(of: pattern) {
            let args = numbers(String(match.output.2))
            var step = CGAffineTransform.identity
            switch match.output.1 {
            case "rotate" where !args.isEmpty:
                let angle = args[0] * .pi / 180
                let (cx, cy) = args.count >= 3 ? (args[1], args[2]) : (0, 0)
                step = CGAffineTransform(translationX: cx, y: cy).rotated(by: angle).translatedBy(x: -cx, y: -cy)
            case "translate" where !args.isEmpty:
                step = CGAffineTransform(translationX: args[0], y: args.count > 1 ? args[1] : 0)
            case "scale" where !args.isEmpty:
                step = CGAffineTransform(scaleX: args[0], y: args.count > 1 ? args[1] : args[0])
            default:
                break
            }
            // En SVG la primera transformación escrita es la más externa.
            result = step.concatenating(result)
        }
        return result
    }
}

// MARK: - XML

/// El árbol del SVG tal cual, antes de interpretarlo: el `clip-path` y el
/// `use` pueden apuntar a elementos que aparecen más adelante.
private final class XMLTree {
    let name: String
    let attributes: [String: String]
    var children: [XMLTree] = []

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    func visit(_ body: (XMLTree) -> Void) {
        body(self)
        children.forEach { $0.visit(body) }
    }

    static func parse(_ text: String) -> XMLTree? {
        guard let data = text.data(using: .utf8) else { return nil }
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        return delegate.root
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var root: XMLTree?
        var stack: [XMLTree] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let element = XMLTree(name: elementName, attributes: attributeDict)
            if let parent = stack.last { parent.children.append(element) } else { root = element }
            stack.append(element)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            stack.removeLast()
        }
    }
}
