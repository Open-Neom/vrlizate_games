# vrlizate_games

Módulo del **VRlizate SDK** dedicado a paquetes `.vrlz` de videojuegos (`vrlizate.nes.v1`, `vrlizate.retro2d.v1` y el perfil beta `vrlizate.webgame.v1`), su autoría externa, gabinetes arcade 3D, persistencia y carga desde HTTPS, directorio local y assets.

> Versión actual: **1.0.0**. Consulta [CHANGELOG.md](CHANGELOG.md).

## Principios de Arquitectura `.vrlz` para Juegos

1. **Separación de Apps y Juegos (`vrlizate_apps` vs `vrlizate_games`):**
   - Mientras `vrlizate_apps` gestiona el contenedor base `.vrlz`/`.vrlw`, escenas GLB y descriptores de experiencias, `vrlizate_games` aisla los contratos específicos de videojuegos (`VrlzGamePackage`, `VrlzGameKind.nes`, `VrlzGameKind.retro2d`, `VrArcadeCabinetSpec`, `VrGameSaveStore` y `VrHomeHoldExitPolicy`).
2. **Juegos independientes y runtimes explícitos:**
   - NES y Retro conservan sus contenedores de datos `game.nes` y `level.json`.
   - Webgame contiene un índice pequeño; el juego independiente se compila a JavaScript/WASM y sus archivos se descargan y verifican por SHA-256. Se ejecutan dentro del navegador aislado, sin cargar Dart AOT ni bibliotecas nativas descargadas en la plataforma.
3. **Lectura Multi-Origen Idéntica (`VrlzGameSourceLoader`):**
   - Un mismo build `.vrlz` se valida y carga con exactamente las mismas reglas desde:
     - **Assets internos** (`AssetBundle`, p. ej. `assets/vrlz/*.vrlz` o `assets/vrlz/catalog.json`).
     - **Carpeta nativa local** (`VrlzDirectoryStore`, p. ej. `VRlizate/experiencias/`).
     - **Cloud HTTPS** (`VrlzWebCatalogLoader` / `VrlzPackageLoader` con verificación SHA-256).

## Juegos web — v1 beta

Importar `vrlizate_games_web_runtime.dart` aporta `VrWebGameController`, un origen
de loopback por juego y el puente de controles/lifecycle. `vrlizate_apps` mantiene
el lector, los límites de recursos, la caché persistente por contenido y el
[empaquetador](../vrlizate_apps/doc/vrlz_webgame_v1_beta.md). Home solo presenta
las salas; la plataforma decide qué paquetes disponibles puede abrir.

El host de VRlizate conserva una sesión suspendida durante diez minutos, hasta
abrir otro juego. Después depende del guardado que implemente el juego original.
No existe un save-state universal para todos los juegos web ni guardado por
cuenta todavía. Los orígenes estables conservan IndexedDB/Hive/localStorage.

La proyección actual usa capturas JPEG de WebView y decodificación de imágenes
a 15 Hz como prototipo. Esto **no equivale a los FPS del juego ni del visor** y
requiere medir latencia, imagen WebGL, audio, temperatura y memoria en teléfono.
Una textura nativa compartida o ports compilados en el anfitrión serán necesarios
para comparar alternativas con menor coste. Un build web o una prueba en Chrome
no certifican que esta proyección ya funcione correctamente en Android.
