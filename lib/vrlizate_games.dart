/// Validated `.vrlz` game packages (`vrlizate.nes.v1` and `vrlizate.retro2d.v1`),
/// external authoring helpers, and multi-source game loading (Assets & Cloud).
library;

export 'package:vrlizate_apps/vrlizate_apps.dart'
    show
        VrlzNesBundle,
        VrlzNesManifest,
        VrlzPackage,
        VrlzPackageKind,
        VrlzPackageLoader,
        VrlzRetroBundle,
        VrlzRetroLevel,
        VrlzRetroManifest,
        VrlzTiledImporter,
        VrlzWebCatalog,
        VrlzWebCatalogEntry,
        VrlzWebCatalogLoader;

export 'domain/models/vr_arcade_cabinet_spec.dart';
export 'domain/models/vr_game_save_entry.dart';
export 'domain/models/vrlz_game_package.dart';
export 'domain/services/vr_game_save_store.dart';
export 'domain/services/vr_home_hold_exit_policy.dart';
export 'domain/services/vrlz_game_authoring.dart';
export 'domain/services/vrlz_game_source_loader.dart';
export 'utils/constants/vr_games_constants.dart';
export 'utils/enums/vr_arcade_cabinet_style.dart';
export 'utils/enums/vrlz_game_kind.dart';
export 'utils/enums/vrlz_game_origin.dart';
