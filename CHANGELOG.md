## 0.1.0

- Separación formal de contratos de videojuegos `.vrlz` (`vrlizate.nes.v1` y
  `vrlizate.retro2d.v1`) en el módulo dedicado `vrlizate_games` del VRlizate SDK.
- `VrlzGamePackage`: contenedor validado exclusivo para builds de juegos `.vrlz`
  sin código ejecutable Dart ni librerías nativas embebidas.
- `VrlzGameSourceLoader`: cargador unificado multi-origen capaz de descubrir y
  validar paquetes `.vrlz` de juegos desde:
  1. **Cloud HTTPS** (`catalog.json` verificado por SHA-256 o URL directa `.vrlz`).
  2. **Directorio nativo local** (`VrlzDirectoryStore` en carpeta del dispositivo).
  3. **Assets internos de la app** (`AssetBundle` / `assets/vrlz/*.vrlz`).
- `VrlzGameAuthoring`: utilidades de autoría externa para empaquetar ROMs
  homebrew open-source y convertir niveles Tiled / matrices ASCII en paquetes
  `.vrlz` deterministas (ZIP STORE).
- Herramientas CLI `tool/pack_game_vrlz.dart` y `tool/index_game_vrlz.dart`.
