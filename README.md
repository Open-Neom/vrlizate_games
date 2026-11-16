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

## Persistencia transaccional de partidas (`A05`)

- `VrGameSaveEntry` realiza copias defensivas de `stateBytes` tanto al construir como en cada lectura (`entry.stateBytes`), de modo que mutar el `Uint8List` devuelto por `VrGameSaveStore.loadEntry(...)` jamás altera el estado guardado en memoria.
- `VrGameSaveStore.restoreFromJson` y `restoreFromJsonString` aplican **restauración atómica en un mapa temporal**: si el JSON está truncado, `schemaVersion` es incompatible, se exceden las cotas (`1 MiB` por ranura / `2,048` entradas) o una entrada contiene base64/campos corruptos, lanzan `FormatException` **conservando intactas todas las partidas anteriores**.

## Juegos web — v1 beta de catálogo curado y garantías de aislamiento (`A07`)

Importar `vrlizate_games_web_runtime.dart` aporta `VrWebGameController`, un origen
de loopback por juego y el puente de controles/lifecycle. `vrlizate_apps` mantiene
el lector, los límites de recursos, la caché persistente por contenido y el
[empaquetador](../vrlizate_apps/doc/vrlz_webgame_v1_beta.md). Home solo presenta
las salas; la plataforma decide qué paquetes disponibles puede abrir.

- **Alcance validado en `1.0.0` (beta de catálogo curado):** `vrlizate.webgame.v1` está diseñado y validado únicamente para **catálogos curados del host** donde el anfitrión suministra el `catalogOrigin` confiado y la política `allowedNetworkOrigins`. No certifica un ecosistema abierto de UGC arbitrario no revisado ni instala un `ServiceWorkerController`/`ServiceWorkerClient` nativo del sistema operativo Android.
- **Aislamiento de origen por editor (`VrWebGameOriginStore.portForManifest`):** el puerto loopback persistente (`IndexedDB` / `localStorage`) se deriva criptográficamente de `(publisherOrigin, manifest.id)` (`catalogOrigin ?? manifest.contentBaseUrl`). Dos orígenes distintos que declaren el mismo `id` reciben puertos distintos, mientras que nuevas revisiones del mismo origen conservan la partida del jugador. El host debe pasar explícitamente `catalogOrigin` (p. ej. el origen HTTPS del catálogo verificado o un origen centinela de importación local) para no delegar la procedencia a `manifest.contentBaseUrl`.
- **Capas efectivas de bloqueo de Workers y política de red (`VrWebGameServer` / `VrWebGameController` / `vrWebGameBridgeScript`):**
  - **Servidor loopback + CSP:** exige token efímero de capacidad por sesión y cabecera `Host` exacta, rechaza con `403 Forbidden` cualquier solicitud con cabeceras `Service-Worker` o `Sec-Fetch-Dest: serviceworker` / `sharedworker`, y emite `worker-src blob:` (cuando `allowBlobWorkers: true`, permitiendo workers dedicados en memoria pero **nunca** `'self'`) o `worker-src 'none'` (cuando `allowBlobWorkers: false`).
  - **WebView y DOM (`AT_DOCUMENT_START`):** intercepta navegaciones y subrecursos (`shouldOverrideUrlLoading` / `shouldInterceptRequest`) y neutraliza en DOM `ServiceWorkerContainer.prototype.register`, `navigator.serviceWorker` y `window.SharedWorker` antes de ejecutar scripts del juego.
  - **Red externa (`allowedNetworkOrigins`):** permite al host intersecar los orígenes HTTPS declarados por el manifiesto o pasar `const <Uri>{}` (política cerrada por defecto recomendada en el host) para denegar toda red externa no autorizada explícitamente.

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
