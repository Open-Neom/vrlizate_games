import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:vrlizate_apps/vrlizate_apps.dart';

import '../../utils/constants/vr_games_constants.dart';
import '../../utils/enums/vrlz_game_kind.dart';
import '../../utils/enums/vrlz_game_origin.dart';

/// Validated `.vrlz` game build (`vrlizate.nes.v1` or `vrlizate.retro2d.v1`).
///
/// Guarantees that the underlying `.vrlz` container is strictly a data-driven
/// game build (containing zero executable Dart or native code) and exposes a
/// unified contract regardless of whether it was loaded from Cloud, a Native
/// Directory, or Internal Assets.
final class VrlzGamePackage {
  const VrlzGamePackage._({
    required this.kind,
    required this.origin,
    required this.package,
    required this.packageSha256,
    this.source,
  });

  final VrlzGameKind kind;
  final VrlzGameOrigin origin;
  final VrlzPackage package;
  final String packageSha256;
  final Uri? source;

  String get id => package.id;
  String get title => package.title;
  String get description => package.description;

  VrlzNesBundle? get nesBundle => package.nesBundle;
  VrlzRetroBundle? get retroBundle => package.retroBundle;

  String get runtime =>
      nesBundle?.manifest.runtime ?? retroBundle!.manifest.runtime;

  String get license =>
      nesBundle?.manifest.license ?? retroBundle!.manifest.license;

  String? get sourceUrl => nesBundle?.manifest.sourceUrl;

  /// SHA-256 of the inner game payload (`game.nes` or `level.json`).
  String get contentSha256 =>
      nesBundle?.manifest.romSha256 ?? retroBundle!.manifest.levelSha256;

  /// Unique deduplication key across Asset, Local Directory, and Cloud sources.
  String get deduplicationKey =>
      '${kind.name}${VrGamesConstants.deduplicationSeparator}$contentSha256';

  /// Re-encodes the validated game build as a deterministic STORE `.vrlz` archive.
  Uint8List encode() => package.encode();

  /// Returns whether [package] is a game `.vrlz` (`nes` or `retro`).
  static bool isGamePackage(VrlzPackage package) =>
      package.kind == VrlzPackageKind.nes ||
      package.kind == VrlzPackageKind.retro;

  /// Converts a [VrlzPackage] into a [VrlzGamePackage] or returns `null` if it
  /// is a non-game package (e.g. scene, builtin route, or connected world).
  static VrlzGamePackage? tryFromPackage(
    VrlzPackage package, {
    VrlzGameOrigin origin = VrlzGameOrigin.asset,
    String? packageSha256,
    Uri? source,
  }) {
    final gameKind = switch (package.kind) {
      VrlzPackageKind.nes => VrlzGameKind.nes,
      VrlzPackageKind.retro => VrlzGameKind.retro2d,
      _ => null,
    };
    if (gameKind == null) return null;
    final resolvedSha =
        packageSha256 ??
        (package.nesBundle?.manifest.romSha256 ??
            package.retroBundle!.manifest.levelSha256);
    return VrlzGamePackage._(
      kind: gameKind,
      origin: origin,
      package: package,
      packageSha256: resolvedSha,
      source: source ?? package.source,
    );
  }

  /// Wraps a validated [VrlzPackage] as a [VrlzGamePackage], throwing
  /// [FormatException] if the package is not a game build.
  static VrlzGamePackage fromPackage(
    VrlzPackage package, {
    VrlzGameOrigin origin = VrlzGameOrigin.asset,
    String? packageSha256,
    Uri? source,
  }) {
    final game = tryFromPackage(
      package,
      origin: origin,
      packageSha256: packageSha256,
      source: source,
    );
    if (game == null) {
      throw FormatException(
        'El paquete VRLZ "${package.id}" (${package.kind.name}) no es un build '
        'de juego compatible con vrlizate_games.',
      );
    }
    return game;
  }

  /// Decodes and validates a `.vrlz` (or raw `.nes`) byte payload as a game build.
  static VrlzGamePackage decode(
    Uint8List bytes, {
    VrlzGameOrigin origin = VrlzGameOrigin.asset,
    Uri? source,
    String? fileName,
  }) {
    final digest = crypto.sha256.convert(bytes).toString();
    final isRawNes =
        (fileName != null &&
            fileName.toLowerCase().endsWith(VrGamesConstants.nesExtension)) ||
        _hasInesMagic(bytes);
    final pkg = isRawNes
        ? VrlzPackage.fromRawNesRom(
            bytes,
            fileName: fileName ?? VrGamesConstants.defaultCartridgeFileName,
            source: source,
          )
        : VrlzPackage.decode(bytes, source: source);
    return fromPackage(
      pkg,
      origin: origin,
      packageSha256: digest,
      source: source,
    );
  }

  static bool _hasInesMagic(Uint8List bytes) =>
      bytes.length >= VrGamesConstants.inesMinHeaderBytes &&
      bytes[0] == VrGamesConstants.inesMagicByte0 &&
      bytes[1] == VrGamesConstants.inesMagicByte1 &&
      bytes[2] == VrGamesConstants.inesMagicByte2 &&
      bytes[3] == VrGamesConstants.inesMagicByte3;
}
