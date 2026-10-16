# vrlizate_games

Módulo del **VRlizate SDK** dedicado a paquetes `.vrlz` de videojuegos (`vrlizate.nes.v1` y `vrlizate.retro2d.v1`), su autoría externa y su carga multi-origen (**Cloud HTTPS**, **Directorio Nativo Local** y **Assets Internos**).

## Principios de Arquitectura `.vrlz` para Juegos

1. **Separación de Apps y Juegos (`vrlizate_apps` vs `vrlizate_games`):**
   - Mientras `vrlizate_apps` gestiona el contenedor base `.vrlz`/`.vrlw`, escenas GLB y descriptores de experiencias, `vrlizate_games` aisla los contratos específicos de videojuegos (`VrlzGamePackage`, `VrlzGameKind.nes`, `VrlzGameKind.retro2d`).
2. **Cero código ejecutable dentro del `.vrlz` ni juegos acoplados al SDK:**
   - Los juegos open-source viven fuera del SDK y de `VRlizate_app` (por ejemplo, en `codebase_games`), donde se compilan como artefactos de datos `.vrlz` puros (`ZIP STORE` sin compresión, `manifest.json` con SHA-256 + `license` + `sourceUrl`, y `game.nes` o `level.json`).
3. **Lectura Multi-Origen Idéntica (`VrlzGameSourceLoader`):**
   - Un mismo build `.vrlz` se valida y carga con exactamente las mismas reglas desde:
     - **Assets internos** (`AssetBundle`, p. ej. `assets/vrlz/*.vrlz` o `assets/vrlz/catalog.json`).
     - **Carpeta nativa local** (`VrlzDirectoryStore`, p. ej. `VRlizate/experiencias/`).
     - **Cloud HTTPS** (`VrlzWebCatalogLoader` / `VrlzPackageLoader` con verificación SHA-256).
