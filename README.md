# AgruPay (anteriormente Notifable)

AgruPay es un gestor financiero personal y social nativo para iOS, diseñado para automatizar y simplificar el seguimiento de tus finanzas. A diferencia de las apps tradicionales, AgruPay no requiere que ingreses manualmente cada compra: se conecta a tu correo electrónico, extrae de forma segura los recibos bancarios y los clasifica de manera inteligente. Además, incorpora herramientas sociales para registrar y cobrar deudas entre amigos.

## 🚀 Características Principales

### 🧠 Automatización e Inteligencia
- **Sincronización con Gmail**: Extrae silenciosa y automáticamente los comprobantes de tus compras y transferencias.
- **Soporte Multibanco Peruano**: Parsers optimizados para Yape, Plin, BCP, BBVA, Interbank y Scotiabank.
- **Detección de Suscripciones**: Identifica pagos recurrentes y los agrupa en la sección "Comprometido este mes", estimando qué día te cobrarán y cuánto.
- **Aprendizaje de Categorías (Merchant Rules)**: AgruPay recuerda cómo clasificas tus comercios. Si marcas "Wong" como "Supermercado", la app auto-categorizará todas tus compras pasadas y futuras.

### 📊 Análisis y Control
- **Dashboard Dinámico**: Carrusel superior de tus cuentas, barra de ritmo de gasto, e indicadores de saldo.
- **Historial Interactivo**: Visualiza el comportamiento de tu dinero agrupado por Día, Semana, Mes o Año mediante gráficas de barras tocables.
- **Comparativas Inteligentes**: Descubre exactamente qué categorías hicieron que gastes más o menos que el mes pasado, todo en lenguaje natural.

### 🎙️ Ingreso Manual Optimizado
- **Dictado por Voz Inteligente**: Si pagaste en efectivo, toca el micrófono y simplemente di "Pagué quince soles en el menú". AgruPay reconocerá el monto, la nota y la categoría con una hermosa animación orgánica.
- **Ingreso Rápido**: Teclado numérico in-app con funciones de calculadora para registrar lo que no pasa por el banco.

### 🤝 AgruPay Social
- **Deudas entre Amigos (Por cobrar)**: Separa fácilmente la cuenta, anota quién te debe y mantén un balance exacto con cada contacto.
- **Recordatorios Push**: Gracias a la integración con Supabase, envíale a tus amigos un recordatorio de pago directamente como notificación a su pantalla de bloqueo.
- **Sincronización en Tiempo Real**: Todo tu círculo social actualizado al instante.

### 🎨 Diseño Premium y Personalización
- **Temas de Color Flexibles**: Desde acentos vibrantes hasta temas pastel de dos colores (Duotone). Toda la aplicación (gráficos, botones, alertas) se adapta a tu estilo.
- **Tipografías a Medida**: Personaliza el diseño de la fuente (System, Rounded, Serif) y su tamaño de manera independiente del sistema iOS.
- **Glassmorphism**: Efectos visuales de desenfoque (`ultraThinMaterial`) donde los botones flotan elegantemente sobre el contenido.

---

## 🗄️ Arquitectura y Tecnologías

AgruPay es una aplicación moderna que aprovecha lo último del ecosistema de desarrollo de Apple:

- **SwiftUI & Concurrencia**: Interfaces completamente declarativas, animaciones nativas y uso extensivo de `async/await` y `@MainActor` bajo Swift 6.
- **SwiftData**: Persistencia de datos ultrarrápida, consultada en tiempo real por las vistas mediante el macro `@Query`.
- **Supabase**: Backend moderno y serverless para manejar el flujo social, los perfiles de usuario y las notificaciones Push de manera remota.
- **Google Sign-In y Gmail API**: OAuth 2.0 para un acceso seguro (Read-Only) a los recibos, garantizando total privacidad local.
- **Procesamiento de Lenguaje y Regex**: Extracción quirúrgica de montos, nombres de comercios y fechas a partir del código HTML de las entidades financieras.
