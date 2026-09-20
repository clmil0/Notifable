"""Embebe los SVG de animales y objetos en `Shared/AvatarArtwork.swift`.

La app los dibuja con `SVGScene` (Canvas), no como imágenes: así se recolorean
y se ven nítidos a cualquier tamaño, también en los widgets. Se embeben como
texto para no depender de recursos del bundle en dos targets.

Uso:  python3 generar.py && python3 a_swift.py
"""
import json
import os
import re

AQUI = os.path.dirname(os.path.abspath(__file__))
DESTINO = os.path.join(AQUI, "..", "..", "Notifable", "Shared", "AvatarArtwork.swift")


def limpio(ruta):
    with open(os.path.join(AQUI, ruta)) as f:
        svg = f.read()
    # Las clases se resuelven en Swift (`SVGScene.classStyles`): el <style> sobra.
    svg = re.sub(r"<style>.*?</style>", "", svg, flags=re.S)
    return re.sub(r"\n\s*\n", "\n", svg).strip()


def literal(texto):
    # `fill="#fff"` ya lleva `"#`: el delimitador necesita dos almohadillas.
    assert '"##' not in texto
    return '##"""\n' + texto + '\n"""##'


def main():
    with open(os.path.join(AQUI, "objetos.json")) as f:
        datos = json.load(f)

    entradas = []
    for a in datos["animales"]:
        entradas.append((a["id"], limpio(a["archivo"])))
    for o in datos["objetos"]:
        for capa in o["capas"]:
            clave = os.path.splitext(os.path.basename(capa["archivo"]))[0]
            entradas.append((clave, limpio(capa["archivo"])))

    animales = ",\n".join(
        f'        .init(id: "{a["id"]}", name: "{a["nombre"]}", fur: "{a["colores"]["--pelo"]}", '
        f'nose: "{a["colores"]["--pico"]}", mark: "{a["colores"]["--acento"]}")'
        for a in datos["animales"])

    def capas(o):
        return ", ".join(
            f'.init(svg: "{os.path.splitext(os.path.basename(c["archivo"]))[0]}", z: {c["z"]})'
            for c in o["capas"])

    objetos = ",\n".join(
        f'        .init(id: "{o["id"]}", name: "{o["nombre"]}", zone: .{o["categoria"]}, '
        f'color: "{o["colores"]["--objeto"]}", color2: "{o["colores"]["--objeto2"]}", '
        f'layers: [{capas(o)}])'
        for o in datos["objetos"])

    cuerpo = ",\n".join(f'        "{k}": {literal(v)}' for k, v in entradas)
    swift = f"""// Generado por output/animales/a_swift.py — no editar a mano.
// Animales: clave = id. Objetos: clave = nombre de archivo sin extensión.

enum AvatarArtwork {{
    static let animals: [AvatarAnimal] = [
{animales}
    ]

    static let items: [AvatarItem] = [
{objetos}
    ]

    static let svg: [String: String] = [
{cuerpo}
    ]
}}
"""
    with open(DESTINO, "w") as f:
        f.write(swift)
    print(f"{len(entradas)} SVG -> {os.path.relpath(DESTINO, AQUI)}")


if __name__ == "__main__":
    main()
