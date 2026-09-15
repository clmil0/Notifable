# Página de invitaciones de AgruPay

Sirve los enlaces `https://agrupay.josephalan444.workers.dev/amigo/<código>` que se comparten por WhatsApp.

- `public/.well-known/apple-app-site-association`: le dice a iOS que abra AgruPay con `/amigo/*`.
- `public/index.html`: lo que ve quien no tiene la app (el código, «Abrir AgruPay», «Copiar código»).
- `public/_headers`: sirve el archivo de Apple como JSON.
- `wrangler.jsonc`: Worker de sólo archivos estáticos. `not_found_handling: single-page-application`
  hace que `/amigo/<código>` devuelva `index.html` **sin redirigir**, así la página conserva el código.

## Publicar (Cloudflare Workers)

```bash
cd web
npx wrangler deploy
```

Comprobar después:

- `https://agrupay.josephalan444.workers.dev/.well-known/apple-app-site-association` → 200 con el JSON.
- `https://agrupay.josephalan444.workers.dev/amigo/a1b2c3d4` → 200 (sin 307) y la página muestra `a1b2c3d4`.

La raíz `/` también muestra la página, con un texto genérico.

## Cambiar de dominio

Un solo ajuste en Xcode: target Notifable → Build Settings → `INVITE_LINK_DOMAIN`. De ahí salen el
entitlement *Associated Domains* y el dominio que usa la app. La app comparte el enlace sólo cuando el
archivo de Apple ya responde con su id (`InviteLinkCheck`); antes, el mensaje lleva sólo el código.
