"""Genera las razas de pingüino en el mismo estilo. Colores editables: --pelo, --pico, --acento."""
import os
import re

AQUI = os.path.dirname(os.path.abspath(__file__))
NAVY = "#1e1a6b"

CUERPO = "M215 560 C205 470 200 390 222 320 C245 250 310 228 370 228 C440 228 500 250 515 320 C530 390 525 470 520 560 C520 600 460 616 370 616 C280 616 215 600 215 560 Z"
CARA_ALTA = "M370 302 C350 270 298 262 264 290 C236 316 232 380 236 450 C240 520 242 580 246 630 L496 630 C498 580 500 520 502 450 C504 380 500 316 476 290 C442 262 390 270 370 302 Z"
CARA_BAJA = "M240 480 C262 436 320 420 370 420 C420 420 478 436 500 480 C502 540 500 590 496 630 L246 630 C242 590 238 540 240 480 Z"
COPETE_HOJA = "M386 238 C368 228 352 212 362 202 C372 193 390 206 398 220 C406 204 426 196 436 206 C444 218 428 232 410 238 Z"
COPETE_PUAS = "M356 240 L346 196 L372 222 L382 182 L398 220 L424 190 L416 240 Z"

ESTILO = """  <style>
    .pelo        { fill: var(--pelo); }
    .pelo-trazo  { stroke: var(--pelo); fill: none; stroke-linecap: round; }
    .pelo-claro  { fill: color-mix(in srgb, var(--pelo) 65%, white); }
    .pico        { fill: var(--pico); }
    .pico-oscuro { fill: color-mix(in srgb, var(--pico) 78%, black); }
    .acento      { fill: var(--acento); }
    .acento-suave{ fill: color-mix(in srgb, var(--acento) 40%, white); }
    .linea       { stroke: #1e1a6b; stroke-width: 8; stroke-linejoin: round; stroke-linecap: round; }
  </style>"""


def ojos(anillo=None, iris=None):
    out = []
    for cx, cy in ((318, 352), (440, 355)):
        if anillo:  # anillo blanco grueso (Adelia) o fino (cabezas oscuras)
            out.append(f'<circle cx="{cx}" cy="{cy}" r="{anillo}" fill="#fff"/>')
        if iris:
            out.append(f'<circle cx="{cx}" cy="{cy}" r="24" fill="{iris}" stroke="{NAVY}" stroke-width="3"/>')
            out.append(f'<circle cx="{cx+1}" cy="{cy+2}" r="13" fill="{NAVY}"/>')
        else:
            out.append(f'<circle cx="{cx}" cy="{cy}" r="24" fill="{NAVY}"/>')
        out.append(f'<circle cx="{cx-9}" cy="{cy-9}" r="8" fill="#fff"/>')
        out.append(f'<circle cx="{cx+9}" cy="{cy+10}" r="3.5" fill="#fff"/>')
    return "\n    ".join(out)


def espejo(d, eje=379):
    """Refleja un path simple (sólo pares x y numéricos) sobre x=eje."""
    toks, out, i = re.findall(r"[A-Za-z]|-?[\d.]+", d), [], 0
    while i < len(toks):
        t = toks[i]
        if t.isalpha():
            out.append(t); i += 1
        else:
            out.append(f"{2*eje - float(t):g}"); out.append(toks[i + 1]); i += 2
    return " ".join(out)


CRESTA = "M336 326 C308 314 268 300 214 286 C238 300 236 302 206 310 C236 314 240 318 214 334 C258 326 290 330 334 338 Z"
MANCHA_PAPUA = "M282 322 C290 300 322 294 344 310 C328 314 312 318 294 328 Z"

RAZAS = [
    dict(id="clasico", nombre="Clásico", pelo="#7d7d8f", pico="#f5a623", acento="#f5a623",
         cara=CARA_ALTA, copete=COPETE_HOJA, ojos=ojos()),
    dict(id="emperador", nombre="Emperador", pelo="#2b2d42", pico="#f28c28", acento="#ffb627",
         cara=CARA_BAJA, copete=COPETE_HOJA, ojos=ojos(anillo=27),
         sobre_cara=f'''<path class="acento-suave" d="M262 452 C300 428 440 428 478 452 C440 440 300 440 262 452 Z"/>
    <path class="acento" d="M226 360 C250 370 268 410 262 452 C250 440 236 420 228 400 Z"/>
    <path class="acento" d="M514 360 C490 370 472 410 478 452 C490 440 504 420 512 400 Z"/>'''),
    dict(id="adelia", nombre="Adelia", pelo="#1f2233", pico="#3d3d4e", acento="#ffffff",
         cara=CARA_BAJA, copete=COPETE_HOJA, ojos=ojos(anillo=34)),
    dict(id="barbijo", nombre="Barbijo", pelo="#3b3f4f", pico="#2a2a36", acento="#ffffff",
         cara=CARA_ALTA, copete=COPETE_HOJA, ojos=ojos(),
         sobre_cara='<path class="pelo-trazo" stroke-width="7" d="M250 392 C298 452 452 456 500 394"/>'),
    dict(id="papua", nombre="Papúa", pelo="#2f3445", pico="#ff6a3d", acento="#ffffff",
         cara=CARA_BAJA, copete=COPETE_HOJA, ojos=ojos(anillo=27),
         sobre_cara=f'''<path fill="#fff" d="{MANCHA_PAPUA}"/>
    <path fill="#fff" d="{espejo(MANCHA_PAPUA)}"/>'''),
    dict(id="penacho", nombre="Penacho amarillo", pelo="#2a2d3a", pico="#e85d2a", acento="#ffd23f",
         cara=CARA_BAJA, copete=COPETE_PUAS, ojos=ojos(iris="#d62839"),
         encima=f'''<path class="acento" stroke="{NAVY}" stroke-width="4" stroke-linejoin="round" d="{CRESTA}"/>
  <path class="acento" stroke="{NAVY}" stroke-width="4" stroke-linejoin="round" d="{espejo(CRESTA)}"/>'''),
    dict(id="magallanes", nombre="Magallanes", pelo="#3a3a48", pico="#4b4b58", acento="#ffffff",
         cara=CARA_ALTA, copete=COPETE_HOJA, ojos=ojos(),
         sobre_cara='''<path class="pelo-trazo" stroke-width="18" d="M232 500 C290 566 450 566 508 500"/>
    <path class="pelo-trazo" stroke-width="8" d="M236 548 C290 600 450 600 504 548"/>'''),
]


def svg(r, ids=""):
    p = ids or r["id"]
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--pelo:{r['pelo']};--pico:{r['pico']};--acento:{r['acento']}">
{ESTILO}
  <defs><clipPath id="{p}-clip"><path id="{p}-cuerpo" d="{CUERPO}"/></clipPath></defs>
  <path class="pelo linea" d="{r['copete']}"/>
  <g id="aleta-izq">
    <path class="pelo linea" d="M248 445 C212 428 172 385 166 342 C162 318 180 310 202 322 C238 342 258 372 264 402 Z"/>
    <path class="pelo-claro" d="M200 332 C222 350 240 380 246 420 C226 400 204 370 196 340 C195 333 197 330 200 332 Z"/>
  </g>
  <g id="aleta-der">
    <path class="pelo linea" d="M502 448 C540 468 576 508 586 544 C591 566 576 574 554 563 C530 550 512 532 500 522 Z"/>
    <path class="pelo-claro" d="M520 480 C545 500 566 526 574 550 C556 540 536 520 522 500 Z"/>
  </g>
  <use href="#{p}-cuerpo" class="pelo"/>
  <g clip-path="url(#{p}-clip)">
    <path class="pelo-claro" d="M268 272 C310 246 432 240 488 272 C440 260 320 260 268 272 Z"/>
    <path id="cara" fill="#fff" d="{r['cara']}"/>
    {r.get('sobre_cara', '')}
    <ellipse cx="370" cy="618" rx="170" ry="30" fill="#e2e2ee"/>
  </g>
  <use href="#{p}-cuerpo" fill="none" class="linea"/>
  <g id="ojos">
    {r['ojos']}
  </g>
  {r.get('encima', '')}
  <g id="pico">
    <path class="pico linea" stroke-width="6" d="M346 374 C348 360 408 358 412 374 C414 394 396 408 379 408 C361 408 344 394 346 374 Z"/>
    <path class="pico-oscuro" d="M352 390 C362 402 396 402 406 390 C400 402 390 405 379 405 C366 405 356 400 352 390 Z"/>
    <path fill="#f06a7a" stroke="{NAVY}" stroke-width="3" stroke-linejoin="round" d="M368 386 C374 380 386 380 392 386 C388 395 372 395 368 386 Z"/>
  </g>
</svg>
'''


for r in RAZAS:
    with open(os.path.join(AQUI, f"pinguino-{r['id']}.svg"), "w") as f:
        f.write(svg(r))

# Hoja de contacto (una sola imagen para revisar)
celdas = []
for i, r in enumerate(RAZAS):
    x, y = (i % 3) * 480, (i // 3) * 520
    interior = svg(r).replace('<svg xmlns="http://www.w3.org/2000/svg"', f'<svg x="{x}" y="{y}"')
    celdas.append(interior + f'<text x="{x+235}" y="{y+500}" text-anchor="middle" font-family="Helvetica" font-size="28" fill="{NAVY}">{r["nombre"]}</text>')
with open(os.path.join(AQUI, "_hoja.svg"), "w") as f:
    f.write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1560 1560" width="1560" height="1560"><rect width="1560" height="1560" fill="#fff"/>{"".join(celdas)}</svg>')

# Galería con selectores de color
tarjetas = "".join(
    f'''<figure>{svg(r)}<figcaption>{r['nombre']}</figcaption>
<label>Pelo <input type="color" data-v="--pelo" value="{r['pelo']}"></label>
<label>Pico <input type="color" data-v="--pico" value="{r['pico']}"></label>
{'<label>Acento <input type="color" data-v="--acento" value="' + r['acento'] + '"></label>' if r['id'] in ('emperador', 'penacho') else ''}</figure>'''
    for r in RAZAS)
with open(os.path.join(AQUI, "galeria.html"), "w") as f:
    f.write(f'''<!doctype html><meta charset="utf-8"><title>Pingüinos</title>
<style>body{{font-family:system-ui;margin:0;padding:24px;background:#f6f6fa}}main{{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:20px}}
figure{{margin:0;background:#fff;border-radius:16px;padding:16px;text-align:center}}svg{{width:100%;height:auto}}figcaption{{font-weight:600;margin:4px 0 8px}}label{{font-size:13px;margin:0 6px}}</style>
<main>{tarjetas}</main>
<script>document.querySelectorAll('input[type=color]').forEach(i=>i.oninput=()=>i.closest('figure').querySelector('svg').style.setProperty(i.dataset.v,i.value))</script>''')
print("ok")
