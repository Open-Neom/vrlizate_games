import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vrlizate_games/vrlizate_games.dart';
import 'package:vrlizate_games/vrlizate_games_io.dart';

Uint8List _sampleInesRom() {
  final rom = Uint8List(16 + 16384 + 8192);
  rom[0] = 0x4E; // N
  rom[1] = 0x45; // E
  rom[2] = 0x53; // S
  rom[3] = 0x1A;
  rom[4] = 1; // 1x 16KB PRG
  rom[5] = 1; // 1x 8KB CHR
  return rom;
}

VrlzRetroLevel _sampleRetroLevel() => VrlzGameAuthoring.createAsciiLevel(
  name: 'Calabozo Sombrío',
  theme: 'neon',
  mode: 'blaster',
  rows: const [
    '################',
    '#..............#',
    '#..*....E....*.#',
    '#..####..####..#',
    '#..............#',
    '#..S........G..#',
    '################',
    '################',
  ],
);

const _sampleLicense =
    'Copyright (c) 2026 Open Source Game Authors. Permission is hereby granted '
    'free of charge to redistribute this open-source game build.';

class _TestAssetBundle extends CachingAssetBundle {
  _TestAssetBundle(this._assets);
  final Map<String, Uint8List> _assets;

  @override
  Future<ByteData> load(String key) async {
    final bytes = _assets[key];
    if (bytes == null) {
      throw FlutterError('Asset not found: $key');
    }
    return ByteData.sublistView(bytes);
  }
}

void main() {
  test('VrlzGameAuthoring encodes NES and Retro 2.5D .vrlz builds and rejects non-game packages', () {
    final nesBytes = VrlzGameAuthoring.encodeNesGame(
      romBytes: _sampleInesRom(),
      id: 'org.vrlizate.games.sample_nes',
      title: 'Sample NES Cartridge',
      description: 'Open-source NROM test cartridge',
      license: _sampleLicense,
      sourceUrl: 'https://github.com/example/sample-nes',
    );
    final nesGame = VrlzGamePackage.decode(nesBytes);
    expect(nesGame.kind, VrlzGameKind.nes);
    expect(nesGame.id, 'org.vrlizate.games.sample_nes');
    expect(nesGame.runtime, 'vrlizate.nes.v1');

    final retroBytes = VrlzGameAuthoring.encodeRetroGame(
      level: _sampleRetroLevel(),
      id: 'org.vrlizate.games.sample_retro',
      title: 'Calabozo Sombrío',
      description: 'Nivel retro 2.5D convertido a .vrlz',
      license: _sampleLicense,
    );
    final retroGame = VrlzGamePackage.decode(retroBytes);
    expect(retroGame.kind, VrlzGameKind.retro2d);
    expect(retroGame.id, 'org.vrlizate.games.sample_retro');
    expect(retroGame.runtime, 'vrlizate.retro2d.v1');

    final builtinBytes = VrlzPackage.encodeBuiltin(
      id: 'org.vrlizate.demo.hello',
      title: 'Hello VR',
      demoId: 'hello_vr',
    );
    expect(
      () => VrlzGamePackage.decode(builtinBytes),
      throwsA(isA<FormatException>()),
    );
  });

  test('VrlzGameDirectoryLoader discovers .vrlz games from Assets, Native Directory, and Cloud HTTPS', () async {
    final nesBytes = VrlzGameAuthoring.encodeNesGame(
      romBytes: _sampleInesRom(),
      id: 'org.vrlizate.games.asset_nes',
      title: 'Asset NES Game',
      license: _sampleLicense,
      sourceUrl: 'https://github.com/example/asset-nes',
    );
    final dirRetroBytes = VrlzGameAuthoring.encodeRetroGame(
      level: _sampleRetroLevel(),
      id: 'org.vrlizate.games.dir_retro',
      title: 'Directory Retro Game',
      license: _sampleLicense,
    );
    final cloudRetroLevel = VrlzGameAuthoring.createAsciiLevel(
      name: 'Cloud Peak',
      theme: 'garden',
      mode: 'platformer',
      rows: const [
        '################',
        '#..............#',
        '#....*....*....#',
        '#...########...#',
        '#..............#',
        '#..S...K....G..#',
        '################',
        '################',
      ],
    );
    final cloudRetroBytes = VrlzGameAuthoring.encodeRetroGame(
      level: cloudRetroLevel,
      id: 'org.vrlizate.games.cloud_retro',
      title: 'Cloud Retro Game',
      license: _sampleLicense,
    );
    final cloudSha = crypto.sha256.convert(cloudRetroBytes).toString();

    // 1. AssetBundle source
    final assetBundle = _TestAssetBundle({
      'assets/vrlz/asset_nes.vrlz': nesBytes,
    });

    // 2. Native Local Directory source
    final tempDir = await Directory.systemTemp.createTemp('vrlizate_games_test_');
    addTearDown(() => tempDir.delete(recursive: true));
    final dirStore = VrlzDirectoryStore(tempDir.path);
    await dirStore.importBytes(dirRetroBytes, filename: 'dir_retro.vrlz');

    // 3. Cloud HTTPS catalog source
    final catalogJson = jsonEncode({
      'formatVersion': 1,
      'packages': [
        {
          'id': 'org.vrlizate.games.cloud_retro',
          'title': 'Cloud Retro Game',
          'url': 'cloud_retro.vrlz',
          'sha256': cloudSha,
        },
      ],
    });
    final mockClient = MockClient((request) async {
      if (request.url.path.endsWith('/catalog.json')) {
        return http.Response(
          catalogJson,
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path.endsWith('/cloud_retro.vrlz')) {
        return http.Response.bytes(
          cloudRetroBytes,
          200,
          headers: {'content-type': 'application/zip'},
        );
      }
      return http.Response('Not found', 404);
    });

    final loader = VrlzGameDirectoryLoader(
      sourceLoader: VrlzGameSourceLoader(httpClient: mockClient),
    );
    final allGames = await loader.discoverAllGames(
      directoryStore: dirStore,
      loadAsset: assetBundle.load,
      explicitAssetPaths: const ['assets/vrlz/asset_nes.vrlz'],
      cloudCatalogUrls: [Uri.parse('https://games.vrlizate.org/catalog.json')],
    );

    expect(allGames.map((g) => g.id).toList(), [
      'org.vrlizate.games.dir_retro',
      'org.vrlizate.games.asset_nes',
      'org.vrlizate.games.cloud_retro',
    ]);
    expect(allGames[0].origin, VrlzGameOrigin.directory);
    expect(allGames[1].origin, VrlzGameOrigin.asset);
    expect(allGames[2].origin, VrlzGameOrigin.cloud);
  });
}
