import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vrlizate_games/vrlizate_games.dart';
import 'package:vrlizate_games/src/web/vr_web_game_bridge.dart';
import 'package:vrlizate_games/src/web/vr_web_game_origin_store.dart';
import 'package:vrlizate_games/src/web/vr_web_game_server.dart';
import 'package:vrlizate_games/src/web/vr_web_game_document_policy.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vrlizate-web-runtime-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'origins are stable across store instances and distinct across game IDs',
    () async {
      final store = VrWebGameOriginStore(directory.path);
      final first = await store.portFor('org.example.one');
      expect(first, inInclusiveRange(20000, 60000));
      expect(
        await VrWebGameOriginStore(directory.path).portFor('org.example.one'),
        first,
      );
      expect(await store.portFor('org.example.two'), isNot(first));
    },
  );

  test(
    'portForManifest isolates identical game IDs across different publisher origins while preserving updates from the same publisher (A07)',
    () async {
      final store = VrWebGameOriginStore(directory.path);
      final publisherOneV1 = _manifest(
        contentBaseUrl: 'https://games.example/releases/v1/',
        revision: 'rev-1',
      );
      final publisherOneV2 = _manifest(
        contentBaseUrl: 'https://games.example/releases/v2/',
        revision: 'rev-2',
      );
      final publisherTwo = _manifest(
        contentBaseUrl: 'https://different-publisher.example/build/',
        revision: 'unrelated-rev',
      );

      expect(publisherOneV1.id, publisherTwo.id);
      final portOneV1 = await store.portForManifest(publisherOneV1);
      final portOneV2 = await store.portForManifest(publisherOneV2);
      final portTwo = await store.portForManifest(publisherTwo);

      expect(portOneV2, portOneV1);
      expect(portTwo, isNot(portOneV1));
    },
  );

  test('concurrent allocations preserve every saved origin', () async {
    final ports = await Future.wait([
      for (var i = 0; i < 24; i++)
        VrWebGameOriginStore(directory.path).portFor('org.example.game-$i'),
    ]);
    expect(ports.toSet(), hasLength(24));
    for (var i = 0; i < 24; i++) {
      expect(
        await VrWebGameOriginStore(
          directory.path,
        ).portFor('org.example.game-$i'),
        ports[i],
      );
    }
  });

  test(
    'corrupt registry is preserved instead of silently losing game saves',
    () async {
      final file = File('${directory.path}/origins.json');
      await file.writeAsString('{bad');
      await expectLater(
        VrWebGameOriginStore(directory.path).portFor('org.example.one'),
        throwsFormatException,
      );
      expect(await file.readAsString(), '{bad');
    },
  );

  test(
    'game origin exposes verified resources and denies other paths, methods and tokens',
    () async {
      final requested = <String>[];
      final manifest = _manifest();
      final loader = VrlzWebGameLoader(
        manifest,
        client: MockClient((request) async {
          requested.add(request.url.path);
          return http.Response.bytes(utf8.encode('<p>real game</p>'), 200);
        }),
      );
      final server = VrWebGameServer(manifest, loader);
      await server.start(port: 0);
      addTearDown(() async {
        await server.close();
        loader.close();
      });
      final probe = await http.get(server.probeUri);
      expect(probe.statusCode, 200);
      expect(probe.body, contains('VRlizate compatibility'));
      expect(probe.headers['cross-origin-opener-policy'], 'same-origin');
      expect(probe.headers['cross-origin-embedder-policy'], 'require-corp');
      expect(
        requested,
        isEmpty,
        reason: 'Preflight must not fetch or run game code.',
      );
      final response = await http.get(server.entryUri);
      expect(response.statusCode, 200);
      expect(response.body, '<p>real game</p>');
      expect(response.headers['cross-origin-embedder-policy'], 'require-corp');
      expect(
        response.headers['content-security-policy'],
        contains("object-src 'none'"),
      );
      expect(response.headers['permissions-policy'], contains('microphone=()'));
      expect((await http.post(server.entryUri)).statusCode, 403);
      expect(
        (await http.get(server.baseUri.resolve('missing.json'))).statusCode,
        404,
      );
      expect(
        (await http.get(
          server.entryUri.replace(path: '/wrong/index.html'),
        )).statusCode,
        403,
      );
      expect(requested, hasLength(1));
      expect(server.owns(server.entryUri.replace(host: 'localhost')), isFalse);
      expect(server.owns(server.entryUri.replace(scheme: 'https')), isFalse);
    },
  );

  test(
    'HTTPS allowlist generates WSS CSP without applying Uri.origin to WSS',
    () async {
      final manifest = _manifest(networkOrigins: ['https://api.example:8443']);
      final loader = VrlzWebGameLoader(
        manifest,
        client: MockClient((_) async => http.Response('<p>real game</p>', 200)),
      );
      final server = VrWebGameServer(manifest, loader);
      await server.start(port: 0);
      addTearDown(() async {
        await server.close();
        loader.close();
      });
      final response = await http.get(server.probeUri);
      expect(response.statusCode, 200);
      expect(
        response.headers['content-security-policy'],
        contains('https://api.example:8443 wss://api.example:8443'),
      );
    },
  );

  test(
    'blocks Service Worker / SharedWorker registrations and enforces host networkOrigins admission policy (A07)',
    () async {
      final manifest = _manifest(
        networkOrigins: const <String>[
          'https://admitted.example:8443',
          'https://unapproved-third-party.example',
        ],
        extraFiles: const <String, String>{'sw.js': 'application/javascript'},
      );
      final loader = VrlzWebGameLoader(
        manifest,
        client: MockClient((_) async => http.Response('<p>real game</p>', 200)),
      );
      final restrictedServer = VrWebGameServer(
        manifest,
        loader,
        allowedNetworkOrigins: <Uri>{
          Uri.parse('https://admitted.example:8443'),
        },
        allowBlobWorkers: false,
      );
      await restrictedServer.start(port: 0);
      addTearDown(() async {
        await restrictedServer.close();
        loader.close();
      });

      final entryResp = await http.get(restrictedServer.entryUri);
      expect(entryResp.statusCode, 200);
      final csp = entryResp.headers['content-security-policy']!;
      expect(csp, contains("worker-src 'none'"));
      expect(csp, isNot(contains("worker-src 'self'")));
      expect(
        csp,
        contains('https://admitted.example:8443 wss://admitted.example:8443'),
      );
      expect(csp, isNot(contains('unapproved-third-party.example')));

      // Service-Worker and Sec-Fetch-Dest: serviceworker/sharedworker requests fail closed with 403.
      final swUri = restrictedServer.baseUri.resolve('sw.js');
      expect((await http.get(swUri)).statusCode, 200);
      expect(
        (await http.get(
          swUri,
          headers: const <String, String>{'Service-Worker': 'script'},
        )).statusCode,
        403,
      );
      expect(
        (await http.get(
          swUri,
          headers: const <String, String>{'Sec-Fetch-Dest': 'serviceworker'},
        )).statusCode,
        403,
      );
      expect(
        (await http.get(
          swUri,
          headers: const <String, String>{'Sec-Fetch-Dest': 'sharedworker'},
        )).statusCode,
        403,
      );

      // Bridge script neutralizes navigator.serviceWorker and window.SharedWorker at document start.
      final bridgeJs = vrWebGameBridgeScript(
        manifest.controls,
        manifest.controllerProfile,
      );
      expect(bridgeJs, contains('ServiceWorkerContainer'));
      expect(
        bridgeJs,
        contains("Object.defineProperty(navigator, 'serviceWorker'"),
      );
      expect(
        bridgeJs,
        contains("Object.defineProperty(window, 'SharedWorker'"),
      );
    },
  );

  test('corrupted download never reaches the game browser', () async {
    final loader = VrlzWebGameLoader(
      _manifest(),
      client: MockClient((_) async => http.Response('tampered', 200)),
    );
    final server = VrWebGameServer(_manifest(), loader);
    await server.start(port: 0);
    addTearDown(() async {
      await server.close();
      loader.close();
    });
    final response = await http.get(server.entryUri);
    expect(response.statusCode, 503);
    expect(response.body, isEmpty);
  });

  test('web profile participates in the existing game discovery contract', () {
    final package = VrlzPackage.decode(
      VrlzPackage.encodeWebGame(manifest: _manifest()),
    );
    final game = VrlzGamePackage.fromPackage(package);
    expect(game.kind, VrlzGameKind.webgame);
    expect(game.runtime, VrlzWebGameManifest.runtime);
    expect(game.webGameManifest!.id, package.id);
    expect(game.contentSha256, hasLength(64));
    expect(game.encode(), package.encode());
  });

  test('selector navigates only to declared HTML on its isolated origin', () {
    final manifest = _manifest(
      extraFiles: {
        'temple/index.html': 'text/html',
        'rhodes/index.html': 'text/html',
        'main.dart.js': 'application/javascript',
        'pretend.html': 'image/png',
      },
    );
    final base = Uri.parse('http://127.0.0.1:23456/capability/');
    final policy = VrWebGameDocumentPolicy(manifest, base);
    for (final path in [
      'index.html',
      'temple/index.html',
      'rhodes/index.html',
    ]) {
      expect(policy.allows(base.resolve(path)), isTrue, reason: path);
    }
    expect(policy.allows(base.resolve('temple/index.html#/menu')), isTrue);
    for (final candidate in [
      base.resolve('main.dart.js'),
      base.resolve('pretend.html'),
      base.resolve('missing/index.html'),
      base.resolve('temple/index.html?redirect=external'),
      Uri.parse('http://127.0.0.1:23456/other/index.html'),
      Uri.parse('http://127.0.0.1:23457/capability/index.html'),
      Uri.parse('https://127.0.0.1:23456/capability/index.html'),
      Uri.parse('http://user@127.0.0.1:23456/capability/index.html'),
      Uri.parse('http://localhost:23456/capability/index.html'),
      Uri.parse('https://other.example/index.html'),
      Uri.parse('javascript:alert(1)'),
      Uri.parse('data:text/html,test'),
    ]) {
      expect(policy.allows(candidate), isFalse, reason: '$candidate');
    }
  });
}

VrlzWebGameManifest _manifest({
  String contentBaseUrl = 'https://games.example/build/',
  String revision = 'abc123',
  List<String> networkOrigins = const [],
  Map<String, String> extraFiles = const {},
}) {
  final bytes = Uint8List.fromList(utf8.encode('<p>real game</p>'));
  return VrlzWebGameManifest.fromJson({
    'formatVersion': 1,
    'runtime': VrlzWebGameManifest.runtime,
    'capabilities': ['web.sandbox'],
    'id': 'org.example.game',
    'title': 'Original game',
    'description': 'Browser integration',
    'revision': revision,
    'entrypoint': 'index.html',
    'contentBaseUrl': contentBaseUrl,
    'networkOrigins': networkOrigins,
    'controllerProfile': 'dpad',
    'controls': {'A': 'Enter'},
    'license': 'MIT',
    'assetNotice': 'Test-owned content.',
    'sourceUrl': 'https://github.com/example/game',
    'licenseUrl': 'https://github.com/example/game/blob/abc/LICENSE',
    'sourceArchiveUrl': 'https://games.example/source.tar.gz',
    'units': [
      {
        'id': 'startup',
        'startup': true,
        'files': [
          {
            'path': 'index.html',
            'byteLength': bytes.length,
            'sha256': sha256.convert(bytes).toString(),
            'mediaType': 'text/html',
          },
          for (final entry in extraFiles.entries)
            {
              'path': entry.key,
              'byteLength': bytes.length,
              'sha256': sha256.convert(bytes).toString(),
              'mediaType': entry.value,
            },
        ],
      },
    ],
  });
}
