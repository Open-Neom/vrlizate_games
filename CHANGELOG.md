## 1.0.0 - 2026-10-20

- Promover `vrlizate_games` a la versión estable `1.0.0` bajo la estructura modular Open Neom (`lib/utils/constants/`, `lib/utils/enums/`, `lib/domain/models/`, `lib/domain/services/`) con una clase o enum por archivo y re-exportación compatible en `lib/src/`.
- Añadir soporte `VrlzGameKind.webgame` (`vrlizate.webgame.v1`) y puente de controles VR para juegos web open-source (`Clumsy Bird`, `Hextris`, `2048`, `Pacman Canvas`).
- Añadir `VrGamesConstants`, `VrArcadeCabinetStyle` (`classicUpright`, `neonCyber`, `tabletopMini`, `wallMounted`) y `VrArcadeCabinetSpec` para definir dimensiones, inclinación de pantalla y colores de marquesina de gabinetes arcade 3D.
- Añadir `VrGameSaveEntry` y `VrGameSaveStore` para almacenar y serializar en JSON récords de puntuación (`highScore`) y partidas guardadas (`stateBytes`) por juego y ranura.
- Añadir `VrHomeHoldExitPolicy` para controlar la salida segura al mantener presionado el botón central/Home durante 3 a 5 segundos (`progress`, `shouldShowAlert`, `shouldTriggerExit`).

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
