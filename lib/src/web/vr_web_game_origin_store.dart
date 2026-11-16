import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:vrlizate_apps/vrlizate_apps.dart';

/// Stable browser origins preserve IndexedDB/Hive and localStorage per game.
///
/// The registry is private host data, never a path supplied by a downloaded game.
/// Use [portForManifest] (or pass `publisherOrigin` to [portFor]) whenever
/// opening a manifest so two publishers declaring the same `id` never share a
/// browser storage origin, while legitimate revisions from the same publisher
/// origin preserve saved progress.
final class VrWebGameOriginStore {
  VrWebGameOriginStore(this.directoryPath);
  final String directoryPath;
  static final _queues = <String, Future<void>>{};

  static final RegExp _packageIdPattern = RegExp(
    r'^[a-zA-Z0-9][a-zA-Z0-9._-]{0,159}$',
  );
  static final RegExp _registryKeyPattern = RegExp(
    r'^[a-zA-Z0-9][a-zA-Z0-9._:-]{0,191}$',
  );

  /// Allocates or retrieves a stable loopback port isolated by both publisher
  /// origin (`catalogOrigin ?? manifest.contentBaseUrl`) and `manifest.id`.
  Future<int> portForManifest(
    VrlzWebGameManifest manifest, {
    Uri? catalogOrigin,
  }) => portFor(
    manifest.id,
    publisherOrigin: catalogOrigin ?? manifest.contentBaseUrl,
  );

  /// Allocates or retrieves a stable loopback port for [packageId].
  ///
  /// When [publisherOrigin] is provided, the namespace is cryptographically
  /// bound to `publisherOrigin.origin` + [packageId]. Omitting [publisherOrigin]
  /// is reserved for curated, single-publisher host catalogs.
  Future<int> portFor(String packageId, {Uri? publisherOrigin}) {
    final key = Directory(directoryPath).absolute.path;
    final operation = (_queues[key] ?? Future<void>.value()).then(
      (_) => _allocate(packageId, publisherOrigin: publisherOrigin),
    );
    final tail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _queues[key] = tail;
    tail.whenComplete(() {
      if (identical(_queues[key], tail)) _queues.remove(key);
    });
    return operation;
  }

  static String _buildRegistryKey(String packageId, Uri? publisherOrigin) {
    if (!_packageIdPattern.hasMatch(packageId)) {
      throw ArgumentError('Invalid package id.');
    }
    if (publisherOrigin == null) {
      return packageId;
    }
    final isLoopbackHttp =
        publisherOrigin.scheme == 'http' &&
        const <String>{'127.0.0.1', '::1'}.contains(publisherOrigin.host);
    if (publisherOrigin.host.isEmpty ||
        publisherOrigin.userInfo.isNotEmpty ||
        publisherOrigin.port < 0 ||
        publisherOrigin.port > 65535 ||
        (publisherOrigin.scheme != 'https' && !isLoopbackHttp)) {
      throw ArgumentError(
        'Publisher origin must be an HTTPS origin or loopback HTTP origin.',
      );
    }
    final canonicalOrigin = publisherOrigin.origin.toLowerCase();
    final originHex = sha256
        .convert(utf8.encode(canonicalOrigin))
        .toString()
        .substring(0, 16);
    return 'pub-$originHex:$packageId';
  }

  Future<int> _allocate(String packageId, {Uri? publisherOrigin}) async {
    final registryKey = _buildRegistryKey(packageId, publisherOrigin);
    final directory = Directory(directoryPath);
    await directory.create(recursive: true);
    final lock = await File(
      '${directory.path}/origins.lock',
    ).open(mode: FileMode.append);
    await lock.lock(FileLock.exclusive);
    try {
      final file = File('${directory.path}/origins.json');
      final registry = <String, int>{};
      if (await file.exists()) {
        if (await file.length() > 128 * 1024) {
          throw const FormatException('Origin registry too large.');
        }
        final json = jsonDecode(await file.readAsString());
        if (json is! Map<String, dynamic> || json.length > 1024) {
          throw const FormatException('Invalid origin registry.');
        }
        for (final entry in json.entries) {
          if (!_registryKeyPattern.hasMatch(entry.key) ||
              entry.value is! int ||
              entry.value < 20000 ||
              entry.value > 60000 ||
              registry.containsValue(entry.value)) {
            throw const FormatException('Invalid or duplicate game origin.');
          }
          registry[entry.key] = entry.value as int;
        }
      }
      final existing = registry[registryKey];
      if (existing != null) return existing;
      if (registry.length >= 1024) {
        throw StateError('Too many saved game origins.');
      }
      final digest = sha256.convert(utf8.encode(registryKey)).bytes;
      var port = 20000 + ((digest[0] << 8 | digest[1]) % 40001);
      while (registry.containsValue(port)) {
        port = port == 60000 ? 20000 : port + 1;
      }
      registry[registryKey] = port;
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(registry), flush: true);
      await temp.rename(file.path);
      return port;
    } finally {
      await lock.unlock();
      await lock.close();
    }
  }
}
