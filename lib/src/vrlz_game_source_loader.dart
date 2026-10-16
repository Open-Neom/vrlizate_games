import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:vrlizate_apps/vrlizate_apps.dart';

import 'vrlz_game_package.dart';

/// Callback signature matching `AssetBundle.load` (`rootBundle.load`).
typedef VrlzAssetByteLoader = Future<ByteData> Function(String assetPath);

/// Unified loader for `.vrlz` game builds from Internal Assets and Cloud HTTPS.
///
/// Pure Dart so CLI authoring tools (`dart run`) and Flutter host apps share the
/// exact same validation and multi-source loading pipeline.
class VrlzGameSourceLoader {
  VrlzGameSourceLoader({
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
  }) : _httpClient = httpClient;

  final http.Client? _httpClient;
  final Duration timeout;

  /// Default bundled `.vrlz` game asset paths shipped in VRlizate.
  static const defaultBundledGameAssets = <String>[
    // NES Homebrew Cartridges (vrlizate.nes.v1)
    'assets/vrlz/nova_the_squirrel.vrlz',
    'assets/vrlz/thwaite_missile_defense.vrlz',
    'assets/vrlz/concentration_room.vrlz',
    'assets/vrlz/mega_buster_arena.vrlz',
    'assets/vrlz/open_nes_snake.vrlz',
    // Retro 2.5D Stereoscopic Levels (vrlizate.retro2d.v1)
    'assets/vrlz/darkness_dungeon.vrlz',
    'assets/vrlz/super_dash_run.vrlz',
    'assets/vrlz/celeste_classic_peak.vrlz',
    'assets/vrlz/bonfire_solaria_quest.vrlz',
    'assets/vrlz/pinball_cyber_arena.vrlz',
    'assets/vrlz/sunny_gardens.vrlz',
    'assets/vrlz/neon_bastion.vrlz',
  ];

  /// Loads and validates a single `.vrlz` game build from an asset loader
  /// (e.g. `rootBundle.load`).
  Future<VrlzGamePackage> loadFromAsset(
    VrlzAssetByteLoader loadAsset,
    String assetPath,
  ) async {
    final data = await loadAsset(assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    return VrlzGamePackage.decode(
      bytes,
      origin: VrlzGameOrigin.asset,
      source: Uri.parse('asset:///$assetPath'),
      fileName: assetPath.split('/').last,
    );
  }

  /// Discovers all `.vrlz` game builds bundled inside the app's assets.
  ///
  /// Pass `rootBundle.load` as [loadAsset]. Optionally pass [discoveredAssets]
  /// from `AssetManifest.listAssets()`. Non-game `.vrlz` files (scenes,
  /// builtin routes, worlds) are automatically ignored.
  Future<List<VrlzGamePackage>> loadFromAssets(
    VrlzAssetByteLoader loadAsset, {
    String assetPrefix = 'assets/vrlz/',
    List<String> explicitAssetPaths = defaultBundledGameAssets,
    Iterable<String> discoveredAssets = const [],
    VrlzGameKind? filterKind,
  }) async {
    final candidatePaths = <String>[...explicitAssetPaths];
    final sortedDiscovered =
        discoveredAssets
            .where(
              (path) =>
                  path.startsWith(assetPrefix) &&
                  (path.endsWith('.vrlz') || path.endsWith('.nes')),
            )
            .toList()
          ..sort();
    for (final path in sortedDiscovered) {
      if (!candidatePaths.contains(path)) {
        candidatePaths.add(path);
      }
    }

    final results = <VrlzGamePackage>[];
    final seenKeys = <String>{};
    for (final path in candidatePaths) {
      try {
        final data = await loadAsset(path);
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        final pkg = VrlzPackage.decode(
          bytes,
          source: Uri.parse('asset:///$path'),
        );
        final game = VrlzGamePackage.tryFromPackage(
          pkg,
          origin: VrlzGameOrigin.asset,
          packageSha256: crypto.sha256.convert(bytes).toString(),
          source: Uri.parse('asset:///$path'),
        );
        if (game == null) continue;
        if (filterKind != null && game.kind != filterKind) continue;
        if (seenKeys.add(game.deduplicationKey)) {
          results.add(game);
        }
      } catch (_) {
        // Ignore missing optional assets or non-game packages.
      }
    }
    return List.unmodifiable(results);
  }

  /// Downloads and validates a single `.vrlz` game build from an HTTPS [url].
  Future<VrlzGamePackage> loadFromCloudUrl(Uri url) async {
    final loader = VrlzPackageLoader(client: _httpClient, timeout: timeout);
    try {
      final pkg = await loader.load(url);
      return VrlzGamePackage.fromPackage(
        pkg,
        origin: VrlzGameOrigin.cloud,
        source: url,
      );
    } finally {
      loader.close();
    }
  }

  /// Downloads a `catalog.json` index from [catalogUrl], verifies each package
  /// against its declared SHA-256, and returns all game `.vrlz` builds.
  Future<List<VrlzGamePackage>> loadFromCloudCatalog(
    Uri catalogUrl, {
    VrlzGameKind? filterKind,
  }) async {
    final catalogLoader = VrlzWebCatalogLoader(
      client: _httpClient,
      timeout: timeout,
    );
    try {
      final catalog = await catalogLoader.load(catalogUrl);
      final games = <VrlzGamePackage>[];
      final seenKeys = <String>{};
      for (final entry in catalog.entries) {
        try {
          final pkg = await catalogLoader.loadPackage(entry);
          final game = VrlzGamePackage.tryFromPackage(
            pkg,
            origin: VrlzGameOrigin.cloud,
            packageSha256: entry.sha256,
            source: entry.url,
          );
          if (game == null) continue;
          if (filterKind != null && game.kind != filterKind) continue;
          if (seenKeys.add(game.deduplicationKey)) {
            games.add(game);
          }
        } catch (_) {
          // Skip non-game packages or unreachable individual entries.
        }
      }
      return List.unmodifiable(games);
    } finally {
      catalogLoader.close();
    }
  }

  /// Decodes raw `.vrlz` or `.nes` bytes from any custom transport.
  VrlzGamePackage decodeBytes(
    Uint8List bytes, {
    required VrlzGameOrigin origin,
    Uri? source,
    String? fileName,
  }) => VrlzGamePackage.decode(
    bytes,
    origin: origin,
    source: source,
    fileName: fileName,
  );
}
