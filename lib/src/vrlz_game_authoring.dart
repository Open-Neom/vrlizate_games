import 'dart:typed_data';

import 'package:vrlizate_apps/vrlizate_apps.dart';

import 'vrlz_game_package.dart';

/// External authoring and conversion helpers for `.vrlz` game builds.
///
/// Game repositories live outside VRlizate and outside the SDK (for example in
/// `codebase_games`). They use [VrlzGameAuthoring] at build time to emit
/// deterministic STORE-only `.vrlz` files with SHA-256 and license metadata.
abstract final class VrlzGameAuthoring {
  /// Encodes a validated `.nes` ROM into a `vrlizate.nes.v1` `.vrlz` package.
  static Uint8List encodeNesGame({
    required Uint8List romBytes,
    required String id,
    required String title,
    String description = '',
    required String license,
    required String sourceUrl,
  }) {
    final encoded = VrlzPackage.encodeNes(
      romBytes: romBytes,
      id: id,
      title: title,
      description: description,
      license: license,
      sourceUrl: sourceUrl,
    );
    VrlzGamePackage.decode(encoded);
    return encoded;
  }

  /// Encodes a validated [VrlzRetroLevel] into a `vrlizate.retro2d.v1` `.vrlz` package.
  static Uint8List encodeRetroGame({
    required VrlzRetroLevel level,
    required String id,
    required String title,
    String description = '',
    required String license,
  }) {
    final encoded = VrlzPackage.encodeRetro(
      level: level,
      id: id,
      title: title,
      description: description,
      license: license,
    );
    VrlzGamePackage.decode(encoded);
    return encoded;
  }

  /// Imports a finite orthogonal Tiled JSON map (`terrain` + `entities` layers)
  /// into a validated [VrlzRetroLevel].
  static VrlzRetroLevel importTiledLevel(
    Map<String, Object?> json, {
    required String name,
    required String theme,
    required String mode,
  }) => VrlzTiledImporter.importLevel(
    json,
    name: name,
    theme: theme,
    mode: mode,
  );

  /// Creates and validates a [VrlzRetroLevel] from rectangular ASCII rows
  /// (`16..128` columns by `8..24` rows using `[.#^*SGEBK]`).
  static VrlzRetroLevel createAsciiLevel({
    required String name,
    required String theme,
    required String mode,
    required List<String> rows,
  }) => VrlzRetroLevel.fromJson({
    'name': name,
    'theme': theme,
    'mode': mode,
    'rows': rows,
  });
}
