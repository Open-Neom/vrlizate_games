import 'package:vrlizate_apps/vrlizate_apps.dart';
import 'package:vrlizate_apps/vrlizate_apps_io.dart';

import 'vrlz_game_package.dart';
import 'vrlz_game_source_loader.dart';

/// Native directory and multi-source discovery for `.vrlz` game builds.
///
/// Combines:
/// 1. Native local directory (`VrlzDirectoryStore`, e.g. `VRlizate/experiencias/`)
/// 2. Internal Flutter assets (`VrlzAssetByteLoader`, e.g. `rootBundle.load`)
/// 3. Cloud HTTPS URLs or catalogs (`VrlzWebCatalogLoader` / `VrlzPackageLoader`)
class VrlzGameDirectoryLoader {
  const VrlzGameDirectoryLoader({this.sourceLoader});

  final VrlzGameSourceLoader? sourceLoader;

  VrlzGameSourceLoader get _loader => sourceLoader ?? VrlzGameSourceLoader();

  /// Scans [store] and loads all validated `.vrlz` (and `.nes`) game packages.
  Future<List<VrlzGamePackage>> loadFromDirectory(
    VrlzDirectoryStore store, {
    VrlzGameKind? filterKind,
  }) async {
    final snapshot = await store.scan();
    final games = <VrlzGamePackage>[];
    final seenKeys = <String>{};
    for (final entry in snapshot.entries) {
      final isNes = entry.metadata.kind == VrlzPackageKind.nes;
      final isRetro = entry.metadata.kind == VrlzPackageKind.retro;
      if (!isNes && !isRetro) continue;
      if (filterKind == VrlzGameKind.nes && !isNes) continue;
      if (filterKind == VrlzGameKind.retro2d && !isRetro) continue;
      try {
        final pkg = await store.load(entry);
        final game = VrlzGamePackage.tryFromPackage(
          pkg,
          origin: VrlzGameOrigin.directory,
          packageSha256: entry.fingerprint,
          source: Uri.file(entry.path),
        );
        if (game != null && seenKeys.add(game.deduplicationKey)) {
          games.add(game);
        }
      } catch (_) {
        // Ignore files that changed or failed revalidation mid-scan.
      }
    }
    return List.unmodifiable(games);
  }

  /// Discovers `.vrlz` game builds across Native Directory, Internal Assets,
  /// and Cloud HTTPS sources, deduplicating by `(kind, contentSha256)`.
  Future<List<VrlzGamePackage>> discoverAllGames({
    VrlzGamePackage? initialGame,
    VrlzDirectoryStore? directoryStore,
    VrlzAssetByteLoader? loadAsset,
    String assetPrefix = 'assets/vrlz/',
    List<String> explicitAssetPaths =
        VrlzGameSourceLoader.defaultBundledGameAssets,
    Iterable<String> discoveredAssets = const [],
    List<Uri> cloudPackageUrls = const [],
    List<Uri> cloudCatalogUrls = const [],
    VrlzGameKind? filterKind,
  }) async {
    final results = <VrlzGamePackage>[];
    final seenKeys = <String>{};

    void addGame(VrlzGamePackage? game) {
      if (game == null) return;
      if (filterKind != null && game.kind != filterKind) return;
      if (seenKeys.add(game.deduplicationKey)) {
        results.add(game);
      }
    }

    addGame(initialGame);

    // 1. Native Local Directory (.vrlz / .nes in user folder)
    if (directoryStore != null) {
      try {
        final localGames = await loadFromDirectory(
          directoryStore,
          filterKind: filterKind,
        );
        for (final game in localGames) {
          addGame(game);
        }
      } catch (_) {}
    }

    // 2. Internal App Assets (assets/vrlz/*.vrlz)
    if (loadAsset != null) {
      try {
        final assetGames = await _loader.loadFromAssets(
          loadAsset,
          assetPrefix: assetPrefix,
          explicitAssetPaths: explicitAssetPaths,
          discoveredAssets: discoveredAssets,
          filterKind: filterKind,
        );
        for (final game in assetGames) {
          addGame(game);
        }
      } catch (_) {}
    }

    // 3. Cloud HTTPS direct package URLs
    for (final url in cloudPackageUrls) {
      try {
        final cloudGame = await _loader.loadFromCloudUrl(url);
        addGame(cloudGame);
      } catch (_) {}
    }

    // 4. Cloud HTTPS catalog.json URLs
    for (final catalogUrl in cloudCatalogUrls) {
      try {
        final catalogGames = await _loader.loadFromCloudCatalog(
          catalogUrl,
          filterKind: filterKind,
        );
        for (final game in catalogGames) {
          addGame(game);
        }
      } catch (_) {}
    }

    return List.unmodifiable(results);
  }
}
