import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:vrlizate_apps/vrlizate_apps.dart';

/// Per-game loopback origin. Only declared, verified files can leave the loader.
/// A fresh capability path rejects other localhost callers and stale sessions.
///
/// Service Worker / SharedWorker script registrations are denied at both HTTP
/// (`Service-Worker` / `Sec-Fetch-Dest`) and CSP (`worker-src`) layers.
/// External `connect-src` allowances from [manifest] can be intersected or
/// disabled entirely by passing [allowedNetworkOrigins] (e.g. `const <Uri>{}`
/// for untrusted third-party packages).
final class VrWebGameServer {
  VrWebGameServer(
    this.manifest,
    this.loader, {
    Set<Uri>? allowedNetworkOrigins,
    this.allowBlobWorkers = true,
  }) : effectiveNetworkOrigins = List<Uri>.unmodifiable(
         _resolveNetworkOrigins(manifest.networkOrigins, allowedNetworkOrigins),
       );

  final VrlzWebGameManifest manifest;
  final VrlzWebGameLoader loader;

  /// Whether in-memory `blob:` dedicated Web Workers are permitted in CSP.
  /// Same-origin HTTP workers (`'self'`) and Service Workers are always blocked.
  final bool allowBlobWorkers;

  /// Effective HTTPS origins admitted after applying host policy.
  final List<Uri> effectiveNetworkOrigins;

  HttpServer? _server;
  StreamSubscription<HttpRequest>? _requests;
  late final String _token = base64Url
      .encode(List<int>.generate(24, (_) => Random.secure().nextInt(256)))
      .replaceAll('=', '');

  static List<Uri> _resolveNetworkOrigins(
    List<Uri> declared,
    Set<Uri>? allowedByHost,
  ) {
    if (allowedByHost == null) {
      return declared;
    }
    final admitted = <String>{
      for (final uri in allowedByHost)
        if (uri.scheme == 'https' &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty)
          uri.origin,
    };
    return <Uri>[
      for (final origin in declared)
        if (admitted.contains(origin.origin)) origin,
    ];
  }

  Uri get baseUri {
    final server = _server;
    if (server == null) throw StateError('Game origin is not running.');
    return Uri.parse('http://127.0.0.1:${server.port}/$_token/');
  }

  static const _probePath = '__vrlizate_host_capabilities__.html';
  Uri get probeUri => baseUri.resolve(_probePath);
  Uri get entryUri => baseUri.resolve(manifest.entrypoint);
  bool owns(Uri uri) =>
      _server != null &&
      uri.scheme == 'http' &&
      uri.host == '127.0.0.1' &&
      uri.port == _server!.port &&
      uri.userInfo.isEmpty &&
      uri.path.startsWith('/$_token/');

  static bool isForbiddenWorkerRequest({
    String? serviceWorkerHeader,
    String? secFetchDestHeader,
  }) {
    if (serviceWorkerHeader != null && serviceWorkerHeader.trim().isNotEmpty) {
      return true;
    }
    final dest = secFetchDestHeader?.trim().toLowerCase();
    return dest == 'serviceworker' || dest == 'sharedworker';
  }

  Future<void> start({required int port}) async {
    if (_server != null) throw StateError('Game origin already running.');
    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      port,
      shared: false,
    );
    _requests = _server!.listen((request) => unawaited(_serve(request)));
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      final host = request.headers.value(HttpHeaders.hostHeader);
      if (host != '127.0.0.1:${_server?.port}' ||
          !request.uri.path.startsWith('/$_token/') ||
          !const {'GET', 'HEAD'}.contains(request.method) ||
          isForbiddenWorkerRequest(
            serviceWorkerHeader: request.headers.value('service-worker'),
            secFetchDestHeader: request.headers.value('sec-fetch-dest'),
          )) {
        response.statusCode = HttpStatus.forbidden;
        return;
      }
      final path = request.uri.path.substring(_token.length + 2);
      if (path == _probePath) {
        // Host-owned HTML on the real isolated game origin, before any
        // downloaded executable runs. COOP/COEP apply to this document too.
        final bytes = utf8.encode(
          '<!doctype html><meta charset="utf-8">'
          '<title>VRlizate compatibility</title>',
        );
        _headers(response, 'text/html; charset=utf-8');
        response.contentLength = bytes.length;
        if (request.method != 'HEAD') response.add(bytes);
        return;
      }
      if (!manifest.files.any((file) => file.path == path)) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final file = manifest.file(path);
      final bytes = await loader.readFile(path);
      _headers(response, file.mediaType);
      response.contentLength = bytes.length;
      if (request.method != 'HEAD') response.add(bytes);
    } catch (_) {
      response.statusCode = HttpStatus.serviceUnavailable;
    } finally {
      await response.close();
    }
  }

  void _headers(HttpResponse response, String mediaType) {
    final network = effectiveNetworkOrigins
        .map((uri) => '${uri.origin} wss://${uri.authority}')
        .join(' ');
    final connectSrc = network.isEmpty ? "'self'" : "'self' $network";
    final workerSrc = allowBlobWorkers ? 'blob:' : "'none'";
    response.headers
      ..set(HttpHeaders.contentTypeHeader, mediaType)
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Referrer-Policy', 'no-referrer')
      ..set('Cross-Origin-Opener-Policy', 'same-origin')
      ..set('Cross-Origin-Embedder-Policy', 'require-corp')
      ..set('Cross-Origin-Resource-Policy', 'same-origin')
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set(
        'Permissions-Policy',
        'camera=(), microphone=(), geolocation=(), bluetooth=(), usb=()',
      )
      ..set(
        'Content-Security-Policy',
        "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' 'wasm-unsafe-eval' blob:; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; media-src 'self' blob: data:; worker-src $workerSrc; connect-src $connectSrc; frame-src 'none'; object-src 'none'; base-uri 'self'; form-action 'none'; frame-ancestors 'none'",
      );
  }

  Future<void> close() async {
    await _requests?.cancel();
    _requests = null;
    await _server?.close(force: true);
    _server = null;
  }
}
