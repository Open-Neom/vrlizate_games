import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Stable browser origins preserve IndexedDB/Hive and localStorage per game.
/// The registry is private host data, never a path supplied by a downloaded game.
final class VrWebGameOriginStore {
  VrWebGameOriginStore(this.directoryPath);
  final String directoryPath;
  static final _queues = <String, Future<void>>{};

  Future<int> portFor(String packageId) {
    final key = Directory(directoryPath).absolute.path;
    final operation = (_queues[key] ?? Future<void>.value()).then(
      (_) => _allocate(packageId),
    );
    final tail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _queues[key] = tail;
    tail.whenComplete(() {
      if (identical(_queues[key], tail)) _queues.remove(key);
    });
    return operation;
  }

  Future<int> _allocate(String packageId) async {
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{0,159}$').hasMatch(packageId)) {
      throw ArgumentError('Invalid package id.');
    }
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
          if (entry.value is! int ||
              entry.value < 20000 ||
              entry.value > 60000 ||
              registry.containsValue(entry.value)) {
            throw const FormatException('Invalid or duplicate game origin.');
          }
          registry[entry.key] = entry.value as int;
        }
      }
      final existing = registry[packageId];
      if (existing != null) return existing;
      if (registry.length >= 1024) {
        throw StateError('Too many saved game origins.');
      }
      final digest = sha256.convert(utf8.encode(packageId)).bytes;
      var port = 20000 + ((digest[0] << 8 | digest[1]) % 40001);
      while (registry.containsValue(port)) {
        port = port == 60000 ? 20000 : port + 1;
      }
      registry[packageId] = port;
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
