// Generado por output/animales/a_swift.py — no editar a mano.
// Animales: clave = id. Objetos: clave = nombre de archivo sin extensión.

enum AvatarArtwork {
    static let animals: [AvatarAnimal] = [
        .init(id: "perro", name: "Perro", fur: "#d9a066", nose: "#2b2238", mark: "#8a5a3b"),
        .init(id: "gato", name: "Gato", fur: "#f4a259", nose: "#f28fa0", mark: "#c8652a"),
        .init(id: "leon", name: "León", fur: "#f2c14e", nose: "#7a4a3a", mark: "#c8641e"),
        .init(id: "tigre", name: "Tigre", fur: "#f5892a", nose: "#e86f7f", mark: "#2b2233"),
        .init(id: "zorro", name: "Zorro", fur: "#ef6f2e", nose: "#2b2238", mark: "#3a2c3c"),
        .init(id: "oso", name: "Oso", fur: "#8d5b3e", nose: "#2b2238", mark: "#e3b98f"),
        .init(id: "panda", name: "Panda", fur: "#f7f7fb", nose: "#2b2d42", mark: "#2b2d42"),
        .init(id: "conejo", name: "Conejo", fur: "#e8e3f2", nose: "#f28fa0", mark: "#f6a6c1"),
        .init(id: "mapache", name: "Mapache", fur: "#9a9cae", nose: "#2b2238", mark: "#34364a"),
        .init(id: "koala", name: "Koala", fur: "#a3a8b8", nose: "#3b3848", mark: "#f4f4f8"),
        .init(id: "alpaca", name: "Alpaca", fur: "#f5ead8", nose: "#8a6a5a", mark: "#e0457b"),
        .init(id: "cerdito", name: "Cerdito", fur: "#f9b8c9", nose: "#f58fab", mark: "#e56f93")
    ]

    static let items: [AvatarItem] = [
        .init(id: "corona", name: "Corona", zone: .cabeza, color: "#ffc93c", color2: "#e63946", layers: [.init(svg: "objeto-corona", z: 4)]),
        .init(id: "gorro-fiesta", name: "Gorro de fiesta", zone: .cabeza, color: "#4cc9f0", color2: "#ff5d8f", layers: [.init(svg: "objeto-gorro-fiesta", z: 4)]),
        .init(id: "sombrero-copa", name: "Sombrero de copa", zone: .cabeza, color: "#2b2d42", color2: "#e63946", layers: [.init(svg: "objeto-sombrero-copa", z: 4)]),
        .init(id: "gorro-mago", name: "Gorro de mago", zone: .cabeza, color: "#5a4fcf", color2: "#ffd23f", layers: [.init(svg: "objeto-gorro-mago", z: 4)]),
        .init(id: "chullo", name: "Chullo andino", zone: .cabeza, color: "#d62839", color2: "#ffd23f", layers: [.init(svg: "objeto-chullo", z: 4)]),
        .init(id: "gorra", name: "Gorra", zone: .cabeza, color: "#2a9d8f", color2: "#f4f1de", layers: [.init(svg: "objeto-gorra", z: 4)]),
        .init(id: "gorro-chef", name: "Gorro de chef", zone: .cabeza, color: "#ffffff", color2: "#e63946", layers: [.init(svg: "objeto-gorro-chef", z: 4)]),
        .init(id: "gorro-navidad", name: "Gorro navideño", zone: .cabeza, color: "#e63946", color2: "#ffffff", layers: [.init(svg: "objeto-gorro-navidad", z: 4)]),
        .init(id: "diadema-flor", name: "Diadema con flor", zone: .cabeza, color: "#9b5de5", color2: "#ff8fab", layers: [.init(svg: "objeto-diadema-flor", z: 4)]),
        .init(id: "lentes", name: "Lentes redondos", zone: .cara, color: "#c9a227", color2: "#ffffff", layers: [.init(svg: "objeto-lentes", z: 3)]),
        .init(id: "gafas-sol", name: "Gafas de sol", zone: .cara, color: "#2b2d42", color2: "#ff5d8f", layers: [.init(svg: "objeto-gafas-sol", z: 3)]),
        .init(id: "bufanda", name: "Bufanda", zone: .cuello, color: "#e63946", color2: "#f4f1de", layers: [.init(svg: "objeto-bufanda", z: 2)]),
        .init(id: "pajarita", name: "Pajarita", zone: .cuello, color: "#e63946", color2: "#ffffff", layers: [.init(svg: "objeto-pajarita", z: 2)]),
        .init(id: "collar-placa", name: "Collar con placa", zone: .cuello, color: "#e63946", color2: "#ffc93c", layers: [.init(svg: "objeto-collar-placa", z: 2)]),
        .init(id: "collar-flores", name: "Collar de flores", zone: .cuello, color: "#ff8fab", color2: "#ffd23f", layers: [.init(svg: "objeto-collar-flores", z: 2)]),
        .init(id: "tunica-mago", name: "Túnica de mago", zone: .cuerpo, color: "#5a4fcf", color2: "#ffd23f", layers: [.init(svg: "objeto-tunica-mago", z: 1)]),
        .init(id: "poncho", name: "Poncho andino", zone: .cuerpo, color: "#d62839", color2: "#ffd23f", layers: [.init(svg: "objeto-poncho", z: 1)]),
        .init(id: "capa-heroe", name: "Capa de héroe", zone: .cuerpo, color: "#e63946", color2: "#ffd23f", layers: [.init(svg: "objeto-capa-heroe-detras", z: -1), .init(svg: "objeto-capa-heroe", z: 1)])
    ]

    static let svg: [String: String] = [
        "perro": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--pelo:#d9a066;--pico:#2b2238;--acento:#8a5a3b">
  <defs><clipPath id="perro-clip"><path id="perro-cuerpo" d="M215 560 C205 470 200 390 222 320 C245 250 310 228 370 228 C440 228 500 250 515 320 C530 390 525 470 520 560 C520 600 460 616 370 616 C280 616 215 600 215 560 Z"/></clipPath></defs>
  <g id="detras">
  <path class="trazo" stroke-width="28" d="M258 590 C222 598 194 584 182 556"/><path class="pelo-trazo" stroke-width="20" d="M258 590 C222 598 194 584 182 556"/>
  </g>
  <g id="aleta-izq">
    <path class="trazo" stroke-width="60" d="M244 408 L180 322"/><path class="pelo-trazo" stroke-width="52" d="M244 408 L180 322"/>
    <ellipse class="acento-suave" cx="181" cy="328" rx="10" ry="8"/>
    <circle class="acento-suave" cx="167" cy="314" r="4.5"/><circle class="acento-suave" cx="179" cy="308" r="4.5"/><circle class="acento-suave" cx="192" cy="313" r="4.5"/>
  </g>
  <g id="aleta-der">
    <path class="trazo" stroke-width="60" d="M502 470 L558 544"/><path class="pelo-trazo" stroke-width="52" d="M502 470 L558 544"/>
  </g>
  <use href="#perro-cuerpo" class="pelo"/>
  <g clip-path="url(#perro-clip)">
    <path class="pelo-claro" d="M268 272 C310 246 432 240 488 272 C440 260 320 260 268 272 Z"/>
    <g id="cara"><ellipse fill="#fff" cx="379" cy="404" rx="58" ry="40"/><ellipse fill="#fff" cx="370" cy="574" rx="122" ry="104"/><ellipse class="acento" cx="442" cy="346" rx="46" ry="42"/></g>
    <ellipse cx="370" cy="618" rx="170" ry="30" fill="#e2e2ee"/>
  </g>
  <use href="#perro-cuerpo" fill="none" class="linea"/>
  <g id="ojos">
    <circle cx="318" cy="352" r="24" fill="#1e1a6b"/>
    <circle cx="309" cy="343" r="8" fill="#fff"/>
    <circle cx="327" cy="362" r="3.5" fill="#fff"/>
    <circle cx="440" cy="355" r="24" fill="#1e1a6b"/>
    <circle cx="431" cy="346" r="8" fill="#fff"/>
    <circle cx="449" cy="365" r="3.5" fill="#fff"/>
  </g>
  <g id="encima"><path class="acento linea"  d="M270 244 C236 240 208 278 206 330 C204 374 222 400 246 394 C264 388 274 352 282 302 C286 276 286 254 270 244 Z"/>
  <path class="acento linea"  d="M 488 244 C 522 240 550 278 552 330 C 554 374 536 400 512 394 C 494 388 484 352 476 302 C 472 276 472 254 488 244 Z"/></g>
  <g id="pico"><path fill="#f06a7a" stroke="#1e1a6b" stroke-width="4" stroke-linejoin="round" d="M366 420 C366 446 392 446 392 420 C384 424 374 424 366 420 Z"/><path d="M379 425 L379 436" stroke="#d24a5c" stroke-width="3" stroke-linecap="round"/><path class="pico linea" stroke-width="5" d="M354 384 C354 368 404 368 404 384 C404 398 392 406 379 406 C366 406 354 398 354 384 Z"/><ellipse cx="368" cy="382" rx="6" ry="3.5" fill="#fff" opacity=".7"/><path class="trazo" stroke-width="5" d="M379 406 L379 414 M379 414 C372.4 425 357 425 353 416 M379 414 C385.6 425 401 425 405 416"/></g>
</svg>
"""##,
        "gato": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--pelo:#f4a259;--pico:#f28fa0;--acento:#c8652a">
  <defs><clipPath id="gato-clip"><path id="gato-cuerpo" d="M215 560 C205 470 200 390 222 320 C245 250 310 228 370 228 C440 228 500 250 515 320 C530 390 525 470 520 560 C520 600 460 616 370 616 C280 616 215 600 215 560 Z"/></clipPath></defs>
  <g id="detras">
  <path class="pelo linea"  d="M238 312 C232 262 236 214 250 186 C282 196 316 218 340 244 Z"/>
  <path class="pelo linea"  d="M 512 312 C 518 262 514 214 500 186 C 468 196 434 218 410 244 Z"/>
  <path class="acento-suave"  d="M254 292 C250 256 254 226 262 208 C284 218 304 232 320 248 Z"/>
  <path class="acento-suave"  d="M 496 292 C 500 256 496 226 488 208 C 466 218 446 232 430 248 Z"/><path class="trazo" stroke-width="26" d="M262 590 C210 604 168 580 162 536 C158 506 172 486 188 476"/><path class="pelo-trazo" stroke-width="18" d="M262 590 C210 604 168 580 162 536 C158 506 172 486 188 476"/>
  </g>
  <g id="aleta-izq">
    <path class="trazo" stroke-width="60" d="M244 408 L180 322"/><path class="pelo-trazo" stroke-width="52" d="M244 408 L180 322"/>
    <ellipse class="acento-suave" cx="181" cy="328" rx="10" ry="8"/>
    <circle class="acento-suave" cx="167" cy="314" r="4.5"/><circle class="acento-suave" cx="179" cy="308" r="4.5"/><circle class="acento-suave" cx="192" cy="313" r="4.5"/>
  </g>
  <g id="aleta-der">
    <path class="trazo" stroke-width="60" d="M502 470 L558 544"/><path class="pelo-trazo" stroke-width="52" d="M502 470 L558 544"/>
  </g>
  <use href="#gato-cuerpo" class="pelo"/>
  <g clip-path="url(#gato-clip)">
    <path class="pelo-claro" d="M268 272 C310 246 432 240 488 272 C440 260 320 260 268 272 Z"/>
    <g id="cara"><ellipse fill="#fff" cx="379" cy="402" rx="46" ry="32"/><ellipse fill="#fff" cx="370" cy="574" rx="122" ry="104"/><path class="acento" d="M352 226 L362 276 L372 226 Z M372 222 L379 286 L386 222 Z M386 226 L396 276 L406 226 Z"/><path class="acento"  d="M200 420 L258 432 L200 446 Z M200 470 L250 480 L200 494 Z"/>
  <path class="acento"  d="M 540 420 L 482 432 L 540 446 Z M 540 470 L 490 480 L 540 494 Z"/></g>
    <ellipse cx="370" cy="618" rx="170" ry="30" fill="#e2e2ee"/>
  </g>
  <use href="#gato-cuerpo" fill="none" class="linea"/>
  <g id="ojos">
    <circle cx="318" cy="352" r="24" fill="#8bc34a" stroke="#1e1a6b" stroke-width="3"/>
    <circle cx="319" cy="354" r="13" fill="#1e1a6b"/>
    <circle cx="309" cy="343" r="8" fill="#fff"/>
    <circle cx="327" cy="362" r="3.5" fill="#fff"/>
    <circle cx="440" cy="355" r="24" fill="#8bc34a" stroke="#1e1a6b" stroke-width="3"/>
    <circle cx="441" cy="357" r="13" fill="#1e1a6b"/>
    <circle cx="431" cy="346" r="8" fill="#fff"/>
    <circle cx="449" cy="365" r="3.5" fill="#fff"/>
  </g>
  <g id="encima"><path class="trazo" stroke-width="4" d="M306 398 L248 386 M306 410 L246 414 M 452 398 L 510 386 M 452 410 L 512 414"/></g>
  <g id="pico"><path class="pico linea" stroke-width="5" d="M364 386 C364 377 394 377 394 386 C394 394 386 400 379 400 C372 400 364 394 364 386 Z"/><ellipse cx="372" cy="384" rx="6" ry="3.5" fill="#fff" opacity=".7"/><path class="trazo" stroke-width="5" d="M379 400 L379 408 M379 408 C374.2 417 363 417 359 410 M379 408 C383.8 417 395 417 399 410"/></g>
</svg>
"""##,
        "leon": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--pelo:#f2c14e;--pico:#7a4a3a;--acento:#c8641e">
  <defs><clipPath id="leon-clip"><path id="leon-cuerpo" d="M215 560 C205 470 200 390 222 320 C245 250 310 228 370 228 C440 228 500 250 515 320 C530 390 525 470 520 560 C520 600 460 616 370 616 C280 616 215 600 215 560 Z"/></clipPath></defs>
  <g id="detras">
  <circle class="trazo" fill="#1e1a6b" stroke-width="16" cx="213" cy="412" r="34"/><circle class="trazo" fill="#1e1a6b" stroke-width="16" cx="201" cy="373" r="34"/><circle class="trazo" fill="#1e1a6b" stroke-width="16" cx="203" cy="333" r="34"/><circle class="trazo" fill="#1e1a6b" stroke-width="16" cx="217" cy="295" r="34"/><circle class="trazo" fill="#1e1a6b" stroke-width="16" cx="244" cy="262" r="34"/><circle class="trazo" fill="#1e1a6b" stroke-width="16" cx="281" cy="236" r="34"/><circle class="trazo" fill="#1e1a6b" stroke-width="16" cx="325" cy="220" r="34"/><circle class="trazo" fill="#1e1a6b" stroke-width="16" cx="372" cy="214" r="34"/><circle class="trazo" fill="#1e1a6b" stroke-width="16" cx="419" cy="220" r="34"/><circle class="trazo" fill="#1e1a6b" stroke-width="16" cx="463" cy="236" r="34"/><circle class="trazo" fill="#1e1a6b" stroke-width="16" cx="500" cy="262" r="34"/><circle class="trazo" fill="#1e1a6b" stroke-width="16" cx="527" cy="295" r="34"/><circle class="trazo" fill="#1e1a6b" stroke-width="16" cx="541" cy="333" r="34"/><circle class="trazo" fill="#1e1a6b" stroke-width="16" cx="543" cy="373" r="34"/><circle class="trazo" fill="#1e1a6b" stroke-width="16" cx="531" cy="412" r="34"/><circle class="acento" cx="213" cy="412" r="34"/><circle class="acento" cx="201" cy="373" r="34"/><circle class="acento" cx="203" cy="333" r="34"/><circle class="acento" cx="217" cy="295" r="34"/><circle class="acento" cx="244" cy="262" r="34"/><circle class="acento" cx="281" cy="236" r="34"/><circle class="acento" cx="325" cy="220" r="34"/><circle class="acento" cx="372" cy="214" r="34"/><circle class="acento" cx="419" cy="220" r="34"/><circle class="acento" cx="463" cy="236" r="34"/><circle class="acento" cx="500" cy="262" r="34"/><circle class="acento" cx="527" cy="295" r="34"/><circle class="acento" cx="541" cy="333" r="34"/><circle class="acento" cx="543" cy="373" r="34"/><circle class="acento" cx="531" cy="412" r="34"/><circle class="pelo linea" cx="282" cy="240" r="30"/><circle class="pelo linea" cx="468" cy="240" r="30"/><circle class="acento-suave" cx="280" cy="236" r="16"/><circle class="acento-suave" cx="470" cy="236" r="16"/><path class="trazo" stroke-width="22" d="M262 592 C214 606 180 596 170 566"/><path class="pelo-trazo" stroke-width="14" d="M262 592 C214 606 180 596 170 566"/><circle class="trazo" fill="#1e1a6b" stroke-width="12" cx="166" cy="556" r="16"/><circle class="trazo" fill="#1e1a6b" stroke-width="12" cx="158" cy="544" r="12"/><circle class="trazo" fill="#1e1a6b" stroke-width="12" cx="174" cy="546" r="11"/><circle class="acento" cx="166" cy="556" r="16"/><circle class="acento" cx="158" cy="544" r="12"/><circle class="acento" cx="174" cy="546" r="11"/>
  </g>
  <g id="aleta-izq">
    <path class="trazo" stroke-width="60" d="M244 408 L180 322"/><path class="pelo-trazo" stroke-width="52" d="M244 408 L180 322"/>
    <ellipse class="acento-suave" cx="181" cy="328" rx="10" ry="8"/>
    <circle class="acento-suave" cx="167" cy="314" r="4.5"/><circle class="acento-suave" cx="179" cy="308" r="4.5"/><circle class="acento-suave" cx="192" cy="313" r="4.5"/>
  </g>
  <g id="aleta-der">
    <path class="trazo" stroke-width="60" d="M502 470 L558 544"/><path class="pelo-trazo" stroke-width="52" d="M502 470 L558 544"/>
  </g>
  <use href="#leon-cuerpo" class="pelo"/>
  <g clip-path="url(#leon-clip)">
    <path class="pelo-claro" d="M268 272 C310 246 432 240 488 272 C440 260 320 260 268 272 Z"/>
    <g id="cara"><ellipse class="pelo-claro" cx="379" cy="404" rx="58" ry="40"/><ellipse class="pelo-claro" cx="370" cy="574" rx="122" ry="104"/></g>
    <ellipse cx="370" cy="618" rx="170" ry="30" fill="#e2e2ee"/>
  </g>
  <use href="#leon-cuerpo" fill="none" class="linea"/>
  <g id="ojos">
    <circle cx="318" cy="352" r="24" fill="#1e1a6b"/>
    <circle cx="309" cy="343" r="8" fill="#fff"/>
    <circle cx="327" cy="362" r="3.5" fill="#fff"/>
    <circle cx="440" cy="355" r="24" fill="#1e1a6b"/>
    <circle cx="431" cy="346" r="8" fill="#fff"/>
    <circle cx="449" cy="365" r="3.5" fill="#fff"/>
  </g>
  <g id="encima"><circle fill="#1e1a6b" cx="336" cy="402" r="3.5"/><circle fill="#1e1a6b" cx="422" cy="402" r="3.5"/><circle fill="#1e1a6b" cx="326" cy="412" r="3.5"/><circle fill="#1e1a6b" cx="432" cy="412" r="3.5"/><circle fill="#1e1a6b" cx="340" cy="416" r="3.5"/><circle fill="#1e1a6b" cx="418" cy="416" r="3.5"/></g>
  <g id="pico"><path class="pico linea" stroke-width="5" d="M354 384 C354 368 404 368 404 384 C404 398 392 406 379 406 C366 406 354 398 354 384 Z"/><ellipse cx="368" cy="382" rx="6" ry="3.5" fill="#fff" opacity=".7"/><path class="trazo" stroke-width="5" d="M379 406 L379 414 M379 414 C372.4 425 357 425 353 416 M379 414 C385.6 425 401 425 405 416"/></g>
</svg>
"""##,
        "tigre": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--pelo:#f5892a;--pico:#e86f7f;--acento:#2b2233">
  <defs><clipPath id="tigre-clip"><path id="tigre-cuerpo" d="M215 560 C205 470 200 390 222 320 C245 250 310 228 370 228 C440 228 500 250 515 320 C530 390 525 470 520 560 C520 600 460 616 370 616 C280 616 215 600 215 560 Z"/></clipPath></defs>
  <g id="detras">
  <circle class="pelo linea" cx="274" cy="246" r="32"/><circle class="pelo linea" cx="476" cy="246" r="32"/><circle cx="272" cy="244" r="15" fill="#fff"/><circle cx="478" cy="244" r="15" fill="#fff"/><path class="trazo" stroke-width="28" d="M262 590 C210 604 168 580 162 536 C158 506 172 486 188 476"/><path class="pelo-trazo" stroke-width="20" d="M262 590 C210 604 168 580 162 536 C158 506 172 486 188 476"/><path class="acento-trazo" stroke-width="20" stroke-dasharray="12 14" d="M262 590 C210 604 168 580 162 536 C158 506 172 486 188 476"/>
  </g>
  <g id="aleta-izq">
    <path class="trazo" stroke-width="60" d="M244 408 L180 322"/><path class="pelo-trazo" stroke-width="52" d="M244 408 L180 322"/>
    <ellipse class="acento-suave" cx="181" cy="328" rx="10" ry="8"/>
    <circle class="acento-suave" cx="167" cy="314" r="4.5"/><circle class="acento-suave" cx="179" cy="308" r="4.5"/><circle class="acento-suave" cx="192" cy="313" r="4.5"/>
  </g>
  <g id="aleta-der">
    <path class="trazo" stroke-width="60" d="M502 470 L558 544"/><path class="pelo-trazo" stroke-width="52" d="M502 470 L558 544"/>
  </g>
  <use href="#tigre-cuerpo" class="pelo"/>
  <g clip-path="url(#tigre-clip)">
    <path class="pelo-claro" d="M268 272 C310 246 432 240 488 272 C440 260 320 260 268 272 Z"/>
    <g id="cara"><ellipse fill="#fff" cx="379" cy="404" rx="64" ry="42"/><ellipse fill="#fff" cx="370" cy="574" rx="122" ry="104"/><path class="acento" d="M356 228 L366 272 L376 228 Z M374 226 L379 262 L384 226 Z M384 228 L392 272 L402 228 Z"/><path class="acento"  d="M198 380 L262 392 L198 404 Z M198 432 L252 440 L198 454 Z M198 506 L244 514 L198 526 Z"/>
  <path class="acento"  d="M 542 380 L 478 392 L 542 404 Z M 542 432 L 488 440 L 542 454 Z M 542 506 L 496 514 L 542 526 Z"/><ellipse cx="300" cy="316" rx="14" ry="8" fill="#fff"/><ellipse cx="458" cy="318" rx="14" ry="8" fill="#fff"/></g>
    <ellipse cx="370" cy="618" rx="170" ry="30" fill="#e2e2ee"/>
  </g>
  <use href="#tigre-cuerpo" fill="none" class="linea"/>
  <g id="ojos">
    <circle cx="318" cy="352" r="24" fill="#1e1a6b"/>
    <circle cx="309" cy="343" r="8" fill="#fff"/>
    <circle cx="327" cy="362" r="3.5" fill="#fff"/>
    <circle cx="440" cy="355" r="24" fill="#1e1a6b"/>
    <circle cx="431" cy="346" r="8" fill="#fff"/>
    <circle cx="449" cy="365" r="3.5" fill="#fff"/>
  </g>
  <g id="encima"><path class="trazo" stroke-width="4" d="M306 398 L248 386 M306 410 L246 414 M 452 398 L 510 386 M 452 410 L 512 414"/></g>
  <g id="pico"><path class="pico linea" stroke-width="5" d="M364 386 C364 377 394 377 394 386 C394 394 386 400 379 400 C372 400 364 394 364 386 Z"/><ellipse cx="372" cy="384" rx="6" ry="3.5" fill="#fff" opacity=".7"/><path class="trazo" stroke-width="5" d="M379 400 L379 408 M379 408 C374.2 417 363 417 359 410 M379 408 C383.8 417 395 417 399 410"/></g>
</svg>
"""##,
        "zorro": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--pelo:#ef6f2e;--pico:#2b2238;--acento:#3a2c3c">
  <defs><clipPath id="zorro-clip"><path id="zorro-cuerpo" d="M215 560 C205 470 200 390 222 320 C245 250 310 228 370 228 C440 228 500 250 515 320 C530 390 525 470 520 560 C520 600 460 616 370 616 C280 616 215 600 215 560 Z"/></clipPath></defs>
  <g id="detras">
  <path class="pelo linea"  d="M238 312 C232 262 236 214 250 186 C282 196 316 218 340 244 Z"/>
  <path class="pelo linea"  d="M 512 312 C 518 262 514 214 500 186 C 468 196 434 218 410 244 Z"/>
  <path class="acento-suave"  d="M254 292 C250 256 254 226 262 208 C284 218 304 232 320 248 Z"/>
  <path class="acento-suave"  d="M 496 292 C 500 256 496 226 488 208 C 466 218 446 232 430 248 Z"/>
  <path class="acento"  d="M250 186 C262 190 276 197 290 205 C278 208 262 212 244 222 C245 208 247 196 250 186 Z"/>
  <path class="acento"  d="M 500 186 C 488 190 474 197 460 205 C 472 208 488 212 506 222 C 505 208 503 196 500 186 Z"/><clipPath id="zorro-cola"><path d="M264 560 C222 536 168 536 148 578 C138 604 160 626 192 620 C222 614 252 604 268 594 Z"/></clipPath><path class="pelo linea" d="M264 560 C222 536 168 536 148 578 C138 604 160 626 192 620 C222 614 252 604 268 594 Z"/><g clip-path="url(#zorro-cola)"><ellipse cx="150" cy="604" rx="34" ry="40" fill="#fff"/></g><path class="trazo" stroke-width="8" fill="none" d="M264 560 C222 536 168 536 148 578 C138 604 160 626 192 620 C222 614 252 604 268 594"/>
  </g>
  <g id="aleta-izq">
    <path class="trazo" stroke-width="60" d="M244 408 L180 322"/><path class="pelo-trazo" stroke-width="52" d="M244 408 L180 322"/>
    <circle class="acento" cx="180" cy="322" r="22"/>
    <ellipse class="acento-suave" cx="181" cy="328" rx="10" ry="8"/>
    <circle class="acento-suave" cx="167" cy="314" r="4.5"/><circle class="acento-suave" cx="179" cy="308" r="4.5"/><circle class="acento-suave" cx="192" cy="313" r="4.5"/>
  </g>
  <g id="aleta-der">
    <path class="trazo" stroke-width="60" d="M502 470 L558 544"/><path class="pelo-trazo" stroke-width="52" d="M502 470 L558 544"/>
    <circle class="acento" cx="558" cy="544" r="22"/>
  </g>
  <use href="#zorro-cuerpo" class="pelo"/>
  <g clip-path="url(#zorro-clip)">
    <path class="pelo-claro" d="M268 272 C310 246 432 240 488 272 C440 260 320 260 268 272 Z"/>
    <g id="cara"><path fill="#fff" d="M200 372 C250 368 320 392 379 440 C438 392 508 368 540 372 L540 640 L200 640 Z"/></g>
    <ellipse cx="370" cy="618" rx="170" ry="30" fill="#e2e2ee"/>
  </g>
  <use href="#zorro-cuerpo" fill="none" class="linea"/>
  <g id="ojos">
    <circle cx="318" cy="352" r="24" fill="#1e1a6b"/>
    <circle cx="309" cy="343" r="8" fill="#fff"/>
    <circle cx="327" cy="362" r="3.5" fill="#fff"/>
    <circle cx="440" cy="355" r="24" fill="#1e1a6b"/>
    <circle cx="431" cy="346" r="8" fill="#fff"/>
    <circle cx="449" cy="365" r="3.5" fill="#fff"/>
  </g>
  <g id="encima"></g>
  <g id="pico"><path class="pico linea" stroke-width="5" d="M354 384 C354 368 404 368 404 384 C404 398 392 406 379 406 C366 406 354 398 354 384 Z"/><ellipse cx="368" cy="382" rx="6" ry="3.5" fill="#fff" opacity=".7"/><path class="trazo" stroke-width="5" d="M379 406 L379 414 M379 414 C372.4 425 357 425 353 416 M379 414 C385.6 425 401 425 405 416"/></g>
</svg>
"""##,
        "oso": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--pelo:#8d5b3e;--pico:#2b2238;--acento:#e3b98f">
  <defs><clipPath id="oso-clip"><path id="oso-cuerpo" d="M215 560 C205 470 200 390 222 320 C245 250 310 228 370 228 C440 228 500 250 515 320 C530 390 525 470 520 560 C520 600 460 616 370 616 C280 616 215 600 215 560 Z"/></clipPath></defs>
  <g id="detras">
  <circle class="pelo linea" cx="270" cy="248" r="40"/><circle class="pelo linea" cx="480" cy="248" r="40"/><circle class="acento-suave" cx="268" cy="244" r="22"/><circle class="acento-suave" cx="482" cy="244" r="22"/>
  </g>
  <g id="aleta-izq">
    <path class="trazo" stroke-width="60" d="M244 408 L180 322"/><path class="pelo-trazo" stroke-width="52" d="M244 408 L180 322"/>
    <ellipse class="acento-suave" cx="181" cy="328" rx="10" ry="8"/>
    <circle class="acento-suave" cx="167" cy="314" r="4.5"/><circle class="acento-suave" cx="179" cy="308" r="4.5"/><circle class="acento-suave" cx="192" cy="313" r="4.5"/>
  </g>
  <g id="aleta-der">
    <path class="trazo" stroke-width="60" d="M502 470 L558 544"/><path class="pelo-trazo" stroke-width="52" d="M502 470 L558 544"/>
  </g>
  <use href="#oso-cuerpo" class="pelo"/>
  <g clip-path="url(#oso-clip)">
    <path class="pelo-claro" d="M268 272 C310 246 432 240 488 272 C440 260 320 260 268 272 Z"/>
    <g id="cara"><ellipse class="acento" cx="379" cy="404" rx="58" ry="40"/><ellipse class="acento" cx="370" cy="574" rx="122" ry="104"/></g>
    <ellipse cx="370" cy="618" rx="170" ry="30" fill="#e2e2ee"/>
  </g>
  <use href="#oso-cuerpo" fill="none" class="linea"/>
  <g id="ojos">
    <circle cx="318" cy="352" r="24" fill="#1e1a6b"/>
    <circle cx="309" cy="343" r="8" fill="#fff"/>
    <circle cx="327" cy="362" r="3.5" fill="#fff"/>
    <circle cx="440" cy="355" r="24" fill="#1e1a6b"/>
    <circle cx="431" cy="346" r="8" fill="#fff"/>
    <circle cx="449" cy="365" r="3.5" fill="#fff"/>
  </g>
  <g id="encima"></g>
  <g id="pico"><path class="pico linea" stroke-width="5" d="M354 384 C354 368 404 368 404 384 C404 398 392 406 379 406 C366 406 354 398 354 384 Z"/><ellipse cx="368" cy="382" rx="6" ry="3.5" fill="#fff" opacity=".7"/><path class="trazo" stroke-width="5" d="M379 406 L379 414 M379 414 C372.4 425 357 425 353 416 M379 414 C385.6 425 401 425 405 416"/></g>
</svg>
"""##,
        "panda": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--pelo:#f7f7fb;--pico:#2b2d42;--acento:#2b2d42">
  <defs><clipPath id="panda-clip"><path id="panda-cuerpo" d="M215 560 C205 470 200 390 222 320 C245 250 310 228 370 228 C440 228 500 250 515 320 C530 390 525 470 520 560 C520 600 460 616 370 616 C280 616 215 600 215 560 Z"/></clipPath></defs>
  <g id="detras">
  <circle class="acento linea" cx="270" cy="248" r="40"/><circle class="acento linea" cx="480" cy="248" r="40"/>
  </g>
  <g id="aleta-izq">
    <path class="trazo" stroke-width="60" d="M244 408 L180 322"/><path class="acento-trazo" stroke-width="52" d="M244 408 L180 322"/>
    <ellipse class="acento-suave" cx="181" cy="328" rx="10" ry="8"/>
    <circle class="acento-suave" cx="167" cy="314" r="4.5"/><circle class="acento-suave" cx="179" cy="308" r="4.5"/><circle class="acento-suave" cx="192" cy="313" r="4.5"/>
  </g>
  <g id="aleta-der">
    <path class="trazo" stroke-width="60" d="M502 470 L558 544"/><path class="acento-trazo" stroke-width="52" d="M502 470 L558 544"/>
  </g>
  <use href="#panda-cuerpo" class="pelo"/>
  <g clip-path="url(#panda-clip)">
    <path class="pelo-claro" d="M268 272 C310 246 432 240 488 272 C440 260 320 260 268 272 Z"/>
    <g id="cara"><ellipse class="acento" cx="314" cy="356" rx="36" ry="46" transform="rotate(28 314 356)"/><ellipse class="acento" cx="444" cy="358" rx="36" ry="46" transform="rotate(-28 444 358)"/></g>
    <ellipse cx="370" cy="618" rx="170" ry="30" fill="#e2e2ee"/>
  </g>
  <use href="#panda-cuerpo" fill="none" class="linea"/>
  <g id="ojos">
    <circle cx="318" cy="352" r="28" fill="#fff"/>
    <circle cx="318" cy="352" r="24" fill="#1e1a6b"/>
    <circle cx="309" cy="343" r="8" fill="#fff"/>
    <circle cx="327" cy="362" r="3.5" fill="#fff"/>
    <circle cx="440" cy="355" r="28" fill="#fff"/>
    <circle cx="440" cy="355" r="24" fill="#1e1a6b"/>
    <circle cx="431" cy="346" r="8" fill="#fff"/>
    <circle cx="449" cy="365" r="3.5" fill="#fff"/>
  </g>
  <g id="encima"></g>
  <g id="pico"><path class="pico linea" stroke-width="5" d="M354 384 C354 368 404 368 404 384 C404 398 392 406 379 406 C366 406 354 398 354 384 Z"/><ellipse cx="368" cy="382" rx="6" ry="3.5" fill="#fff" opacity=".7"/><path class="trazo" stroke-width="5" d="M379 406 L379 414 M379 414 C372.4 425 357 425 353 416 M379 414 C385.6 425 401 425 405 416"/></g>
</svg>
"""##,
        "conejo": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--pelo:#e8e3f2;--pico:#f28fa0;--acento:#f6a6c1">
  <defs><clipPath id="conejo-clip"><path id="conejo-cuerpo" d="M215 560 C205 470 200 390 222 320 C245 250 310 228 370 228 C440 228 500 250 515 320 C530 390 525 470 520 560 C520 600 460 616 370 616 C280 616 215 600 215 560 Z"/></clipPath></defs>
  <g id="detras">
  <ellipse class="pelo linea" cx="298" cy="228" rx="22" ry="46" transform="rotate(-30 298 228)"/><ellipse class="pelo linea" cx="452" cy="228" rx="22" ry="46" transform="rotate(30 452 228)"/><ellipse class="acento-suave" cx="298" cy="232" rx="11" ry="33.12" transform="rotate(-30 298 228)"/><ellipse class="acento-suave" cx="452" cy="232" rx="11" ry="33.12" transform="rotate(30 452 228)"/>
  </g>
  <g id="aleta-izq">
    <path class="trazo" stroke-width="60" d="M244 408 L180 322"/><path class="pelo-trazo" stroke-width="52" d="M244 408 L180 322"/>
    <ellipse class="acento-suave" cx="181" cy="328" rx="10" ry="8"/>
    <circle class="acento-suave" cx="167" cy="314" r="4.5"/><circle class="acento-suave" cx="179" cy="308" r="4.5"/><circle class="acento-suave" cx="192" cy="313" r="4.5"/>
  </g>
  <g id="aleta-der">
    <path class="trazo" stroke-width="60" d="M502 470 L558 544"/><path class="pelo-trazo" stroke-width="52" d="M502 470 L558 544"/>
  </g>
  <use href="#conejo-cuerpo" class="pelo"/>
  <g clip-path="url(#conejo-clip)">
    <path class="pelo-claro" d="M268 272 C310 246 432 240 488 272 C440 260 320 260 268 272 Z"/>
    <g id="cara"><ellipse fill="#fff" cx="379" cy="402" rx="44" ry="32"/><ellipse fill="#fff" cx="370" cy="574" rx="122" ry="104"/><ellipse cx="282" cy="402" rx="18" ry="11" fill="#ff8fa8" opacity=".45"/><ellipse cx="476" cy="404" rx="18" ry="11" fill="#ff8fa8" opacity=".45"/></g>
    <ellipse cx="370" cy="618" rx="170" ry="30" fill="#e2e2ee"/>
  </g>
  <use href="#conejo-cuerpo" fill="none" class="linea"/>
  <g id="ojos">
    <circle cx="318" cy="352" r="24" fill="#1e1a6b"/>
    <circle cx="309" cy="343" r="8" fill="#fff"/>
    <circle cx="327" cy="362" r="3.5" fill="#fff"/>
    <circle cx="440" cy="355" r="24" fill="#1e1a6b"/>
    <circle cx="431" cy="346" r="8" fill="#fff"/>
    <circle cx="449" cy="365" r="3.5" fill="#fff"/>
  </g>
  <g id="encima"></g>
  <g id="pico"><path fill="#fff" stroke="#1e1a6b" stroke-width="3.5" stroke-linejoin="round" d="M369 412 L369 428 C369 431 389 431 389 428 L389 412 Z M379 413 L379 429"/><path class="pico linea" stroke-width="5" d="M364 386 C364 377 394 377 394 386 C394 394 386 400 379 400 C372 400 364 394 364 386 Z"/><ellipse cx="372" cy="384" rx="6" ry="3.5" fill="#fff" opacity=".7"/><path class="trazo" stroke-width="5" d="M379 400 L379 408 M379 408 C374.2 417 363 417 359 410 M379 408 C383.8 417 395 417 399 410"/></g>
</svg>
"""##,
        "mapache": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--pelo:#9a9cae;--pico:#2b2238;--acento:#34364a">
  <defs><clipPath id="mapache-clip"><path id="mapache-cuerpo" d="M215 560 C205 470 200 390 222 320 C245 250 310 228 370 228 C440 228 500 250 515 320 C530 390 525 470 520 560 C520 600 460 616 370 616 C280 616 215 600 215 560 Z"/></clipPath></defs>
  <g id="detras">
  <path class="pelo linea"  d="M238 312 C232 262 236 214 250 186 C282 196 316 218 340 244 Z"/>
  <path class="pelo linea"  d="M 512 312 C 518 262 514 214 500 186 C 468 196 434 218 410 244 Z"/>
  <path class="acento"  d="M254 292 C250 256 254 226 262 208 C284 218 304 232 320 248 Z"/>
  <path class="acento"  d="M 496 292 C 500 256 496 226 488 208 C 466 218 446 232 430 248 Z"/><path class="trazo" stroke-width="34" d="M262 590 C212 604 172 584 164 540 C160 516 168 498 180 488"/><path class="pelo-trazo" stroke-width="26" d="M262 590 C212 604 172 584 164 540 C160 516 168 498 180 488"/><path class="acento-trazo" stroke-width="26" stroke-dasharray="13 12" d="M262 590 C212 604 172 584 164 540 C160 516 168 498 180 488"/>
  </g>
  <g id="aleta-izq">
    <path class="trazo" stroke-width="60" d="M244 408 L180 322"/><path class="pelo-trazo" stroke-width="52" d="M244 408 L180 322"/>
    <circle class="acento" cx="180" cy="322" r="22"/>
    <ellipse class="acento-suave" cx="181" cy="328" rx="10" ry="8"/>
    <circle class="acento-suave" cx="167" cy="314" r="4.5"/><circle class="acento-suave" cx="179" cy="308" r="4.5"/><circle class="acento-suave" cx="192" cy="313" r="4.5"/>
  </g>
  <g id="aleta-der">
    <path class="trazo" stroke-width="60" d="M502 470 L558 544"/><path class="pelo-trazo" stroke-width="52" d="M502 470 L558 544"/>
    <circle class="acento" cx="558" cy="544" r="22"/>
  </g>
  <use href="#mapache-cuerpo" class="pelo"/>
  <g clip-path="url(#mapache-clip)">
    <path class="pelo-claro" d="M268 272 C310 246 432 240 488 272 C440 260 320 260 268 272 Z"/>
    <g id="cara"><ellipse fill="#fff" cx="379" cy="404" rx="58" ry="40"/><ellipse class="pelo-claro" cx="370" cy="574" rx="122" ry="104"/><path class="acento" d="M200 334 C250 314 330 328 379 346 C428 328 508 314 540 334 L540 388 C490 400 430 394 379 382 C328 394 268 400 200 388 Z"/><path fill="#fff" d="M278 318 C300 300 336 302 352 318 C330 312 300 312 278 318 Z"/><path fill="#fff" d="M406 320 C422 304 458 302 480 320 C458 314 428 314 406 320 Z"/></g>
    <ellipse cx="370" cy="618" rx="170" ry="30" fill="#e2e2ee"/>
  </g>
  <use href="#mapache-cuerpo" fill="none" class="linea"/>
  <g id="ojos">
    <circle cx="318" cy="352" r="28" fill="#fff"/>
    <circle cx="318" cy="352" r="24" fill="#1e1a6b"/>
    <circle cx="309" cy="343" r="8" fill="#fff"/>
    <circle cx="327" cy="362" r="3.5" fill="#fff"/>
    <circle cx="440" cy="355" r="28" fill="#fff"/>
    <circle cx="440" cy="355" r="24" fill="#1e1a6b"/>
    <circle cx="431" cy="346" r="8" fill="#fff"/>
    <circle cx="449" cy="365" r="3.5" fill="#fff"/>
  </g>
  <g id="encima"></g>
  <g id="pico"><path class="pico linea" stroke-width="5" d="M354 384 C354 368 404 368 404 384 C404 398 392 406 379 406 C366 406 354 398 354 384 Z"/><ellipse cx="368" cy="382" rx="6" ry="3.5" fill="#fff" opacity=".7"/><path class="trazo" stroke-width="5" d="M379 406 L379 414 M379 414 C372.4 425 357 425 353 416 M379 414 C385.6 425 401 425 405 416"/></g>
</svg>
"""##,
        "koala": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--pelo:#a3a8b8;--pico:#3b3848;--acento:#f4f4f8">
  <defs><clipPath id="koala-clip"><path id="koala-cuerpo" d="M215 560 C205 470 200 390 222 320 C245 250 310 228 370 228 C440 228 500 250 515 320 C530 390 525 470 520 560 C520 600 460 616 370 616 C280 616 215 600 215 560 Z"/></clipPath></defs>
  <g id="detras">
  <circle class="pelo linea" cx="254" cy="258" r="52"/><circle class="pelo linea" cx="496" cy="258" r="52"/><circle class="acento" cx="252" cy="254" r="32"/><circle class="acento" cx="498" cy="254" r="32"/><circle class="acento" cx="226" cy="250" r="9"/><circle class="acento" cx="524" cy="250" r="9"/><circle class="acento" cx="234" cy="232" r="9"/><circle class="acento" cx="516" cy="232" r="9"/><circle class="acento" cx="250" cy="222" r="9"/><circle class="acento" cx="500" cy="222" r="9"/>
  </g>
  <g id="aleta-izq">
    <path class="trazo" stroke-width="60" d="M244 408 L180 322"/><path class="pelo-trazo" stroke-width="52" d="M244 408 L180 322"/>
    <ellipse class="acento-suave" cx="181" cy="328" rx="10" ry="8"/>
    <circle class="acento-suave" cx="167" cy="314" r="4.5"/><circle class="acento-suave" cx="179" cy="308" r="4.5"/><circle class="acento-suave" cx="192" cy="313" r="4.5"/>
  </g>
  <g id="aleta-der">
    <path class="trazo" stroke-width="60" d="M502 470 L558 544"/><path class="pelo-trazo" stroke-width="52" d="M502 470 L558 544"/>
  </g>
  <use href="#koala-cuerpo" class="pelo"/>
  <g clip-path="url(#koala-clip)">
    <path class="pelo-claro" d="M268 272 C310 246 432 240 488 272 C440 260 320 260 268 272 Z"/>
    <g id="cara"><ellipse class="acento" cx="370" cy="574" rx="112" ry="96"/><ellipse class="acento" cx="379" cy="440" rx="30" ry="16"/></g>
    <ellipse cx="370" cy="618" rx="170" ry="30" fill="#e2e2ee"/>
  </g>
  <use href="#koala-cuerpo" fill="none" class="linea"/>
  <g id="ojos">
    <circle cx="318" cy="352" r="24" fill="#1e1a6b"/>
    <circle cx="309" cy="343" r="8" fill="#fff"/>
    <circle cx="327" cy="362" r="3.5" fill="#fff"/>
    <circle cx="440" cy="355" r="24" fill="#1e1a6b"/>
    <circle cx="431" cy="346" r="8" fill="#fff"/>
    <circle cx="449" cy="365" r="3.5" fill="#fff"/>
  </g>
  <g id="encima"></g>
  <g id="pico"><path class="pico linea" stroke-width="6" d="M354 368 C354 344 404 344 404 368 L404 392 C404 412 392 420 379 420 C366 420 354 412 354 392 Z"/><ellipse cx="368" cy="362" rx="7" ry="10" fill="#fff" opacity=".45"/><path class="trazo" stroke-width="5" d="M366 432 C372 438 386 438 392 432"/></g>
</svg>
"""##,
        "alpaca": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--pelo:#f5ead8;--pico:#8a6a5a;--acento:#e0457b">
  <defs><clipPath id="alpaca-clip"><path id="alpaca-cuerpo" d="M215 560 C205 470 200 390 222 320 C245 250 310 228 370 228 C440 228 500 250 515 320 C530 390 525 470 520 560 C520 600 460 616 370 616 C280 616 215 600 215 560 Z"/></clipPath></defs>
  <g id="detras">
  <ellipse class="pelo linea" cx="300" cy="222" rx="16" ry="40" transform="rotate(-22 300 222)"/><ellipse class="pelo linea" cx="450" cy="222" rx="16" ry="40" transform="rotate(22 450 222)"/><ellipse class="pelo-claro" cx="300" cy="226" rx="8" ry="28.8" transform="rotate(-22 300 222)"/><ellipse class="pelo-claro" cx="450" cy="226" rx="8" ry="28.8" transform="rotate(22 450 222)"/>
  </g>
  <g id="aleta-izq">
    <path class="trazo" stroke-width="60" d="M244 408 L180 322"/><path class="pelo-trazo" stroke-width="52" d="M244 408 L180 322"/>
    <ellipse class="acento-suave" cx="181" cy="328" rx="10" ry="8"/>
    <circle class="acento-suave" cx="167" cy="314" r="4.5"/><circle class="acento-suave" cx="179" cy="308" r="4.5"/><circle class="acento-suave" cx="192" cy="313" r="4.5"/>
  </g>
  <g id="aleta-der">
    <path class="trazo" stroke-width="60" d="M502 470 L558 544"/><path class="pelo-trazo" stroke-width="52" d="M502 470 L558 544"/>
  </g>
  <use href="#alpaca-cuerpo" class="pelo"/>
  <g clip-path="url(#alpaca-clip)">
    <path class="pelo-claro" d="M268 272 C310 246 432 240 488 272 C440 260 320 260 268 272 Z"/>
    <g id="cara"><ellipse class="pelo-claro" cx="379" cy="406" rx="50" ry="40"/><ellipse class="pelo-claro" cx="370" cy="574" rx="122" ry="104"/><ellipse cx="282" cy="402" rx="18" ry="11" fill="#ff8fa8" opacity=".45"/><ellipse cx="476" cy="404" rx="18" ry="11" fill="#ff8fa8" opacity=".45"/></g>
    <ellipse cx="370" cy="618" rx="170" ry="30" fill="#e2e2ee"/>
  </g>
  <use href="#alpaca-cuerpo" fill="none" class="linea"/>
  <g id="ojos">
    <circle cx="318" cy="352" r="24" fill="#1e1a6b"/>
    <circle cx="309" cy="343" r="8" fill="#fff"/>
    <circle cx="327" cy="362" r="3.5" fill="#fff"/>
    <circle cx="440" cy="355" r="24" fill="#1e1a6b"/>
    <circle cx="431" cy="346" r="8" fill="#fff"/>
    <circle cx="449" cy="365" r="3.5" fill="#fff"/>
  </g>
  <g id="encima"><circle class="trazo" fill="#1e1a6b" stroke-width="10" cx="330" cy="252" r="20"/><circle class="trazo" fill="#1e1a6b" stroke-width="10" cx="352" cy="236" r="22"/><circle class="trazo" fill="#1e1a6b" stroke-width="10" cx="380" cy="230" r="24"/><circle class="trazo" fill="#1e1a6b" stroke-width="10" cx="408" cy="236" r="22"/><circle class="trazo" fill="#1e1a6b" stroke-width="10" cx="430" cy="252" r="20"/><circle class="trazo" fill="#1e1a6b" stroke-width="10" cx="356" cy="262" r="18"/><circle class="trazo" fill="#1e1a6b" stroke-width="10" cx="404" cy="262" r="18"/><circle class="trazo" fill="#1e1a6b" stroke-width="10" cx="380" cy="258" r="20"/><circle class="pelo-claro" cx="330" cy="252" r="20"/><circle class="pelo-claro" cx="352" cy="236" r="22"/><circle class="pelo-claro" cx="380" cy="230" r="24"/><circle class="pelo-claro" cx="408" cy="236" r="22"/><circle class="pelo-claro" cx="430" cy="252" r="20"/><circle class="pelo-claro" cx="356" cy="262" r="18"/><circle class="pelo-claro" cx="404" cy="262" r="18"/><circle class="pelo-claro" cx="380" cy="258" r="20"/><circle class="acento linea" stroke-width="4" cx="296" cy="258" r="12"/><circle class="acento linea" stroke-width="4" cx="462" cy="258" r="12"/></g>
  <g id="pico"><path class="pico linea" stroke-width="5" d="M364 386 C364 377 394 377 394 386 C394 394 386 400 379 400 C372 400 364 394 364 386 Z"/><ellipse cx="372" cy="384" rx="6" ry="3.5" fill="#fff" opacity=".7"/><path class="trazo" stroke-width="5" d="M379 400 L379 408 M379 408 C374.2 417 363 417 359 410 M379 408 C383.8 417 395 417 399 410"/></g>
</svg>
"""##,
        "cerdito": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--pelo:#f9b8c9;--pico:#f58fab;--acento:#e56f93">
  <defs><clipPath id="cerdito-clip"><path id="cerdito-cuerpo" d="M215 560 C205 470 200 390 222 320 C245 250 310 228 370 228 C440 228 500 250 515 320 C530 390 525 470 520 560 C520 600 460 616 370 616 C280 616 215 600 215 560 Z"/></clipPath></defs>
  <g id="detras">
  <path class="pelo linea"  d="M238 312 C232 262 236 214 250 186 C282 196 316 218 340 244 Z"/>
  <path class="pelo linea"  d="M 512 312 C 518 262 514 214 500 186 C 468 196 434 218 410 244 Z"/>
  <path class="acento"  d="M254 292 C250 256 254 226 262 208 C284 218 304 232 320 248 Z"/>
  <path class="acento"  d="M 496 292 C 500 256 496 226 488 208 C 466 218 446 232 430 248 Z"/><path class="trazo" stroke-width="14" d="M250 584 C226 596 196 590 194 568 C192 548 218 544 222 562 C226 580 204 588 186 578"/><path class="pelo-trazo" stroke-width="7" d="M250 584 C226 596 196 590 194 568 C192 548 218 544 222 562 C226 580 204 588 186 578"/>
  </g>
  <g id="aleta-izq">
    <path class="trazo" stroke-width="60" d="M244 408 L180 322"/><path class="pelo-trazo" stroke-width="52" d="M244 408 L180 322"/>
    <ellipse class="acento-suave" cx="181" cy="328" rx="10" ry="8"/>
    <circle class="acento-suave" cx="167" cy="314" r="4.5"/><circle class="acento-suave" cx="179" cy="308" r="4.5"/><circle class="acento-suave" cx="192" cy="313" r="4.5"/>
  </g>
  <g id="aleta-der">
    <path class="trazo" stroke-width="60" d="M502 470 L558 544"/><path class="pelo-trazo" stroke-width="52" d="M502 470 L558 544"/>
  </g>
  <use href="#cerdito-cuerpo" class="pelo"/>
  <g clip-path="url(#cerdito-clip)">
    <path class="pelo-claro" d="M268 272 C310 246 432 240 488 272 C440 260 320 260 268 272 Z"/>
    <g id="cara"><ellipse class="pelo-claro" cx="370" cy="574" rx="122" ry="104"/><ellipse cx="282" cy="402" rx="18" ry="11" fill="#ff8fa8" opacity=".45"/><ellipse cx="476" cy="404" rx="18" ry="11" fill="#ff8fa8" opacity=".45"/></g>
    <ellipse cx="370" cy="618" rx="170" ry="30" fill="#e2e2ee"/>
  </g>
  <use href="#cerdito-cuerpo" fill="none" class="linea"/>
  <g id="ojos">
    <circle cx="318" cy="352" r="24" fill="#1e1a6b"/>
    <circle cx="309" cy="343" r="8" fill="#fff"/>
    <circle cx="327" cy="362" r="3.5" fill="#fff"/>
    <circle cx="440" cy="355" r="24" fill="#1e1a6b"/>
    <circle cx="431" cy="346" r="8" fill="#fff"/>
    <circle cx="449" cy="365" r="3.5" fill="#fff"/>
  </g>
  <g id="encima"></g>
  <g id="pico"><ellipse class="pico linea" stroke-width="6" cx="379" cy="392" rx="38" ry="27"/><ellipse class="pico-oscuro" cx="366" cy="392" rx="6" ry="10"/><ellipse class="pico-oscuro" cx="392" cy="392" rx="6" ry="10"/><path class="trazo" stroke-width="5" d="M364 432 C372 440 386 440 394 432"/></g>
</svg>
"""##,
        "objeto-corona": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--objeto:#ffc93c;--objeto2:#e63946">
  <g id="obj-corona">
    <path class="objeto linea" stroke-width="6" d="M318 248 L312 196 L344 220 L375 186 L406 220 L438 196 L432 248 C400 254 350 254 318 248 Z"/>
    <path class="objeto-oscuro" d="M320 236 C350 242 400 242 430 236 L432 248 C400 254 350 254 318 248 Z"/>
    <circle class="objeto linea" stroke-width="4" cx="312" cy="194" r="8"/><circle class="objeto linea" stroke-width="4" cx="375" cy="184" r="9"/><circle class="objeto linea" stroke-width="4" cx="438" cy="194" r="8"/>
    <circle class="objeto-2 linea" stroke-width="4" cx="375" cy="226" r="10"/><circle class="objeto-2" cx="341" cy="230" r="6"/><circle class="objeto-2" cx="409" cy="230" r="6"/>
    <path class="trazo" stroke-width="6" d="M318 248 C350 254 400 254 432 248"/></g>
</svg>
"""##,
        "objeto-gorro-fiesta": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--objeto:#4cc9f0;--objeto2:#ff5d8f">
  <g id="obj-gorro-fiesta">
    <g transform="rotate(10 380 248)">
      <path class="objeto linea" stroke-width="6" d="M318 252 L382 190 L446 252 C404 262 360 262 318 252 Z"/>
      <circle class="objeto-2" cx="364" cy="236" r="7"/><circle class="objeto-2" cx="398" cy="228" r="6"/><circle class="objeto-2" cx="380" cy="210" r="5"/><circle class="objeto-2" cx="414" cy="246" r="5"/><circle class="objeto-2" cx="346" cy="249" r="4"/>
      <path class="objeto2-trazo" stroke-width="7" d="M320 252 C360 262 404 262 444 252"/>
      <circle class="objeto-2 linea" stroke-width="5" cx="382" cy="190" r="13"/>
    </g></g>
</svg>
"""##,
        "objeto-sombrero-copa": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--objeto:#2b2d42;--objeto2:#e63946">
  <g id="obj-sombrero-copa">
    <g transform="rotate(-8 375 240)">
      <path class="objeto linea" stroke-width="6" d="M332 238 L327 190 C327 182 423 182 423 190 L418 238 Z"/>
      <path class="objeto-2" d="M330.3 218 L419.7 218 L418.3 234 L331.7 234 Z"/>
      <path class="objeto-claro" opacity=".5" d="M348 194 L350 212 L357 212 L355 194 Z"/>
      <ellipse class="objeto linea" stroke-width="6" cx="375" cy="240" rx="80" ry="13"/>
    </g></g>
</svg>
"""##,
        "objeto-gorro-mago": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--objeto:#5a4fcf;--objeto2:#ffd23f">
  <g id="obj-gorro-mago">
    <path class="objeto linea" stroke-width="6" d="M316 246 C330 214 350 192 374 180 C394 172 424 176 448 188 C424 192 410 204 406 216 C414 228 422 238 430 246 Z"/>
    <polygon class="objeto-2"  points="372.0,207.0 375.4,215.3 384.4,216.0 377.6,221.8 379.6,230.5 372.0,225.8 364.4,230.5 366.4,221.8 359.6,216.0 368.6,215.3"/><polygon class="objeto-2"  points="402.0,231.0 403.9,235.5 408.7,235.8 405.0,239.0 406.1,243.7 402.0,241.2 397.9,243.7 399.0,239.0 395.3,235.8 400.1,235.5"/><polygon class="objeto-2"  points="346.0,232.0 347.6,235.8 351.7,236.1 348.6,238.8 349.5,242.9 346.0,240.7 342.5,242.9 343.4,238.8 340.3,236.1 344.4,235.8"/>
    <circle class="objeto-2" cx="447" cy="189" r="6"/>
    <ellipse class="objeto linea" stroke-width="6" cx="372" cy="248" rx="94" ry="15"/>
    <path class="objeto-2" d="M290 246 C330 240 414 240 454 246 C414 244 330 244 290 246 Z"/></g>
</svg>
"""##,
        "objeto-chullo": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--objeto:#d62839;--objeto2:#ffd23f">
  <g id="obj-chullo">
    <defs><clipPath id="obj-chullo-chullo"><path d="M216 300 C226 246 296 220 370 220 C446 220 510 244 522 300 C470 286 280 286 216 300 Z"/></clipPath></defs>
    <path class="trazo" stroke-width="12" d="M232 394 L228 440 M510 394 L514 440"/><path class="objeto2-trazo" stroke-width="5" d="M232 394 L228 440 M510 394 L514 440"/>
    <circle class="objeto-2 linea" stroke-width="5" cx="228" cy="446" r="11"/><circle class="objeto-2 linea" stroke-width="5" cx="514" cy="446" r="11"/>
    <path class="objeto linea" stroke-width="6" d="M218 292 C208 332 214 370 232 394 C250 386 262 348 264 292 Z"/><path class="objeto linea" stroke-width="6" d="M 524 292 C 534 332 528 370 510 394 C 492 386 480 348 478 292 Z"/>
    <path class="objeto-2" d="M222 350 L234 336 L246 350 L234 364 Z M520 350 L508 336 L496 350 L508 364 Z"/>
    <path class="objeto linea" stroke-width="6" d="M216 300 C226 246 296 220 370 220 C446 220 510 244 522 300 C470 286 280 286 216 300 Z"/>
    <g clip-path="url(#obj-chullo-chullo)">
      <path class="objeto-2" d="M200 266 C290 250 450 250 540 266 L540 284 C450 268 290 268 200 284 Z"/>
      <polyline points="208,246 224,236 240,246 256,236 272,246 288,236 304,246 320,236 336,246 352,236 368,246 384,236 400,246 416,236 432,246 448,236 464,246 480,236 496,246 512,236 528,246" fill="none" stroke="#fff" stroke-width="5" stroke-linejoin="round"/>
      <path fill="#fff" d="M248 262 L254 268 L248 274 L242 268 Z"/><path fill="#fff" d="M278 262 L284 268 L278 274 L272 268 Z"/><path fill="#fff" d="M308 262 L314 268 L308 274 L302 268 Z"/><path fill="#fff" d="M338 262 L344 268 L338 274 L332 268 Z"/><path fill="#fff" d="M368 262 L374 268 L368 274 L362 268 Z"/><path fill="#fff" d="M398 262 L404 268 L398 274 L392 268 Z"/><path fill="#fff" d="M428 262 L434 268 L428 274 L422 268 Z"/><path fill="#fff" d="M458 262 L464 268 L458 274 L452 268 Z"/><path fill="#fff" d="M488 262 L494 268 L488 274 L482 268 Z"/>
    </g>
    <path class="trazo" stroke-width="6" d="M216 300 C226 246 296 220 370 220 C446 220 510 244 522 300 C470 286 280 286 216 300 Z"/>
    <circle class="objeto-2 linea" stroke-width="5" cx="370" cy="212" r="15"/></g>
</svg>
"""##,
        "objeto-gorra": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--objeto:#2a9d8f;--objeto2:#f4f1de">
  <g id="obj-gorra">
    <path class="objeto linea" stroke-width="6" d="M236 292 C244 246 300 222 372 222 C446 222 502 246 510 292 C450 282 296 282 236 292 Z"/>
    <path d="M372 224 C360 240 350 262 346 286 M372 224 C384 240 394 262 398 286" stroke="#1e1a6b" stroke-opacity=".25" stroke-width="4" fill="none"/>
    <circle class="objeto-2 linea" stroke-width="4" cx="372" cy="262" r="13"/>
    <path class="objeto-2 linea" stroke-width="6" d="M244 290 C300 276 448 276 502 290 C510 300 504 310 492 312 C440 298 306 298 254 312 C242 310 236 300 244 290 Z"/>
    <circle class="objeto linea" stroke-width="4" cx="372" cy="222" r="7"/></g>
</svg>
"""##,
        "objeto-gorro-chef": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--objeto:#ffffff;--objeto2:#e63946">
  <g id="obj-gorro-chef">
    <circle class="trazo" fill="#1e1a6b" stroke-width="12" cx="334" cy="212" r="24"/><circle class="trazo" fill="#1e1a6b" stroke-width="12" cx="374" cy="200" r="26"/><circle class="trazo" fill="#1e1a6b" stroke-width="12" cx="414" cy="212" r="24"/><circle class="trazo" fill="#1e1a6b" stroke-width="12" cx="354" cy="220" r="20"/><circle class="trazo" fill="#1e1a6b" stroke-width="12" cx="394" cy="220" r="20"/><circle class="objeto" cx="334" cy="212" r="24"/><circle class="objeto" cx="374" cy="200" r="26"/><circle class="objeto" cx="414" cy="212" r="24"/><circle class="objeto" cx="354" cy="220" r="20"/><circle class="objeto" cx="394" cy="220" r="20"/>
    <path class="objeto linea" stroke-width="6" d="M324 252 L328 214 L420 214 L424 252 C392 258 356 258 324 252 Z"/>
    <path class="objeto-2" d="M326 234 L422 234 L423 243 L325 243 Z"/>
    <path d="M356 218 L354 232 M376 218 L376 232 M396 218 L398 232" stroke="#1e1a6b" stroke-opacity=".25" stroke-width="3" fill="none"/></g>
</svg>
"""##,
        "objeto-gorro-navidad": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--objeto:#e63946;--objeto2:#ffffff">
  <g id="obj-gorro-navidad">
    <path class="objeto linea" stroke-width="6" d="M318 236 C324 200 358 180 402 180 C448 180 486 200 504 234 C484 222 462 224 448 238 Z"/>
    <path class="objeto-oscuro" opacity=".35" d="M440 232 C452 214 474 208 494 216 C470 212 456 220 446 234 Z"/>
    <rect class="objeto-2 linea" stroke-width="6" x="302" y="224" width="158" height="28" rx="14"/>
    <circle class="objeto-2 linea" stroke-width="5" cx="506" cy="236" r="15"/></g>
</svg>
"""##,
        "objeto-diadema-flor": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--objeto:#9b5de5;--objeto2:#ff8fab">
  <g id="obj-diadema-flor">
    <path class="trazo" stroke-width="18" d="M244 292 C272 240 470 236 502 288"/>
    <path class="objeto-trazo" stroke-width="10" d="M244 292 C272 240 470 236 502 288"/>
    <path fill="#52b788" stroke="#1e1a6b" stroke-width="4" stroke-linejoin="round" d="M470 262 C488 262 500 272 504 284 C488 286 474 278 470 262 Z"/>
    <circle class="trazo" fill="#1e1a6b" stroke-width="8" cx="456.0" cy="235.0" r="13"/><circle class="trazo" fill="#1e1a6b" stroke-width="8" cx="468.4" cy="244.0" r="13"/><circle class="trazo" fill="#1e1a6b" stroke-width="8" cx="463.6" cy="258.5" r="13"/><circle class="trazo" fill="#1e1a6b" stroke-width="8" cx="448.4" cy="258.5" r="13"/><circle class="trazo" fill="#1e1a6b" stroke-width="8" cx="443.6" cy="244.0" r="13"/><circle class="objeto-2" cx="456.0" cy="235.0" r="13"/><circle class="objeto-2" cx="468.4" cy="244.0" r="13"/><circle class="objeto-2" cx="463.6" cy="258.5" r="13"/><circle class="objeto-2" cx="448.4" cy="258.5" r="13"/><circle class="objeto-2" cx="443.6" cy="244.0" r="13"/><circle fill="#ffd23f" stroke="#1e1a6b" stroke-width="4" cx="456" cy="248" r="9"/></g>
</svg>
"""##,
        "objeto-lentes": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--objeto:#c9a227;--objeto2:#ffffff">
  <g id="obj-lentes"><path class="trazo" stroke-width="13" d="M351 350 C364 340 394 340 407 353 M285 346 L230 336 M473 350 L516 342"/><path class="objeto-trazo" stroke-width="7" d="M351 350 C364 340 394 340 407 353 M285 346 L230 336 M473 350 L516 342"/><circle cx="318" cy="352" r="33" fill="#fff" fill-opacity=".22"/><circle class="trazo" stroke-width="13" cx="318" cy="352" r="33"/><circle class="objeto-trazo" stroke-width="7" cx="318" cy="352" r="33"/><path d="M304 332 C310 328 320 327 326 329" stroke="#fff" stroke-width="4" fill="none" stroke-linecap="round" opacity=".8"/><circle cx="440" cy="355" r="33" fill="#fff" fill-opacity=".22"/><circle class="trazo" stroke-width="13" cx="440" cy="355" r="33"/><circle class="objeto-trazo" stroke-width="7" cx="440" cy="355" r="33"/><path d="M426 335 C432 331 442 330 448 332" stroke="#fff" stroke-width="4" fill="none" stroke-linecap="round" opacity=".8"/></g>
</svg>
"""##,
        "objeto-gafas-sol": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--objeto:#2b2d42;--objeto2:#ff5d8f">
  <g id="obj-gafas-sol"><path class="trazo" stroke-width="7" d="M346 352 C360 342 398 342 412 354 M284 344 L230 336 M474 348 L516 342"/><path class="objeto linea" stroke-width="6" d="M286 330 C286 322 350 322 350 330 C350 364 336 378 318 378 C300 378 286 364 286 330 Z"/><path class="objeto-2" d="M286 330 C286 322 350 322 350 330 L350 338 C328 334 308 334 286 338 Z"/><path d="M300 346 L314 346 M300 356 L306 356" stroke="#fff" stroke-width="4" stroke-linecap="round" opacity=".55"/><path class="objeto linea" stroke-width="6" d="M408 333 C408 325 472 325 472 333 C472 367 458 381 440 381 C422 381 408 367 408 333 Z"/><path class="objeto-2" d="M408 333 C408 325 472 325 472 333 L472 341 C450 337 430 337 408 341 Z"/><path d="M422 349 L436 349 M422 359 L428 359" stroke="#fff" stroke-width="4" stroke-linecap="round" opacity=".55"/></g>
</svg>
"""##,
        "objeto-bufanda": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--objeto:#e63946;--objeto2:#f4f1de">
  <g id="obj-bufanda"><defs><clipPath id="obj-bufanda-buf"><path d="M212 438 C290 468 450 468 526 438 L528 470 C450 504 290 504 210 470 Z"/><path d="M430 474 C434 514 438 544 440 576 L482 570 C478 534 472 504 466 472 Z"/></clipPath></defs>
    <path class="trazo" stroke-width="10" d="M444 575 L444 590 M453 574 L453 589 M462 573 L462 588 M471 572 L471 587 M480 571 L480 586 "/><path class="objeto-trazo" stroke-width="5" d="M444 575 L444 590 M453 574 L453 589 M462 573 L462 588 M471 572 L471 587 M480 571 L480 586 "/>
    <path class="objeto linea" stroke-width="6" d="M212 438 C290 468 450 468 526 438 L528 470 C450 504 290 504 210 470 Z"/>
    <path class="objeto linea" stroke-width="6" d="M430 474 C434 514 438 544 440 576 L482 570 C478 534 472 504 466 472 Z"/>
    <g clip-path="url(#obj-bufanda-buf)">
      <rect class="objeto-2" x="246" y="420" width="18" height="100"/><rect class="objeto-2" x="316" y="420" width="18" height="100"/><rect class="objeto-2" x="386" y="420" width="18" height="100"/><rect class="objeto-2" x="456" y="420" width="18" height="100"/>
      <rect class="objeto-2" x="420" y="506" width="80" height="14"/><rect class="objeto-2" x="420" y="536" width="80" height="14"/>
    </g>
    <path class="trazo" stroke-width="6" d="M212 438 C290 468 450 468 526 438 L528 470 C450 504 290 504 210 470 Z"/><path class="trazo" stroke-width="6" d="M430 474 C434 514 438 544 440 576 L482 570 C478 534 472 504 466 472 Z"/></g>
</svg>
"""##,
        "objeto-pajarita": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--objeto:#e63946;--objeto2:#ffffff">
  <g id="obj-pajarita">
    <path class="objeto linea" stroke-width="5" d="M379 456 L332 432 C320 444 320 470 332 482 Z"/>
    <path class="objeto linea" stroke-width="5" d="M 379 456 L 426 432 C 438 444 438 470 426 482 Z"/>
    <circle class="objeto-2" cx="340" cy="448" r="4"/><circle class="objeto-2" cx="336" cy="466" r="4"/><circle class="objeto-2" cx="418" cy="448" r="4"/><circle class="objeto-2" cx="422" cy="466" r="4"/><circle class="objeto-2" cx="352" cy="458" r="3.5"/><circle class="objeto-2" cx="406" cy="458" r="3.5"/>
    <rect class="objeto-oscuro linea" stroke-width="5" x="366" y="444" width="26" height="24" rx="7"/></g>
</svg>
"""##,
        "objeto-collar-placa": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--objeto:#e63946;--objeto2:#ffc93c">
  <g id="obj-collar-placa">
    <path class="objeto linea" stroke-width="5" d="M216 436 C290 462 450 462 522 436 L523 456 C450 482 290 482 215 456 Z"/>
    <circle class="trazo" stroke-width="4" cx="379" cy="474" r="6"/>
    <circle class="objeto-2 linea" stroke-width="5" cx="379" cy="496" r="18"/>
    <g class="objeto-2-oscuro"><ellipse cx="379" cy="501" rx="7" ry="6"/><circle cx="370" cy="490" r="3.2"/><circle cx="379" cy="487" r="3.2"/><circle cx="388" cy="490" r="3.2"/></g></g>
</svg>
"""##,
        "objeto-collar-flores": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--objeto:#ff8fab;--objeto2:#ffd23f">
  <g id="obj-collar-flores"><circle class="objeto linea" stroke-width="3.5" cx="224.0" cy="415.0" r="10"/><circle class="objeto linea" stroke-width="3.5" cx="234.5" cy="422.6" r="10"/><circle class="objeto linea" stroke-width="3.5" cx="230.5" cy="434.9" r="10"/><circle class="objeto linea" stroke-width="3.5" cx="217.5" cy="434.9" r="10"/><circle class="objeto linea" stroke-width="3.5" cx="213.5" cy="422.6" r="10"/><circle fill="#fff" stroke="#1e1a6b" stroke-width="3" cx="224.0" cy="426.0" r="6"/><circle class="objeto-2 linea" stroke-width="3.5" cx="262.6" cy="433.4" r="10"/><circle class="objeto-2 linea" stroke-width="3.5" cx="273.1" cy="441.0" r="10"/><circle class="objeto-2 linea" stroke-width="3.5" cx="269.1" cy="453.3" r="10"/><circle class="objeto-2 linea" stroke-width="3.5" cx="256.1" cy="453.3" r="10"/><circle class="objeto-2 linea" stroke-width="3.5" cx="252.1" cy="441.0" r="10"/><circle fill="#fff" stroke="#1e1a6b" stroke-width="3" cx="262.6" cy="444.4" r="6"/><circle class="objeto linea" stroke-width="3.5" cx="300.9" cy="446.5" r="10"/><circle class="objeto linea" stroke-width="3.5" cx="311.3" cy="454.1" r="10"/><circle class="objeto linea" stroke-width="3.5" cx="307.3" cy="466.4" r="10"/><circle class="objeto linea" stroke-width="3.5" cx="294.4" cy="466.4" r="10"/><circle class="objeto linea" stroke-width="3.5" cx="290.4" cy="454.1" r="10"/><circle fill="#fff" stroke="#1e1a6b" stroke-width="3" cx="300.9" cy="457.5" r="6"/><circle class="objeto-2 linea" stroke-width="3.5" cx="338.8" cy="454.4" r="10"/><circle class="objeto-2 linea" stroke-width="3.5" cx="349.3" cy="462.0" r="10"/><circle class="objeto-2 linea" stroke-width="3.5" cx="345.3" cy="474.3" r="10"/><circle class="objeto-2 linea" stroke-width="3.5" cx="332.4" cy="474.3" r="10"/><circle class="objeto-2 linea" stroke-width="3.5" cx="328.4" cy="462.0" r="10"/><circle fill="#fff" stroke="#1e1a6b" stroke-width="3" cx="338.8" cy="465.4" r="6"/><circle class="objeto linea" stroke-width="3.5" cx="376.5" cy="457.0" r="10"/><circle class="objeto linea" stroke-width="3.5" cx="387.0" cy="464.6" r="10"/><circle class="objeto linea" stroke-width="3.5" cx="383.0" cy="476.9" r="10"/><circle class="objeto linea" stroke-width="3.5" cx="370.0" cy="476.9" r="10"/><circle class="objeto linea" stroke-width="3.5" cx="366.0" cy="464.6" r="10"/><circle fill="#fff" stroke="#1e1a6b" stroke-width="3" cx="376.5" cy="468.0" r="6"/><circle class="objeto-2 linea" stroke-width="3.5" cx="413.8" cy="454.4" r="10"/><circle class="objeto-2 linea" stroke-width="3.5" cx="424.3" cy="462.0" r="10"/><circle class="objeto-2 linea" stroke-width="3.5" cx="420.3" cy="474.3" r="10"/><circle class="objeto-2 linea" stroke-width="3.5" cx="407.4" cy="474.3" r="10"/><circle class="objeto-2 linea" stroke-width="3.5" cx="403.4" cy="462.0" r="10"/><circle fill="#fff" stroke="#1e1a6b" stroke-width="3" cx="413.8" cy="465.4" r="6"/><circle class="objeto linea" stroke-width="3.5" cx="450.9" cy="446.5" r="10"/><circle class="objeto linea" stroke-width="3.5" cx="461.3" cy="454.1" r="10"/><circle class="objeto linea" stroke-width="3.5" cx="457.3" cy="466.4" r="10"/><circle class="objeto linea" stroke-width="3.5" cx="444.4" cy="466.4" r="10"/><circle class="objeto linea" stroke-width="3.5" cx="440.4" cy="454.1" r="10"/><circle fill="#fff" stroke="#1e1a6b" stroke-width="3" cx="450.9" cy="457.5" r="6"/><circle class="objeto-2 linea" stroke-width="3.5" cx="487.6" cy="433.4" r="10"/><circle class="objeto-2 linea" stroke-width="3.5" cx="498.1" cy="441.0" r="10"/><circle class="objeto-2 linea" stroke-width="3.5" cx="494.1" cy="453.3" r="10"/><circle class="objeto-2 linea" stroke-width="3.5" cx="481.1" cy="453.3" r="10"/><circle class="objeto-2 linea" stroke-width="3.5" cx="477.1" cy="441.0" r="10"/><circle fill="#fff" stroke="#1e1a6b" stroke-width="3" cx="487.6" cy="444.4" r="6"/><circle class="objeto linea" stroke-width="3.5" cx="524.0" cy="415.0" r="10"/><circle class="objeto linea" stroke-width="3.5" cx="534.5" cy="422.6" r="10"/><circle class="objeto linea" stroke-width="3.5" cx="530.5" cy="434.9" r="10"/><circle class="objeto linea" stroke-width="3.5" cx="517.5" cy="434.9" r="10"/><circle class="objeto linea" stroke-width="3.5" cx="513.5" cy="422.6" r="10"/><circle fill="#fff" stroke="#1e1a6b" stroke-width="3" cx="524.0" cy="426.0" r="6"/></g>
</svg>
"""##,
        "objeto-tunica-mago": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--objeto:#5a4fcf;--objeto2:#ffd23f">
  <g id="obj-tunica-mago"><defs><clipPath id="obj-tunica-mago-tun-c"><path d="M215 560 C205 470 200 390 222 320 C245 250 310 228 370 228 C440 228 500 250 515 320 C530 390 525 470 520 560 C520 600 460 616 370 616 C280 616 215 600 215 560 Z"/></clipPath><clipPath id="obj-tunica-mago-tun-r"><path d="M190 452 C260 470 330 480 379 520 C428 480 500 470 560 452 L560 650 L190 650 Z"/></clipPath></defs>
    <g clip-path="url(#obj-tunica-mago-tun-c)">
      <path class="objeto" d="M190 452 C260 470 330 480 379 520 C428 480 500 470 560 452 L560 650 L190 650 Z"/>
      <ellipse class="objeto-oscuro" cx="370" cy="618" rx="170" ry="30"/>
      <path class="objeto2-trazo" stroke-width="14" d="M190 452 C260 470 330 480 379 520 C428 480 500 470 560 452"/>
      <path class="trazo" stroke-width="5" d="M190 444 C260 462 330 472 379 512 C428 472 500 462 560 444"/>
      <path class="objeto2-trazo" stroke-width="10" d="M379 524 L379 640"/>
      <polygon class="objeto-2"  points="300.0,546.0 303.7,554.9 313.3,555.7 306.0,561.9 308.2,571.3 300.0,566.3 291.8,571.3 294.0,561.9 286.7,555.7 296.3,554.9"/><polygon class="objeto-2"  points="452.0,537.0 454.9,544.0 462.5,544.6 456.7,549.5 458.5,556.9 452.0,553.0 445.5,556.9 447.3,549.5 441.5,544.6 449.1,544.0"/><polygon class="objeto-2"  points="470.0,588.0 472.1,593.1 477.6,593.5 473.4,597.1 474.7,602.5 470.0,599.6 465.3,602.5 466.6,597.1 462.4,593.5 467.9,593.1"/><polygon class="objeto-2"  points="268.0,513.0 269.9,517.5 274.7,517.8 271.0,521.0 272.1,525.7 268.0,523.1 263.9,525.7 265.0,521.0 261.3,517.8 266.1,517.5"/>
    </g>
    <g clip-path="url(#obj-tunica-mago-tun-r)"><path class="linea" fill="none" d="M215 560 C205 470 200 390 222 320 C245 250 310 228 370 228 C440 228 500 250 515 320 C530 390 525 470 520 560 C520 600 460 616 370 616 C280 616 215 600 215 560 Z"/></g></g>
</svg>
"""##,
        "objeto-poncho": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--objeto:#d62839;--objeto2:#ffd23f">
  <g id="obj-poncho"><path class="trazo" stroke-width="9" d="M215 553 L213 566 M392 599 L394 612 M230 557 L228 570 M406 595 L408 608 M245 562 L243 575 M419 590 L421 603 M260 567 L258 580 M433 585 L435 598 M275 571 L273 584 M446 581 L448 594 M290 576 L288 589 M460 576 L462 589 M304 581 L302 594 M473 571 L475 584 M319 585 L317 598 M486 567 L488 580 M334 590 L332 603 M500 562 L502 575 M349 595 L347 608 M513 557 L515 570 M364 599 L362 612 M527 553 L529 566 "/><path class="objeto2-trazo" stroke-width="4" d="M215 553 L213 566 M392 599 L394 612 M230 557 L228 570 M406 595 L408 608 M245 562 L243 575 M419 590 L421 603 M260 567 L258 580 M433 585 L435 598 M275 571 L273 584 M446 581 L448 594 M290 576 L288 589 M460 576 L462 589 M304 581 L302 594 M473 571 L475 584 M319 585 L317 598 M486 567 L488 580 M334 590 L332 603 M500 562 L502 575 M349 595 L347 608 M513 557 L515 570 M364 599 L362 612 M527 553 L529 566 "/>
    <path class="objeto linea" stroke-width="6" d="M206 446 C280 426 470 426 532 446 L540 548 L379 604 L200 548 Z"/>
    <g clip-path="url(#obj-poncho-poncho)">
      <rect class="objeto-2" x="190" y="474" width="360" height="34"/>
      <polyline points="196,485 214,497 232,485 250,497 268,485 286,497 304,485 322,497 340,485 358,497 376,485 394,497 412,485 430,497 448,485 466,497 484,485 502,497 520,485 538,497" fill="none" stroke="#fff" stroke-width="5" stroke-linejoin="round"/>
      <rect class="objeto-oscuro" x="190" y="528" width="360" height="12"/>
      <path class="objeto-2" d="M250 446 L258 456 L250 466 L242 456 Z"/><path class="objeto-2" d="M286 446 L294 456 L286 466 L278 456 Z"/><path class="objeto-2" d="M322 446 L330 456 L322 466 L314 456 Z"/><path class="objeto-2" d="M358 446 L366 456 L358 466 L350 456 Z"/><path class="objeto-2" d="M394 446 L402 456 L394 466 L386 456 Z"/><path class="objeto-2" d="M430 446 L438 456 L430 466 L422 456 Z"/><path class="objeto-2" d="M466 446 L474 456 L466 466 L458 456 Z"/><path class="objeto-2" d="M502 446 L510 456 L502 466 L494 456 Z"/>
    </g>
    <path class="trazo" stroke-width="6" d="M206 446 C280 426 470 426 532 446 L540 548 L379 604 L200 548 Z"/>
    <defs><clipPath id="obj-poncho-poncho"><path d="M206 446 C280 426 470 426 532 446 L540 548 L379 604 L200 548 Z"/></clipPath></defs></g>
</svg>
"""##,
        "objeto-capa-heroe-detras": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--objeto:#e63946;--objeto2:#ffd23f">
  <g id="obj-capa-heroe-detras"><path class="objeto linea" stroke-width="6" d="M252 410 C206 470 176 548 164 624 C260 610 480 610 580 624 C566 548 536 470 492 410 Z"/>
    <path class="objeto-oscuro" d="M180 590 C190 530 214 470 250 424 C230 470 214 530 206 606 C196 606 186 606 180 606 Z"/></g>
</svg>
"""##,
        "objeto-capa-heroe": ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="140 170 470 460" width="470" height="460" style="--objeto:#e63946;--objeto2:#ffd23f">
  <g id="obj-capa-heroe"><path class="trazo" stroke-width="18" d="M226 426 C290 456 460 456 518 426"/><path class="objeto-trazo" stroke-width="10" d="M226 426 C290 456 460 456 518 426"/>
    <circle class="objeto-2 linea" stroke-width="5" cx="373" cy="449" r="16"/><polygon class="objeto-oscuro"  points="373.0,440.0 375.4,445.7 381.6,446.2 376.9,450.3 378.3,456.3 373.0,453.1 367.7,456.3 369.1,450.3 364.4,446.2 370.6,445.7"/></g>
</svg>
"""##
    ]
}
