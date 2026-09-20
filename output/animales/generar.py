"""Genera animales y objetos en el mismo estilo que los pingüinos.

Animales  -> animales/<id>.svg   colores editables: --pelo, --pico (nariz), --acento
Objetos   -> objetos/objeto-<id>.svg (+ objeto-<id>-detras.svg)   colores: --objeto, --objeto2
Todos comparten viewBox "140 170 470 460" y la misma silueta de cuerpo que los pingüinos,
así que cualquier objeto encaja en cualquier animal (y en cualquier pingüino).
Orden de capas: objetos 'detras'  ->  animal  ->  objetos 'delante' (cuerpo, cuello, cara, cabeza).
"""
import json
import math
import os
import re

AQUI = os.path.dirname(os.path.abspath(__file__))
NAVY = "#1e1a6b"
VIEWBOX = 'viewBox="140 170 470 460" width="470" height="460"'

CUERPO = "M215 560 C205 470 200 390 222 320 C245 250 310 228 370 228 C440 228 500 250 515 320 C530 390 525 470 520 560 C520 600 460 616 370 616 C280 616 215 600 215 560 Z"

ESTILO = """  <style>
    .pelo        { fill: var(--pelo); }
    .pelo-trazo  { stroke: var(--pelo); fill: none; stroke-linecap: round; stroke-linejoin: round; }
    .pelo-claro  { fill: color-mix(in srgb, var(--pelo) 65%, white); }
    .pelo-oscuro { fill: color-mix(in srgb, var(--pelo) 80%, black); }
    .pico        { fill: var(--pico); }
    .pico-oscuro { fill: color-mix(in srgb, var(--pico) 78%, black); }
    .acento      { fill: var(--acento); }
    .acento-trazo{ stroke: var(--acento); fill: none; stroke-linejoin: round; }
    .acento-suave{ fill: color-mix(in srgb, var(--acento) 40%, white); }
    .linea       { stroke: #1e1a6b; stroke-width: 8; stroke-linejoin: round; stroke-linecap: round; }
    .trazo       { stroke: #1e1a6b; fill: none; stroke-linecap: round; stroke-linejoin: round; }
  </style>"""

ESTILO_OBJ = """  <style>
    .objeto        { fill: var(--objeto); }
    .objeto-claro  { fill: color-mix(in srgb, var(--objeto) 60%, white); }
    .objeto-oscuro { fill: color-mix(in srgb, var(--objeto) 75%, black); }
    .objeto-trazo  { stroke: var(--objeto); fill: none; stroke-linecap: round; stroke-linejoin: round; }
    .objeto-2      { fill: var(--objeto2); }
    .objeto-2-oscuro { fill: color-mix(in srgb, var(--objeto2) 70%, black); }
    .objeto2-trazo { stroke: var(--objeto2); fill: none; stroke-linecap: round; stroke-linejoin: round; }
    .linea         { stroke: #1e1a6b; stroke-width: 8; stroke-linejoin: round; stroke-linecap: round; }
    .trazo         { stroke: #1e1a6b; fill: none; stroke-linecap: round; stroke-linejoin: round; }
  </style>"""


# ---------------------------------------------------------------- utilidades
def espejo(d, eje=379):
    """Refleja un path absoluto (M/L/C/Z) sobre x=eje."""
    toks, out, i = re.findall(r"[A-Za-z]|-?[\d.]+", d), [], 0
    while i < len(toks):
        t = toks[i]
        if t.isalpha():
            out.append(t); i += 1
        else:
            out.append(f"{2*eje - float(t):g}"); out.append(toks[i + 1]); i += 2
    return " ".join(out)


def par(d, clase, eje=375, extra=""):
    return f'<path class="{clase}" {extra} d="{d}"/>\n  <path class="{clase}" {extra} d="{espejo(d, eje)}"/>'


def tubo(d, ancho, clase="pelo-trazo", rayas=None):
    """Trazo con contorno azul (brazos, colas)."""
    s = (f'<path class="trazo" stroke-width="{ancho+8}" d="{d}"/>'
         f'<path class="{clase}" stroke-width="{ancho}" d="{d}"/>')
    if rayas:
        s += f'<path class="acento-trazo" stroke-width="{ancho}" stroke-dasharray="{rayas}" d="{d}"/>'
    return s


def bolitas(pts, clase, contorno=12):
    """Círculos solapados con un solo contorno exterior (melena, lana, nubes)."""
    a = "".join(f'<circle class="trazo" fill="{NAVY}" stroke-width="{contorno}" cx="{x}" cy="{y}" r="{r}"/>' for x, y, r in pts)
    b = "".join(f'<circle class="{clase}" cx="{x}" cy="{y}" r="{r}"/>' for x, y, r in pts)
    return a + b


def estrella(cx, cy, r, clase, extra=""):
    pts = []
    for k in range(10):
        a = -math.pi / 2 + k * math.pi / 5
        rr = r if k % 2 == 0 else r * 0.45
        pts.append(f"{cx + rr*math.cos(a):.1f},{cy + rr*math.sin(a):.1f}")
    return f'<polygon class="{clase}" {extra} points="{" ".join(pts)}"/>'


def ojos(anillo=None, iris=None):
    out = []
    for cx, cy in ((318, 352), (440, 355)):
        if anillo:
            out.append(f'<circle cx="{cx}" cy="{cy}" r="{anillo}" fill="#fff"/>')
        if iris:
            out.append(f'<circle cx="{cx}" cy="{cy}" r="24" fill="{iris}" stroke="{NAVY}" stroke-width="3"/>')
            out.append(f'<circle cx="{cx+1}" cy="{cy+2}" r="13" fill="{NAVY}"/>')
        else:
            out.append(f'<circle cx="{cx}" cy="{cy}" r="24" fill="{NAVY}"/>')
        out.append(f'<circle cx="{cx-9}" cy="{cy-9}" r="8" fill="#fff"/>')
        out.append(f'<circle cx="{cx+9}" cy="{cy+10}" r="3.5" fill="#fff"/>')
    return "\n    ".join(out)


# ---------------------------------------------------------------- piezas de animal
def brazos(clase="pelo-trazo", mano=None):
    """Mismas posiciones que las aletas: izquierda saludando, derecha abajo. Ids compatibles."""
    izq, der = "M244 408 L180 322", "M502 470 L558 544"
    mano_izq = mano or ""
    return f'''<g id="aleta-izq">
    {tubo(izq, 52, clase)}
    {mano_izq.format(x=180, y=322)}
    <ellipse class="acento-suave" cx="181" cy="328" rx="10" ry="8"/>
    <circle class="acento-suave" cx="167" cy="314" r="4.5"/><circle class="acento-suave" cx="179" cy="308" r="4.5"/><circle class="acento-suave" cx="192" cy="313" r="4.5"/>
  </g>
  <g id="aleta-der">
    {tubo(der, 52, clase)}
    {mano_izq.format(x=558, y=544)}
  </g>'''


OREJA_PUNTA = "M238 312 C232 262 236 214 250 186 C282 196 316 218 340 244 Z"
OREJA_PUNTA_IN = "M254 292 C250 256 254 226 262 208 C284 218 304 232 320 248 Z"


def orejas_punta(interior="acento-suave", punta=None):
    s = par(OREJA_PUNTA, "pelo linea") + "\n  " + par(OREJA_PUNTA_IN, interior)
    if punta:
        s += "\n  " + par("M250 186 C262 190 276 197 290 205 C278 208 262 212 244 222 C245 208 247 196 250 186 Z", punta)
    return s


def orejas_redondas(cx=270, cy=248, r=40, ri=22, clase="pelo", interior="acento-suave", eje=375):
    cx2 = 2 * eje - cx
    s = f'<circle class="{clase} linea" cx="{cx}" cy="{cy}" r="{r}"/><circle class="{clase} linea" cx="{cx2}" cy="{cy}" r="{r}"/>'
    if interior:
        s += f'<circle class="{interior}" cx="{cx-2}" cy="{cy-4}" r="{ri}"/><circle class="{interior}" cx="{cx2+2}" cy="{cy-4}" r="{ri}"/>'
    return s


def orejas_largas(rx, ry, cx, cy, ang, interior="acento-suave", eje=375):
    cx2 = 2 * eje - cx
    return (f'<ellipse class="pelo linea" cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" transform="rotate({-ang} {cx} {cy})"/>'
            f'<ellipse class="pelo linea" cx="{cx2}" cy="{cy}" rx="{rx}" ry="{ry}" transform="rotate({ang} {cx2} {cy})"/>'
            f'<ellipse class="{interior}" cx="{cx}" cy="{cy+4}" rx="{rx*.5:g}" ry="{ry*.72:g}" transform="rotate({-ang} {cx} {cy})"/>'
            f'<ellipse class="{interior}" cx="{cx2}" cy="{cy+4}" rx="{rx*.5:g}" ry="{ry*.72:g}" transform="rotate({ang} {cx2} {cy})"/>')


OREJA_CAIDA = "M270 244 C236 240 208 278 206 330 C204 374 222 400 246 394 C264 388 274 352 282 302 C286 276 286 254 270 244 Z"

N_OVAL = "M354 384 C354 368 404 368 404 384 C404 398 392 406 379 406 C366 406 354 398 354 384 Z"
N_TRI = "M364 386 C364 377 394 377 394 386 C394 394 386 400 379 400 C372 400 364 394 364 386 Z"
N_KOALA = "M354 368 C354 344 404 344 404 368 L404 392 C404 412 392 420 379 420 C366 420 354 412 354 392 Z"


def boca(y, ancho=24, alto=12):
    return (f'<path class="trazo" stroke-width="5" d="M379 {y} L379 {y+8} M379 {y+8} C{379-ancho*.3:g} {y+8+alto} {379-ancho:g} {y+8+alto} {379-ancho-4:g} {y+10} '
            f'M379 {y+8} C{379+ancho*.3:g} {y+8+alto} {379+ancho:g} {y+8+alto} {379+ancho+4:g} {y+10}"/>')


def nariz(tipo="oval", lengua=False, dientes=False):
    if tipo == "cerdo":
        return (f'<ellipse class="pico linea" stroke-width="6" cx="379" cy="392" rx="38" ry="27"/>'
                f'<ellipse class="pico-oscuro" cx="366" cy="392" rx="6" ry="10"/><ellipse class="pico-oscuro" cx="392" cy="392" rx="6" ry="10"/>'
                f'<path class="trazo" stroke-width="5" d="M364 432 C372 440 386 440 394 432"/>')
    if tipo == "koala":
        return (f'<path class="pico linea" stroke-width="6" d="{N_KOALA}"/>'
                f'<ellipse cx="368" cy="362" rx="7" ry="10" fill="#fff" opacity=".45"/>'
                f'<path class="trazo" stroke-width="5" d="M366 432 C372 438 386 438 392 432"/>')
    d, y = (N_OVAL, 406) if tipo == "oval" else (N_TRI, 400)
    s = ""
    if lengua:
        s += f'<path fill="#f06a7a" stroke="{NAVY}" stroke-width="4" stroke-linejoin="round" d="M366 {y+14} C366 {y+40} 392 {y+40} 392 {y+14} C384 {y+18} 374 {y+18} 366 {y+14} Z"/><path d="M379 {y+19} L379 {y+30}" stroke="#d24a5c" stroke-width="3" stroke-linecap="round"/>'
    if dientes:
        s += f'<path fill="#fff" stroke="{NAVY}" stroke-width="3.5" stroke-linejoin="round" d="M369 {y+12} L369 {y+28} C369 {y+31} 389 {y+31} 389 {y+28} L389 {y+12} Z M379 {y+13} L379 {y+29}"/>'
    s += f'<path class="pico linea" stroke-width="5" d="{d}"/>'
    s += f'<ellipse cx="{368 if tipo=="oval" else 372}" cy="{y-24 if tipo=="oval" else y-16}" rx="6" ry="3.5" fill="#fff" opacity=".7"/>'
    s += boca(y, 22 if tipo == "oval" else 16, 11 if tipo == "oval" else 9)
    return s


def bigotes(y=398, puntos=False):
    if puntos:
        return "".join(f'<circle fill="{NAVY}" cx="{x}" cy="{yy}" r="3.5"/><circle fill="{NAVY}" cx="{758-x}" cy="{yy}" r="3.5"/>'
                       for x, yy in ((336, y + 6), (326, y + 16), (340, y + 20)))
    d = f"M306 {y} L248 {y-12} M306 {y+12} L246 {y+16}"
    return f'<path class="trazo" stroke-width="4" d="{d} {espejo(d, 379)}"/>'


def hocico(clase="blanco", rx=58, ry=40, cy=404):
    fill = 'fill="#fff"' if clase == "blanco" else f'class="{clase}"'
    return f'<ellipse {fill} cx="379" cy="{cy}" rx="{rx}" ry="{ry}"/>'


def panza(clase="blanco", rx=122, ry=104, cy=574):
    fill = 'fill="#fff"' if clase == "blanco" else f'class="{clase}"'
    return f'<ellipse {fill} cx="370" cy="{cy}" rx="{rx}" ry="{ry}"/>'


RUBOR = '<ellipse cx="282" cy="402" rx="18" ry="11" fill="#ff8fa8" opacity=".45"/><ellipse cx="476" cy="404" rx="18" ry="11" fill="#ff8fa8" opacity=".45"/>'


def melena():
    pts = []
    for k in range(15):
        a = math.radians(-202 + k * (224 / 14))
        pts.append((round(372 + 172 * math.cos(a)), round(358 + 144 * math.sin(a)), 34))
    return bolitas(pts, "acento", 16)


# ---------------------------------------------------------------- animales
ANIMALES = [
    dict(id="perro", nombre="Perro", pelo="#d9a066", pico="#2b2238", acento="#8a5a3b",
         detras=tubo("M258 590 C222 598 194 584 182 556", 20),
         brazos=brazos(),
         cara=hocico() + panza() + '<ellipse class="acento" cx="442" cy="346" rx="46" ry="42"/>',
         ojos=ojos(),
         encima=par(OREJA_CAIDA, "acento linea", 379),
         nariz=nariz("oval", lengua=True)),
    dict(id="gato", nombre="Gato", pelo="#f4a259", pico="#f28fa0", acento="#c8652a",
         detras=orejas_punta() + tubo("M262 590 C210 604 168 580 162 536 C158 506 172 486 188 476", 18),
         brazos=brazos(),
         cara=hocico(rx=46, ry=32, cy=402) + panza()
              + '<path class="acento" d="M352 226 L362 276 L372 226 Z M372 222 L379 286 L386 222 Z M386 226 L396 276 L406 226 Z"/>'
              + par("M200 420 L258 432 L200 446 Z M200 470 L250 480 L200 494 Z", "acento", 370),
         ojos=ojos(iris="#8bc34a"),
         encima=bigotes(),
         nariz=nariz("tri")),
    dict(id="leon", nombre="León", pelo="#f2c14e", pico="#7a4a3a", acento="#c8641e",
         detras=melena() + orejas_redondas(282, 240, 30, 16)
                + tubo("M262 592 C214 606 180 596 170 566", 14)
                + bolitas([(166, 556, 16), (158, 544, 12), (174, 546, 11)], "acento", 12),
         brazos=brazos(),
         cara=hocico("pelo-claro") + panza("pelo-claro"),
         ojos=ojos(),
         encima=bigotes(396, puntos=True),
         nariz=nariz("oval")),
    dict(id="tigre", nombre="Tigre", pelo="#f5892a", pico="#e86f7f", acento="#2b2233",
         detras=orejas_redondas(274, 246, 32, 18, interior=None)
                + '<circle cx="272" cy="244" r="15" fill="#fff"/><circle cx="478" cy="244" r="15" fill="#fff"/>'
                + tubo("M262 590 C210 604 168 580 162 536 C158 506 172 486 188 476", 20, rayas="12 14"),
         brazos=brazos(),
         cara=hocico(rx=64, ry=42) + panza()
              + '<path class="acento" d="M356 228 L366 272 L376 228 Z M374 226 L379 262 L384 226 Z M384 228 L392 272 L402 228 Z"/>'
              + par("M198 380 L262 392 L198 404 Z M198 432 L252 440 L198 454 Z M198 506 L244 514 L198 526 Z", "acento", 370)
              + '<ellipse cx="300" cy="316" rx="14" ry="8" fill="#fff"/><ellipse cx="458" cy="318" rx="14" ry="8" fill="#fff"/>',
         ojos=ojos(),
         encima=bigotes(),
         nariz=nariz("tri")),
    dict(id="zorro", nombre="Zorro", pelo="#ef6f2e", pico="#2b2238", acento="#3a2c3c",
         detras=orejas_punta(interior="acento-suave", punta="acento")
                + '<clipPath id="{p}-cola"><path d="M264 560 C222 536 168 536 148 578 C138 604 160 626 192 620 C222 614 252 604 268 594 Z"/></clipPath>'
                + '<path class="pelo linea" d="M264 560 C222 536 168 536 148 578 C138 604 160 626 192 620 C222 614 252 604 268 594 Z"/>'
                + '<g clip-path="url(#{p}-cola)"><ellipse cx="150" cy="604" rx="34" ry="40" fill="#fff"/></g>'
                + '<path class="trazo" stroke-width="8" fill="none" d="M264 560 C222 536 168 536 148 578 C138 604 160 626 192 620 C222 614 252 604 268 594"/>',
         brazos=brazos(mano='<circle class="acento" cx="{x}" cy="{y}" r="22"/>'),
         cara='<path fill="#fff" d="M200 372 C250 368 320 392 379 440 C438 392 508 368 540 372 L540 640 L200 640 Z"/>',
         ojos=ojos(),
         encima="",
         nariz=nariz("oval")),
    dict(id="oso", nombre="Oso", pelo="#8d5b3e", pico="#2b2238", acento="#e3b98f",
         detras=orejas_redondas(),
         brazos=brazos(),
         cara=hocico("acento") + panza("acento"),
         ojos=ojos(),
         encima="",
         nariz=nariz("oval")),
    dict(id="panda", nombre="Panda", pelo="#f7f7fb", pico="#2b2d42", acento="#2b2d42",
         detras=orejas_redondas(clase="acento", interior=None),
         brazos=brazos("acento-trazo"),
         cara='<ellipse class="acento" cx="314" cy="356" rx="36" ry="46" transform="rotate(28 314 356)"/>'
              '<ellipse class="acento" cx="444" cy="358" rx="36" ry="46" transform="rotate(-28 444 358)"/>',
         ojos=ojos(anillo=28),
         encima="",
         nariz=nariz("oval")),
    dict(id="conejo", nombre="Conejo", pelo="#e8e3f2", pico="#f28fa0", acento="#f6a6c1",
         detras=orejas_largas(22, 46, 298, 228, 30),
         brazos=brazos(),
         cara=hocico(rx=44, ry=32, cy=402) + panza() + RUBOR,
         ojos=ojos(),
         encima="",
         nariz=nariz("tri", dientes=True)),
    dict(id="mapache", nombre="Mapache", pelo="#9a9cae", pico="#2b2238", acento="#34364a",
         detras=orejas_punta(interior="acento") + tubo("M262 590 C212 604 172 584 164 540 C160 516 168 498 180 488", 26, rayas="13 12"),
         brazos=brazos(mano='<circle class="acento" cx="{x}" cy="{y}" r="22"/>'),
         cara=hocico() + panza("pelo-claro")
              + '<path class="acento" d="M200 334 C250 314 330 328 379 346 C428 328 508 314 540 334 L540 388 C490 400 430 394 379 382 C328 394 268 400 200 388 Z"/>'
              + '<path fill="#fff" d="M278 318 C300 300 336 302 352 318 C330 312 300 312 278 318 Z"/><path fill="#fff" d="M406 320 C422 304 458 302 480 320 C458 314 428 314 406 320 Z"/>',
         ojos=ojos(anillo=28),
         encima="",
         nariz=nariz("oval")),
    dict(id="koala", nombre="Koala", pelo="#a3a8b8", pico="#3b3848", acento="#f4f4f8",
         detras=orejas_redondas(254, 258, 52, 32, interior="acento")
                + "".join(f'<circle class="acento" cx="{x}" cy="{y}" r="9"/><circle class="acento" cx="{750-x}" cy="{y}" r="9"/>' for x, y in ((226, 250), (234, 232), (250, 222))),
         brazos=brazos(),
         cara=panza("acento", rx=112, ry=96) + '<ellipse class="acento" cx="379" cy="440" rx="30" ry="16"/>',
         ojos=ojos(),
         encima="",
         nariz=nariz("koala")),
    dict(id="alpaca", nombre="Alpaca", pelo="#f5ead8", pico="#8a6a5a", acento="#e0457b",
         detras=orejas_largas(16, 40, 300, 222, 22, interior="pelo-claro"),
         brazos=brazos(),
         cara=hocico("pelo-claro", rx=50, ry=40, cy=406) + panza("pelo-claro") + RUBOR,
         ojos=ojos(),
         encima=bolitas([(330, 252, 20), (352, 236, 22), (380, 230, 24), (408, 236, 22), (430, 252, 20), (356, 262, 18), (404, 262, 18), (380, 258, 20)], "pelo-claro", 10)
                + '<circle class="acento linea" stroke-width="4" cx="296" cy="258" r="12"/><circle class="acento linea" stroke-width="4" cx="462" cy="258" r="12"/>',
         nariz=nariz("tri")),
    dict(id="cerdito", nombre="Cerdito", pelo="#f9b8c9", pico="#f58fab", acento="#e56f93",
         detras=orejas_punta(interior="acento") + '<path class="trazo" stroke-width="14" d="M250 584 C226 596 196 590 194 568 C192 548 218 544 222 562 C226 580 204 588 186 578"/><path class="pelo-trazo" stroke-width="7" d="M250 584 C226 596 196 590 194 568 C192 548 218 544 222 562 C226 580 204 588 186 578"/>',
         brazos=brazos(),
         cara=panza("pelo-claro") + RUBOR,
         ojos=ojos(),
         encima="",
         nariz=nariz("cerdo")),
]


def svg_animal(a, pref=None, objetos=()):
    p = pref or a["id"]
    detras_obj = "".join(o.get("detras_svg", "") for o in objetos)
    delante_obj = "".join(o.get("delante_svg", "") for o in objetos)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" {VIEWBOX} style="--pelo:{a['pelo']};--pico:{a['pico']};--acento:{a['acento']}">
{ESTILO}
  <defs><clipPath id="{p}-clip"><path id="{p}-cuerpo" d="{CUERPO}"/></clipPath></defs>
  {detras_obj}<g id="detras">
  {a['detras'].replace('{p}', p)}
  </g>
  {a['brazos']}
  <use href="#{p}-cuerpo" class="pelo"/>
  <g clip-path="url(#{p}-clip)">
    <path class="pelo-claro" d="M268 272 C310 246 432 240 488 272 C440 260 320 260 268 272 Z"/>
    <g id="cara">{a['cara']}</g>
    <ellipse cx="370" cy="618" rx="170" ry="30" fill="#e2e2ee"/>
  </g>
  <use href="#{p}-cuerpo" fill="none" class="linea"/>
  <g id="ojos">
    {a['ojos']}
  </g>
  <g id="encima">{a['encima']}</g>
  <g id="pico">{a['nariz']}</g>
{delante_obj}</svg>
'''


# ---------------------------------------------------------------- objetos
def lentes():
    s = ""
    for cx, cy in ((318, 352), (440, 355)):
        s += f'<circle cx="{cx}" cy="{cy}" r="33" fill="#fff" fill-opacity=".22"/><circle class="trazo" stroke-width="13" cx="{cx}" cy="{cy}" r="33"/><circle class="objeto-trazo" stroke-width="7" cx="{cx}" cy="{cy}" r="33"/>'
        s += f'<path d="M{cx-14} {cy-20} C{cx-8} {cy-24} {cx+2} {cy-25} {cx+8} {cy-23}" stroke="#fff" stroke-width="4" fill="none" stroke-linecap="round" opacity=".8"/>'
    d = "M351 350 C364 340 394 340 407 353 M285 346 L230 336 M473 350 L516 342"
    return f'<path class="trazo" stroke-width="13" d="{d}"/><path class="objeto-trazo" stroke-width="7" d="{d}"/>' + s


def gafas_sol():
    s = f'<path class="trazo" stroke-width="7" d="M346 352 C360 342 398 342 412 354 M284 344 L230 336 M474 348 L516 342"/>'
    for cx, cy in ((318, 352), (440, 355)):
        d = f"M{cx-32} {cy-22} C{cx-32} {cy-30} {cx+32} {cy-30} {cx+32} {cy-22} C{cx+32} {cy+12} {cx+18} {cy+26} {cx} {cy+26} C{cx-18} {cy+26} {cx-32} {cy+12} {cx-32} {cy-22} Z"
        s += f'<path class="objeto linea" stroke-width="6" d="{d}"/>'
        s += f'<path class="objeto-2" d="M{cx-32} {cy-22} C{cx-32} {cy-30} {cx+32} {cy-30} {cx+32} {cy-22} L{cx+32} {cy-14} C{cx+10} {cy-18} {cx-10} {cy-18} {cx-32} {cy-14} Z"/>'
        s += f'<path d="M{cx-18} {cy-6} L{cx-4} {cy-6} M{cx-18} {cy+4} L{cx-12} {cy+4}" stroke="#fff" stroke-width="4" stroke-linecap="round" opacity=".55"/>'
    return s


def poncho():
    D = "M206 446 C280 426 470 426 532 446 L540 548 L379 604 L200 548 Z"
    zig = " ".join(f"{x},{497 if (x//18)%2 else 485}" for x in range(196, 548, 18))
    fleco = ""
    for k in range(1, 12):
        t = k / 12
        x1, y1 = 200 + (379 - 200) * t, 548 + (604 - 548) * t
        x2, y2 = 379 + (540 - 379) * t, 604 + (548 - 604) * t
        fleco += f"M{x1:.0f} {y1:.0f} L{x1-2:.0f} {y1+13:.0f} M{x2:.0f} {y2:.0f} L{x2+2:.0f} {y2+13:.0f} "
    return f'''<path class="trazo" stroke-width="9" d="{fleco}"/><path class="objeto2-trazo" stroke-width="4" d="{fleco}"/>
    <path class="objeto linea" stroke-width="6" d="{D}"/>
    <g clip-path="url(#{{p}}-poncho)">
      <rect class="objeto-2" x="190" y="474" width="360" height="34"/>
      <polyline points="{zig}" fill="none" stroke="#fff" stroke-width="5" stroke-linejoin="round"/>
      <rect class="objeto-oscuro" x="190" y="528" width="360" height="12"/>
      {"".join(f'<path class="objeto-2" d="M{x} 446 L{x+8} 456 L{x} 466 L{x-8} 456 Z"/>' for x in range(250, 520, 36))}
    </g>
    <path class="trazo" stroke-width="6" d="{D}"/>
    <defs><clipPath id="{{p}}-poncho"><path d="{D}"/></clipPath></defs>'''


def tunica():
    V = "M190 452 C260 470 330 480 379 520 C428 480 500 470 560 452"
    R = V + " L560 650 L190 650 Z"
    return f'''<defs><clipPath id="{{p}}-tun-c"><path d="{CUERPO}"/></clipPath><clipPath id="{{p}}-tun-r"><path d="{R}"/></clipPath></defs>
    <g clip-path="url(#{{p}}-tun-c)">
      <path class="objeto" d="{R}"/>
      <ellipse class="objeto-oscuro" cx="370" cy="618" rx="170" ry="30"/>
      <path class="objeto2-trazo" stroke-width="14" d="{V}"/>
      <path class="trazo" stroke-width="5" d="M190 444 C260 462 330 472 379 512 C428 472 500 462 560 444"/>
      <path class="objeto2-trazo" stroke-width="10" d="M379 524 L379 640"/>
      {estrella(300, 560, 14, "objeto-2")}{estrella(452, 548, 11, "objeto-2")}{estrella(470, 596, 8, "objeto-2")}{estrella(268, 520, 7, "objeto-2")}
    </g>
    <g clip-path="url(#{{p}}-tun-r)"><path class="linea" fill="none" d="{CUERPO}"/></g>'''


def bufanda():
    B = "M212 438 C290 468 450 468 526 438 L528 470 C450 504 290 504 210 470 Z"
    E = "M430 474 C434 514 438 544 440 576 L482 570 C478 534 472 504 466 472 Z"
    fl = "".join(f"M{444+k*9} {575-k} L{444+k*9} {590-k} " for k in range(5))
    return f'''<defs><clipPath id="{{p}}-buf"><path d="{B}"/><path d="{E}"/></clipPath></defs>
    <path class="trazo" stroke-width="10" d="{fl}"/><path class="objeto-trazo" stroke-width="5" d="{fl}"/>
    <path class="objeto linea" stroke-width="6" d="{B}"/>
    <path class="objeto linea" stroke-width="6" d="{E}"/>
    <g clip-path="url(#{{p}}-buf)">
      {"".join(f'<rect class="objeto-2" x="{x}" y="420" width="18" height="100"/>' for x in (246, 316, 386, 456))}
      <rect class="objeto-2" x="420" y="506" width="80" height="14"/><rect class="objeto-2" x="420" y="536" width="80" height="14"/>
    </g>
    <path class="trazo" stroke-width="6" d="{B}"/><path class="trazo" stroke-width="6" d="{E}"/>'''


def lei():
    s = ""
    for k in range(9):
        t = k / 8
        x = (1-t)**2*224 + 2*(1-t)*t*379 + t*t*524
        y = (1-t)**2*426 + 2*(1-t)*t*510 + t*t*426
        c = "objeto" if k % 2 == 0 else "objeto-2"
        for j in range(5):
            a = math.radians(j * 72 - 90)
            s += f'<circle class="{c} linea" stroke-width="3.5" cx="{x+11*math.cos(a):.1f}" cy="{y+11*math.sin(a):.1f}" r="10"/>'
        s += f'<circle fill="#fff" stroke="{NAVY}" stroke-width="3" cx="{x:.1f}" cy="{y:.1f}" r="6"/>'
    return s


def flor(cx, cy, r=13):
    pts = [(round(cx + r*math.cos(math.radians(k*72-90)), 1), round(cy + r*math.sin(math.radians(k*72-90)), 1), r) for k in range(5)]
    return bolitas(pts, "objeto-2", 8) + f'<circle fill="#ffd23f" stroke="{NAVY}" stroke-width="4" cx="{cx}" cy="{cy}" r="{r*.7:.0f}"/>'


CHULLO = "M216 300 C226 246 296 220 370 220 C446 220 510 244 522 300 C470 286 280 286 216 300 Z"
FLAP = "M218 292 C208 332 214 370 232 394 C250 386 262 348 264 292 Z"

OBJETOS = [
    # ---- cabeza
    dict(id="corona", nombre="Corona", categoria="cabeza", objeto="#ffc93c", objeto2="#e63946", delante=f'''
    <path class="objeto linea" stroke-width="6" d="M318 248 L312 196 L344 220 L375 186 L406 220 L438 196 L432 248 C400 254 350 254 318 248 Z"/>
    <path class="objeto-oscuro" d="M320 236 C350 242 400 242 430 236 L432 248 C400 254 350 254 318 248 Z"/>
    <circle class="objeto linea" stroke-width="4" cx="312" cy="194" r="8"/><circle class="objeto linea" stroke-width="4" cx="375" cy="184" r="9"/><circle class="objeto linea" stroke-width="4" cx="438" cy="194" r="8"/>
    <circle class="objeto-2 linea" stroke-width="4" cx="375" cy="226" r="10"/><circle class="objeto-2" cx="341" cy="230" r="6"/><circle class="objeto-2" cx="409" cy="230" r="6"/>
    <path class="trazo" stroke-width="6" d="M318 248 C350 254 400 254 432 248"/>'''),
    dict(id="gorro-fiesta", nombre="Gorro de fiesta", categoria="cabeza", objeto="#4cc9f0", objeto2="#ff5d8f", delante=f'''
    <g transform="rotate(10 380 248)">
      <path class="objeto linea" stroke-width="6" d="M318 252 L382 190 L446 252 C404 262 360 262 318 252 Z"/>
      <circle class="objeto-2" cx="364" cy="236" r="7"/><circle class="objeto-2" cx="398" cy="228" r="6"/><circle class="objeto-2" cx="380" cy="210" r="5"/><circle class="objeto-2" cx="414" cy="246" r="5"/><circle class="objeto-2" cx="346" cy="249" r="4"/>
      <path class="objeto2-trazo" stroke-width="7" d="M320 252 C360 262 404 262 444 252"/>
      <circle class="objeto-2 linea" stroke-width="5" cx="382" cy="190" r="13"/>
    </g>'''),
    dict(id="sombrero-copa", nombre="Sombrero de copa", categoria="cabeza", objeto="#2b2d42", objeto2="#e63946", delante=f'''
    <g transform="rotate(-8 375 240)">
      <path class="objeto linea" stroke-width="6" d="M332 238 L327 190 C327 182 423 182 423 190 L418 238 Z"/>
      <path class="objeto-2" d="M330.3 218 L419.7 218 L418.3 234 L331.7 234 Z"/>
      <path class="objeto-claro" opacity=".5" d="M348 194 L350 212 L357 212 L355 194 Z"/>
      <ellipse class="objeto linea" stroke-width="6" cx="375" cy="240" rx="80" ry="13"/>
    </g>'''),
    dict(id="gorro-mago", nombre="Gorro de mago", categoria="cabeza", objeto="#5a4fcf", objeto2="#ffd23f", delante=f'''
    <path class="objeto linea" stroke-width="6" d="M316 246 C330 214 350 192 374 180 C394 172 424 176 448 188 C424 192 410 204 406 216 C414 228 422 238 430 246 Z"/>
    {estrella(372, 220, 13, "objeto-2")}{estrella(402, 238, 7, "objeto-2")}{estrella(346, 238, 6, "objeto-2")}
    <circle class="objeto-2" cx="447" cy="189" r="6"/>
    <ellipse class="objeto linea" stroke-width="6" cx="372" cy="248" rx="94" ry="15"/>
    <path class="objeto-2" d="M290 246 C330 240 414 240 454 246 C414 244 330 244 290 246 Z"/>'''),
    dict(id="chullo", nombre="Chullo andino", categoria="cabeza", objeto="#d62839", objeto2="#ffd23f", delante=f'''
    <defs><clipPath id="{{p}}-chullo"><path d="{CHULLO}"/></clipPath></defs>
    <path class="trazo" stroke-width="12" d="M232 394 L228 440 M{742-232} 394 L{742-228} 440"/><path class="objeto2-trazo" stroke-width="5" d="M232 394 L228 440 M{742-232} 394 L{742-228} 440"/>
    <circle class="objeto-2 linea" stroke-width="5" cx="228" cy="446" r="11"/><circle class="objeto-2 linea" stroke-width="5" cx="{742-228}" cy="446" r="11"/>
    <path class="objeto linea" stroke-width="6" d="{FLAP}"/><path class="objeto linea" stroke-width="6" d="{espejo(FLAP, 371)}"/>
    <path class="objeto-2" d="M222 350 L234 336 L246 350 L234 364 Z M{742-222} 350 L{742-234} 336 L{742-246} 350 L{742-234} 364 Z"/>
    <path class="objeto linea" stroke-width="6" d="{CHULLO}"/>
    <g clip-path="url(#{{p}}-chullo)">
      <path class="objeto-2" d="M200 266 C290 250 450 250 540 266 L540 284 C450 268 290 268 200 284 Z"/>
      <polyline points="{" ".join(f"{x},{246 if (x//16)%2 else 236}" for x in range(208, 540, 16))}" fill="none" stroke="#fff" stroke-width="5" stroke-linejoin="round"/>
      {"".join(f'<path fill="#fff" d="M{x} 262 L{x+6} 268 L{x} 274 L{x-6} 268 Z"/>' for x in range(248, 500, 30))}
    </g>
    <path class="trazo" stroke-width="6" d="{CHULLO}"/>
    <circle class="objeto-2 linea" stroke-width="5" cx="370" cy="212" r="15"/>'''),
    dict(id="gorra", nombre="Gorra", categoria="cabeza", objeto="#2a9d8f", objeto2="#f4f1de", delante=f'''
    <path class="objeto linea" stroke-width="6" d="M236 292 C244 246 300 222 372 222 C446 222 502 246 510 292 C450 282 296 282 236 292 Z"/>
    <path d="M372 224 C360 240 350 262 346 286 M372 224 C384 240 394 262 398 286" stroke="{NAVY}" stroke-opacity=".25" stroke-width="4" fill="none"/>
    <circle class="objeto-2 linea" stroke-width="4" cx="372" cy="262" r="13"/>
    <path class="objeto-2 linea" stroke-width="6" d="M244 290 C300 276 448 276 502 290 C510 300 504 310 492 312 C440 298 306 298 254 312 C242 310 236 300 244 290 Z"/>
    <circle class="objeto linea" stroke-width="4" cx="372" cy="222" r="7"/>'''),
    dict(id="gorro-chef", nombre="Gorro de chef", categoria="cabeza", objeto="#ffffff", objeto2="#e63946", delante=f'''
    {bolitas([(334, 212, 24), (374, 200, 26), (414, 212, 24), (354, 220, 20), (394, 220, 20)], "objeto", 12)}
    <path class="objeto linea" stroke-width="6" d="M324 252 L328 214 L420 214 L424 252 C392 258 356 258 324 252 Z"/>
    <path class="objeto-2" d="M326 234 L422 234 L423 243 L325 243 Z"/>
    <path d="M356 218 L354 232 M376 218 L376 232 M396 218 L398 232" stroke="{NAVY}" stroke-opacity=".25" stroke-width="3" fill="none"/>'''),
    dict(id="gorro-navidad", nombre="Gorro navideño", categoria="cabeza", objeto="#e63946", objeto2="#ffffff", delante=f'''
    <path class="objeto linea" stroke-width="6" d="M318 236 C324 200 358 180 402 180 C448 180 486 200 504 234 C484 222 462 224 448 238 Z"/>
    <path class="objeto-oscuro" opacity=".35" d="M440 232 C452 214 474 208 494 216 C470 212 456 220 446 234 Z"/>
    <rect class="objeto-2 linea" stroke-width="6" x="302" y="224" width="158" height="28" rx="14"/>
    <circle class="objeto-2 linea" stroke-width="5" cx="506" cy="236" r="15"/>'''),
    dict(id="diadema-flor", nombre="Diadema con flor", categoria="cabeza", objeto="#9b5de5", objeto2="#ff8fab", delante=f'''
    <path class="trazo" stroke-width="18" d="M244 292 C272 240 470 236 502 288"/>
    <path class="objeto-trazo" stroke-width="10" d="M244 292 C272 240 470 236 502 288"/>
    <path fill="#52b788" stroke="{NAVY}" stroke-width="4" stroke-linejoin="round" d="M470 262 C488 262 500 272 504 284 C488 286 474 278 470 262 Z"/>
    {flor(456, 248)}'''),
    # ---- cara
    dict(id="lentes", nombre="Lentes redondos", categoria="cara", objeto="#c9a227", objeto2="#ffffff", delante=lentes()),
    dict(id="gafas-sol", nombre="Gafas de sol", categoria="cara", objeto="#2b2d42", objeto2="#ff5d8f", delante=gafas_sol()),
    # ---- cuello
    dict(id="bufanda", nombre="Bufanda", categoria="cuello", objeto="#e63946", objeto2="#f4f1de", delante=bufanda()),
    dict(id="pajarita", nombre="Pajarita", categoria="cuello", objeto="#e63946", objeto2="#ffffff", delante=f'''
    <path class="objeto linea" stroke-width="5" d="M379 456 L332 432 C320 444 320 470 332 482 Z"/>
    <path class="objeto linea" stroke-width="5" d="{espejo("M379 456 L332 432 C320 444 320 470 332 482 Z", 379)}"/>
    <circle class="objeto-2" cx="340" cy="448" r="4"/><circle class="objeto-2" cx="336" cy="466" r="4"/><circle class="objeto-2" cx="418" cy="448" r="4"/><circle class="objeto-2" cx="422" cy="466" r="4"/><circle class="objeto-2" cx="352" cy="458" r="3.5"/><circle class="objeto-2" cx="406" cy="458" r="3.5"/>
    <rect class="objeto-oscuro linea" stroke-width="5" x="366" y="444" width="26" height="24" rx="7"/>'''),
    dict(id="collar-placa", nombre="Collar con placa", categoria="cuello", objeto="#e63946", objeto2="#ffc93c", delante=f'''
    <path class="objeto linea" stroke-width="5" d="M216 436 C290 462 450 462 522 436 L523 456 C450 482 290 482 215 456 Z"/>
    <circle class="trazo" stroke-width="4" cx="379" cy="474" r="6"/>
    <circle class="objeto-2 linea" stroke-width="5" cx="379" cy="496" r="18"/>
    <g class="objeto-2-oscuro"><ellipse cx="379" cy="501" rx="7" ry="6"/><circle cx="370" cy="490" r="3.2"/><circle cx="379" cy="487" r="3.2"/><circle cx="388" cy="490" r="3.2"/></g>'''),
    dict(id="collar-flores", nombre="Collar de flores", categoria="cuello", objeto="#ff8fab", objeto2="#ffd23f", delante=lei()),
    # ---- cuerpo
    dict(id="tunica-mago", nombre="Túnica de mago", categoria="cuerpo", objeto="#5a4fcf", objeto2="#ffd23f", delante=tunica()),
    dict(id="poncho", nombre="Poncho andino", categoria="cuerpo", objeto="#d62839", objeto2="#ffd23f", delante=poncho()),
    dict(id="capa-heroe", nombre="Capa de héroe", categoria="cuerpo", objeto="#e63946", objeto2="#ffd23f",
         detras=f'''<path class="objeto linea" stroke-width="6" d="M252 410 C206 470 176 548 164 624 C260 610 480 610 580 624 C566 548 536 470 492 410 Z"/>
    <path class="objeto-oscuro" d="M180 590 C190 530 214 470 250 424 C230 470 214 530 206 606 C196 606 186 606 180 606 Z"/>''',
         delante=f'''<path class="trazo" stroke-width="18" d="M226 426 C290 456 460 456 518 426"/><path class="objeto-trazo" stroke-width="10" d="M226 426 C290 456 460 456 518 426"/>
    <circle class="objeto-2 linea" stroke-width="5" cx="373" cy="449" r="16"/>{estrella(373, 449, 9, "objeto-oscuro")}'''),
]

ORDEN = {"cuerpo": 1, "cuello": 2, "cara": 3, "cabeza": 4}


def capa_obj(o, parte, p):
    body = o.get(parte)
    if not body:
        return ""
    return f'<g id="obj-{o["id"]}{"-detras" if parte == "detras" else ""}" class="obj" style="--objeto:{o["objeto"]};--objeto2:{o["objeto2"]}">{body.replace("{p}", p)}</g>'


def para_componer(o, p):
    return dict(detras_svg=capa_obj(o, "detras", p), delante_svg=capa_obj(o, "delante", p))


def svg_objeto(o, parte="delante"):
    p = f"obj-{o['id']}{'-detras' if parte == 'detras' else ''}"
    return f'''<svg xmlns="http://www.w3.org/2000/svg" {VIEWBOX} style="--objeto:{o['objeto']};--objeto2:{o['objeto2']}">
{ESTILO_OBJ}
  <g id="{p}">{o[parte].replace("{p}", p)}</g>
</svg>
'''


def componer(a, ids_obj, pref):
    objs = sorted((o for o in OBJETOS if o["id"] in ids_obj), key=lambda o: ORDEN[o["categoria"]])
    return svg_animal(a, pref, [para_componer(o, f"{pref}-{o['id']}") for o in objs]).replace(
        "</style>", ESTILO_OBJ.split("<style>")[1].split("</style>")[0] + "</style>", 1)


# ---------------------------------------------------------------- salida
if __name__ == "__main__":
    os.makedirs(os.path.join(AQUI, "animales"), exist_ok=True)
    os.makedirs(os.path.join(AQUI, "objetos"), exist_ok=True)
    for a in ANIMALES:
        with open(os.path.join(AQUI, "animales", f"{a['id']}.svg"), "w") as f:
            f.write(svg_animal(a))
    manifiesto = []
    for o in OBJETOS:
        capas = []
        if o.get("detras"):
            with open(os.path.join(AQUI, "objetos", f"objeto-{o['id']}-detras.svg"), "w") as f:
                f.write(svg_objeto(o, "detras"))
            capas.append(dict(archivo=f"objetos/objeto-{o['id']}-detras.svg", posicion="detras", z=-1))
        with open(os.path.join(AQUI, "objetos", f"objeto-{o['id']}.svg"), "w") as f:
            f.write(svg_objeto(o))
        capas.append(dict(archivo=f"objetos/objeto-{o['id']}.svg", posicion="delante", z=ORDEN[o["categoria"]]))
        manifiesto.append(dict(id=o["id"], nombre=o["nombre"], categoria=o["categoria"],
                               colores={"--objeto": o["objeto"], "--objeto2": o["objeto2"]}, capas=capas))
    with open(os.path.join(AQUI, "objetos.json"), "w") as f:
        json.dump(dict(
            viewBox="140 170 470 460",
            orden_capas="z<0 detrás del animal; animal = 0; luego cuerpo(1), cuello(2), cara(3), cabeza(4)",
            una_por_categoria=True,
            animales=[dict(id=a["id"], nombre=a["nombre"], archivo=f"animales/{a['id']}.svg",
                           colores={"--pelo": a["pelo"], "--pico": a["pico"], "--acento": a["acento"]}) for a in ANIMALES],
            objetos=manifiesto), f, ensure_ascii=False, indent=2)
    print("ok", len(ANIMALES), "animales,", len(OBJETOS), "objetos")


# ---------------------------------------------------------------- galería / probador
def galeria():
    reglas_obj = ESTILO_OBJ.split("<style>")[1].split("</style>")[0]
    modelos = {a["id"]: dict(nombre=a["nombre"], svg=svg_animal(a, "pv"),
                             colores={"--pelo": a["pelo"], "--pico": a["pico"], "--acento": a["acento"]}) for a in ANIMALES}
    # Si la carpeta de pingüinos está al lado, se añaden al probador para comprobar que los objetos encajan
    dir_ping = os.path.join(AQUI, "..", "pinguinos")
    if os.path.isdir(dir_ping):
        for fn in sorted(os.listdir(dir_ping)):
            if fn.startswith("pinguino-") and fn.endswith(".svg"):
                txt = open(os.path.join(dir_ping, fn)).read()
                m = re.search(r'--pelo:([^;]+);--pico:([^;]+);--acento:([^"]+)"', txt)
                modelos[fn[:-4]] = dict(nombre="Pingüino " + fn[9:-4], svg=txt,
                                        colores={"--pelo": m[1], "--pico": m[2], "--acento": m[3]} if m else {})
    objetos = {o["id"]: dict(nombre=o["nombre"], categoria=o["categoria"], orden=ORDEN[o["categoria"]],
                             colores={"--objeto": o["objeto"], "--objeto2": o["objeto2"]},
                             detras=capa_obj(o, "detras", "pv-" + o["id"]), delante=capa_obj(o, "delante", "pv-" + o["id"]))
               for o in OBJETOS}
    tarjetas = "".join(
        f'''<figure data-id="{a['id']}">{svg_animal(a)}<figcaption>{a['nombre']}</figcaption>
<label>Pelo <input type="color" data-v="--pelo" value="{a['pelo']}"></label><label>Nariz <input type="color" data-v="--pico" value="{a['pico']}"></label><label>Acento <input type="color" data-v="--acento" value="{a['acento']}"></label></figure>'''
        for a in ANIMALES)
    cats = [("cabeza", "Cabeza"), ("cara", "Cara"), ("cuello", "Cuello"), ("cuerpo", "Cuerpo")]
    return f'''<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Animales y objetos</title>
<style>
body{{font-family:system-ui;margin:0;padding:24px;background:#f6f6fa;color:#1e1a6b}}h1{{margin:0 0 16px;font-size:22px}}h2{{font-size:17px;margin:28px 0 12px}}
.probador{{display:grid;grid-template-columns:minmax(260px,420px) 1fr;gap:20px;background:#fff;border-radius:16px;padding:20px}}
@media(max-width:760px){{.probador{{grid-template-columns:1fr}}}}
#vista svg{{width:100%;height:auto}}select{{font-size:15px;padding:6px 8px;border-radius:8px}}
.cat{{margin:10px 0}}.cat b{{display:block;font-size:13px;text-transform:uppercase;letter-spacing:.04em;margin-bottom:6px;opacity:.7}}
.chips{{display:flex;flex-wrap:wrap;gap:6px}}.chip{{border:1.5px solid #d6d4ea;background:#fff;border-radius:999px;padding:5px 11px;font-size:13px;cursor:pointer;color:inherit}}
.chip[aria-pressed=true]{{background:#1e1a6b;color:#fff;border-color:#1e1a6b}}.colores{{display:flex;flex-wrap:wrap;gap:10px;margin-top:6px;font-size:13px}}
main{{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:20px}}
figure{{margin:0;background:#fff;border-radius:16px;padding:16px;text-align:center}}figure svg{{width:100%;height:auto}}figcaption{{font-weight:600;margin:4px 0 8px}}label{{font-size:13px;margin:0 4px}}
</style>
<h1>Animales y objetos</h1>
<section class="probador">
  <div id="vista"></div>
  <div>
    <label style="margin:0">Animal <select id="modelo"></select></label>
    <div class="colores" id="col-animal"></div>
    {"".join(f'<div class="cat" data-cat="{c}"><b>{n}</b><div class="chips"></div><div class="colores"></div></div>' for c, n in cats)}
  </div>
</section>
<h2>Animales (colores editables)</h2>
<main>{tarjetas}</main>
<script>
const M={json.dumps(modelos, ensure_ascii=False)};
const O={json.dumps(objetos, ensure_ascii=False)};
const REGLAS={json.dumps(reglas_obj)};
const sel={{cabeza:null,cara:null,cuello:null,cuerpo:null}}, colA={{}}, colO={{}};
const $=s=>document.querySelector(s);
Object.entries(M).forEach(([id,m])=>$('#modelo').add(new Option(m.nombre,id)));
function pintar(){{
  const id=$('#modelo').value, m=M[id];
  let s=m.svg.replace('</style>',REGLAS+'</style>');
  const act=Object.values(sel).filter(Boolean).sort((a,b)=>O[a].orden-O[b].orden);
  const det=act.map(k=>O[k].detras).join(''), del=act.map(k=>O[k].delante).join('');
  s=s.replace('</defs>','</defs>'+det).replace(/<\\/svg>\\s*$/,del+'</svg>');
  $('#vista').innerHTML=s;
  const svg=$('#vista svg');
  Object.entries(colA[id]||{{}}).forEach(([k,v])=>svg.style.setProperty(k,v));
  act.forEach(k=>Object.entries(colO[k]||{{}}).forEach(([v,c])=>svg.querySelectorAll('#obj-'+k+',#obj-'+k+'-detras').forEach(g=>g.style.setProperty(v,c))));
}}
function selectorColor(cont,nombre,valor,fn){{
  const l=document.createElement('label');l.textContent=nombre+' ';const i=document.createElement('input');i.type='color';i.value=valor;i.oninput=()=>fn(i.value);l.append(i);cont.append(l);
}}
function coloresAnimal(){{
  const id=$('#modelo').value,c=$('#col-animal');c.innerHTML='';
  const nom={{'--pelo':'Pelo','--pico':'Pico/nariz','--acento':'Acento'}};
  Object.entries(M[id].colores).forEach(([k,v])=>selectorColor(c,nom[k],(colA[id]||{{}})[k]||v.trim(),x=>{{(colA[id]=colA[id]||{{}})[k]=x;pintar();}}));
}}
function coloresObjeto(cat){{
  const c=document.querySelector(`.cat[data-cat=${{cat}}] .colores`);c.innerHTML='';const k=sel[cat];if(!k)return;
  Object.entries(O[k].colores).forEach(([v,def],i)=>selectorColor(c,i?'Color 2':'Color 1',(colO[k]||{{}})[v]||def,x=>{{(colO[k]=colO[k]||{{}})[v]=x;pintar();}}));
}}
document.querySelectorAll('.cat').forEach(div=>{{
  const cat=div.dataset.cat,chips=div.querySelector('.chips');
  const mk=(k,n)=>{{const b=document.createElement('button');b.className='chip';b.textContent=n;b.setAttribute('aria-pressed',sel[cat]===k);
    b.onclick=()=>{{sel[cat]=k;chips.querySelectorAll('.chip').forEach(x=>x.setAttribute('aria-pressed',x===b));coloresObjeto(cat);pintar();}};chips.append(b);}};
  mk(null,'Ninguno');Object.entries(O).filter(([,o])=>o.categoria===cat).forEach(([k,o])=>mk(k,o.nombre));
}});
$('#modelo').onchange=()=>{{coloresAnimal();pintar();}};
sel.cabeza='chullo';sel.cuerpo='poncho';
document.querySelectorAll('.cat').forEach(d=>d.querySelectorAll('.chip').forEach(b=>{{if(b.textContent===(sel[d.dataset.cat]&&O[sel[d.dataset.cat]].nombre))b.click();}}));
$('#modelo').value='alpaca';coloresAnimal();pintar();
document.querySelectorAll('main input[type=color]').forEach(i=>i.oninput=()=>i.closest('figure').querySelector('svg').style.setProperty(i.dataset.v,i.value));
</script>'''


if __name__ == "__main__":
    with open(os.path.join(AQUI, "galeria.html"), "w") as f:
        f.write(galeria())
    print("galería ok")
