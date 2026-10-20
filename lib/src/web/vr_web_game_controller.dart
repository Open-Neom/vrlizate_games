import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:vrlizate_apps/vrlizate_apps.dart';

import 'vr_web_game_bridge.dart';
import 'vr_web_game_capabilities.dart';
import 'vr_web_game_document_policy.dart';
import 'vr_web_game_server.dart';

/// One isolated browser program at a time; the host renders its frames in VR.
/// This boundary exposes input and pixels, not native service/permission RPC.
class VrWebGameController extends ChangeNotifier {
  VrWebGameController({
    required this.manifest,
    required this.loader,
    required this.port,
    this.captureFramesPerSecond = 15,
  }) {
    if (port < 20000 ||
        port > 60000 ||
        captureFramesPerSecond < 1 ||
        captureFramesPerSecond > 30) {
      throw ArgumentError('Invalid browser runtime limits.');
    }
  }
  final VrlzWebGameManifest manifest;
  final VrlzWebGameLoader loader;
  final int port, captureFramesPerSecond;
  HeadlessInAppWebView? _browser;
  InAppWebViewController? _web;
  VrWebGameServer? _server;
  ui.Image? _image;
  Timer? _captureTimer;
  Timer? _readyTimeout;
  bool _disposed = false, _started = false, _paused = false, _capturing = false;
  int _generation = 0, _frames = 0;
  bool _preflightRunning = false, _preflightPassed = false;
  bool _entryLoaded = false, _handshakeReady = false;
  bool _waitingForReady = false;
  Uri? _documentUri;
  int _documentGeneration = 0;
  String? _error;
  String _status = 'Preparando juego…';
  Future<void>? _startOperation;
  Future<void> _inputQueue = Future.value();
  Map<String, Object?>? _pendingInput;
  bool _sendingInput = false, _awaitNeutral = true, _browserActive = true;
  final _buttonInputs = Queue<Map<String, Object?>>();
  Map<String, bool> _lastButtons = {};
  bool _lastPointerClick = false;
  Future<void> _activityQueue = Future.value();

  ui.Image? get image => _image;
  String? get error => _error;
  String get status => _status;
  bool get ready =>
      _started && _preflightPassed && _web != null && _error == null;
  bool get paused => _paused;
  bool get isClosed => _disposed;
  int get capturedFrames => _frames;
  Uri? get browserUri => _documentUri ?? _server?.entryUri;

  Future<void> start() => _startOperation ??= _start();

  Future<void> _start() async {
    final generation = ++_generation;
    try {
      final server = VrWebGameServer(manifest, loader);
      _server = server;
      await server.start(port: port);
      if (_disposed || generation != _generation) {
        await server.close();
        return;
      }
      final documents = VrWebGameDocumentPolicy(manifest, server.baseUri);
      final browser = HeadlessInAppWebView(
        initialSize: ui.Size(
          manifest.viewportWidth.toDouble(),
          manifest.viewportHeight.toDouble(),
        ),
        initialUrlRequest: URLRequest(url: WebUri(server.probeUri.toString())),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          javaScriptCanOpenWindowsAutomatically: false,
          supportMultipleWindows: false,
          useShouldOverrideUrlLoading: true,
          useShouldInterceptRequest: true,
          mediaPlaybackRequiresUserGesture: false,
          allowFileAccess: false,
          allowContentAccess: false,
          allowFileAccessFromFileURLs: false,
          allowUniversalAccessFromFileURLs: false,
          domStorageEnabled: true,
          databaseEnabled: true,
          geolocationEnabled: false,
          thirdPartyCookiesEnabled: false,
          isInspectable: false,
          offscreenPreRaster: true,
          transparentBackground: false,
        ),
        initialUserScripts: UnmodifiableListView([
          UserScript(
            source: vrWebGameBridgeScript(
              manifest.controls,
              manifest.controllerProfile,
            ),
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            forMainFrameOnly: true,
          ),
        ]),
        onWebViewCreated: (controller) {
          if (_disposed || generation != _generation) return;
          _web = controller;
          controller.addJavaScriptHandler(
            handlerName: 'vrlizateReady',
            callback: (arguments) async {
              if (arguments.length != 1 || arguments.single is! Map) {
                return false;
              }
              final data = arguments.single as Map;
              final navigation = _documentGeneration;
              final uri = Uri.tryParse(data['href']?.toString() ?? '');
              final current = Uri.tryParse(
                (await controller.getUrl())?.toString() ?? '',
              );
              if (_disposed ||
                  generation != _generation ||
                  navigation != _documentGeneration ||
                  !_preflightPassed ||
                  _error != null ||
                  data['type'] != 'vrlizate.ready.v1' ||
                  !const {
                    'bridge',
                    'keyboard',
                    'gamepad',
                  }.contains(data['input']) ||
                  uri == null ||
                  current == null ||
                  !documents.allows(uri) ||
                  !documents.allows(current) ||
                  uri.removeFragment() != _documentUri ||
                  current.removeFragment() != _documentUri) {
                return false;
              }
              _handshakeReady = true;
              _finishLoading(generation, navigation);
              return true;
            },
          );
        },
        onLoadStart: (_, url) {
          if (_disposed || generation != _generation || !_preflightPassed) {
            return;
          }
          final uri = Uri.tryParse(url?.toString() ?? '');
          if (uri == null || !documents.allows(uri)) {
            return;
          }
          _waitForReady(generation, uri);
        },
        shouldOverrideUrlLoading: (_, action) async {
          final uri = Uri.tryParse(action.request.url?.toString() ?? '');
          return uri != null &&
                  (_preflightPassed
                      ? documents.allows(uri)
                      : uri == server.probeUri)
              ? NavigationActionPolicy.ALLOW
              : NavigationActionPolicy.CANCEL;
        },
        shouldInterceptRequest: (_, request) async {
          final uri = Uri.tryParse(request.url.toString());
          if (uri != null &&
              (server.owns(uri) ||
                  (uri.scheme == 'https' &&
                      manifest.networkOrigins.any(
                        (origin) => origin.origin == uri.origin,
                      )) ||
                  const {'data', 'blob'}.contains(uri.scheme))) {
            return null;
          }
          return WebResourceResponse(
            statusCode: 403,
            reasonPhrase: 'Blocked',
            contentType: 'text/plain',
            data: Uint8List(0),
          );
        },
        onPermissionRequest: (_, request) async => PermissionResponse(
          resources: request.resources,
          action: PermissionResponseAction.DENY,
        ),
        onCreateWindow: (_, _) async => false,
        onLoadStop: (_, url) async {
          if (_disposed || generation != _generation) return;
          final uri = Uri.tryParse(url?.toString() ?? '');
          if (uri == null || !server.owns(uri) || _error != null) return;
          if (uri.path == server.probeUri.path) {
            if (_preflightRunning || _preflightPassed) return;
            _preflightRunning = true;
            try {
              _status = 'Comprobando compatibilidad del navegador…';
              _notify();
              dynamic report = await _web?.evaluateJavascript(
                source: vrWebGameCapabilitiesReportScript(
                  manifest.requirements,
                ),
              );
              if (report is String) report = jsonDecode(report);
              if (_disposed || generation != _generation) return;
              final missing = report is Map && report['missing'] is List
                  ? (report['missing'] as List).whereType<String>().toList()
                  : manifest.requirements;
              if (report is! Map ||
                  report['supported'] != true ||
                  missing.isNotEmpty) {
                _fail(
                  'Navegador no compatible con ${manifest.title}: '
                  '${missing.isEmpty ? 'no se pudo verificar compatibilidad' : missing.join(', ')}. '
                  'Comprueba la versión de Android System WebView.',
                );
                return;
              }
              _status = 'Preparando archivos iniciales del juego…';
              _notify();
              await loader.prefetchStartup();
              if (_disposed || generation != _generation) return;
              _preflightPassed = true;
              _waitForReady(generation, server.entryUri);
              await _web?.loadUrl(
                urlRequest: URLRequest(url: WebUri(server.entryUri.toString())),
              );
            } catch (error) {
              if (!_disposed && generation == _generation) {
                _fail(
                  'No se pudo comprobar o preparar ${manifest.title}: $error',
                );
              }
            } finally {
              _preflightRunning = false;
            }
            return;
          }
          if (!_preflightPassed ||
              !documents.allows(uri) ||
              uri.removeFragment() != _documentUri) {
            return;
          }
          final navigation = _documentGeneration;
          _entryLoaded = true;
          await _web?.evaluateJavascript(
            source:
                "window.__vrlizateHost?.notifyReady();window.postMessage({type:'vrlizate.probe.v1'},location.origin);",
          );
          _finishLoading(generation, navigation);
        },
        onReceivedError: (_, request, error) {
          if (_disposed || request.isForMainFrame != true) return;
          _fail('No se pudo cargar el juego: ${error.description}');
        },
        onReceivedHttpError: (_, request, response) {
          if (_disposed || request.isForMainFrame != true) return;
          _fail('No se pudo abrir el juego (HTTP ${response.statusCode}).');
        },
      );
      _browser = browser;
      await browser.run();
      if (_disposed || generation != _generation) await browser.dispose();
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _fail('No se pudo iniciar ${manifest.title}: $error');
    }
  }

  void _waitForReady(int generation, Uri document) {
    _documentGeneration++;
    _documentUri = document.removeFragment();
    _started = _entryLoaded = _handshakeReady = false;
    _waitingForReady = true;
    _clearInput();
    _captureTimer?.cancel();
    _status = 'Inicializando ${manifest.title} · esperando al juego…';
    _scheduleReadyTimeout(generation);
    _notify();
  }

  void _scheduleReadyTimeout(int generation) {
    _readyTimeout?.cancel();
    if (_paused || !_waitingForReady) return;
    _readyTimeout = Timer(const Duration(seconds: 90), () {
      if (!_disposed && generation == _generation && !_started) {
        _fail(
          '${manifest.title} no confirmó que está listo en 90 segundos. '
          'El paquete debe anunciar vrlizate.ready.v1 después de iniciar su interfaz.',
        );
      }
    });
  }

  void _finishLoading(int generation, int navigation) {
    if (_disposed ||
        generation != _generation ||
        navigation != _documentGeneration ||
        _error != null ||
        _started ||
        !_entryLoaded ||
        !_handshakeReady) {
      return;
    }
    _started = true;
    _waitingForReady = false;
    _readyTimeout?.cancel();
    _status = 'Juego listo · descargando recursos según se necesitan';
    _captureTimer = Timer.periodic(
      Duration(microseconds: 1000000 ~/ captureFramesPerSecond),
      (_) => unawaited(_capture(generation, navigation)),
    );
    if (_paused) unawaited(_setBrowserActivity(false));
    _notify();
  }

  Future<void> _capture(int generation, int navigation) async {
    final web = _web;
    if (_disposed ||
        _paused ||
        !_browserActive ||
        _capturing ||
        web == null ||
        !_started ||
        navigation != _documentGeneration ||
        _error != null) {
      return;
    }
    _capturing = true;
    try {
      final bytes = await web.takeScreenshot(
        screenshotConfiguration: ScreenshotConfiguration(
          compressFormat: CompressFormat.JPEG,
          quality: 85,
          snapshotWidth: manifest.viewportWidth.toDouble(),
        ),
      );
      if (bytes == null ||
          bytes.isEmpty ||
          bytes.length > 8 * 1024 * 1024 ||
          _disposed ||
          navigation != _documentGeneration ||
          generation != _generation) {
        return;
      }
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: manifest.viewportWidth,
        targetHeight: manifest.viewportHeight,
      );
      try {
        final frame = await codec.getNextFrame();
        if (_disposed ||
            generation != _generation ||
            navigation != _documentGeneration ||
            _paused) {
          frame.image.dispose();
          return;
        }
        final previous = _image;
        _image = frame.image;
        _frames++;
        _notify();
        // A WidgetComponent may still be painting the previous frame.
        if (previous != null) {
          SchedulerBinding.instance.addPostFrameCallback(
            (_) => previous.dispose(),
          );
          SchedulerBinding.instance.ensureVisualUpdate();
        }
      } finally {
        codec.dispose();
      }
    } catch (_) {
      if (!_disposed && generation == _generation) {
        _status = 'Esperando la siguiente imagen del juego…';
      }
    } finally {
      _capturing = false;
    }
  }

  /// Coalesces analog packets; slow platform calls cannot queue stale movement.
  void input({
    required Map<String, bool> buttons,
    double x = 0,
    double y = 0,
    double lookX = 0,
    double lookY = 0,
    double? pointerX,
    double? pointerY,
    bool pointerClick = false,
  }) {
    if (!ready || _paused || !_browserActive || _disposed) return;
    if (![x, y, lookX, lookY].every((value) => value.isFinite) ||
        pointerX != null && !pointerX.isFinite ||
        pointerY != null && !pointerY.isFinite) {
      unawaited(releaseInput());
      return;
    }
    if (_awaitNeutral) {
      if (buttons.values.any((down) => down) ||
          pointerClick ||
          [x, y, lookX, lookY].any((value) => value.abs() > .15)) {
        return;
      }
      _awaitNeutral = false;
    }
    double axis(double value) => value.isFinite ? value.clamp(-1.0, 1.0) : 0;
    final packet = <String, Object?>{
      'buttons': {
        for (final key in const [
          'a',
          'x',
          'y',
          'l',
          'r',
          'grip',
          'start',
          'select',
        ])
          key: buttons[key] ?? false,
      },
      'axes': {
        'x': axis(x),
        'y': axis(y),
        'lookX': axis(lookX),
        'lookY': axis(lookY),
      },
      if (pointerX != null && pointerX.isFinite)
        'pointerX': pointerX.clamp(0.0, 1.0),
      if (pointerY != null && pointerY.isFinite)
        'pointerY': pointerY.clamp(0.0, 1.0),
      'pointerClick': pointerClick,
    };
    final normalizedButtons = packet['buttons'] as Map<String, bool>;
    if (!mapEquals(_lastButtons, normalizedButtons) ||
        _lastPointerClick != pointerClick) {
      // Analog samples may be replaced; a short A press/release may not be.
      if (_buttonInputs.length >= 16) {
        unawaited(releaseInput());
        return;
      }
      _buttonInputs.add(packet);
    }
    _lastButtons = normalizedButtons;
    _lastPointerClick = pointerClick;
    _pendingInput = packet;
    if (!_sendingInput) unawaited(_flushInput());
  }

  Future<void> _flushInput() async {
    _sendingInput = true;
    try {
      while ((_buttonInputs.isNotEmpty || _pendingInput != null) &&
          ready &&
          !_paused &&
          _browserActive &&
          !_disposed) {
        final input = _buttonInputs.isNotEmpty
            ? _buttonInputs.removeFirst()
            : _pendingInput;
        if (identical(input, _pendingInput)) _pendingInput = null;
        await _evaluate('window.__vrlizateHost?.input(${jsonEncode(input)});');
      }
    } finally {
      _sendingInput = false;
    }
  }

  Future<void> sendKey(String code, {bool shift = false}) async {
    if (!ready ||
        _paused ||
        !RegExp(
          r'^(Key[A-Z]|Digit[0-9]|Arrow(Up|Down|Left|Right)|Enter|Escape|Space|Tab|Backspace|Delete)$',
        ).hasMatch(code)) {
      return;
    }
    await _evaluate('window.__vrlizateHost?.key(${jsonEncode(code)},$shift);');
  }

  void _clearInput() {
    _pendingInput = null;
    _buttonInputs.clear();
    _lastButtons = {};
    _lastPointerClick = false;
    _awaitNeutral = true;
  }

  Future<void> releaseInput() async {
    _clearInput();
    await _evaluate('window.__vrlizateHost?.release();');
  }

  Future<void> setPaused(bool value) async {
    if (_disposed || _paused == value || !value && _error != null) return;
    _paused = value;
    _scheduleReadyTimeout(_generation);
    _clearInput();
    await _setBrowserActivity(!value);
    _notify();
  }

  Future<void> _setBrowserActivity(bool active) {
    final generation = _generation;
    _browserActive = false;
    final operation = _activityQueue.then((_) async {
      if (_disposed || generation != _generation) return;
      // Resume the native WebView before asking its JS event loop to resume.
      if (active) {
        try {
          await _web?.resume();
        } catch (_) {}
      }
      if (_disposed || generation != _generation) return;
      await _evaluate(
        'window.__vrlizateHost?.lifecycle(${active ? 'true' : 'false'});',
      );
      if (_disposed || generation != _generation) return;
      if (!active) {
        try {
          await _web?.pauseAllMediaPlayback();
        } catch (_) {}
        try {
          await _web?.pause();
        } catch (_) {}
      }
      if (!_disposed && generation == _generation && active == !_paused) {
        _browserActive = active;
      }
    });
    _activityQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  void _fail(String message) {
    _error = message;
    _waitingForReady = false;
    _captureTimer?.cancel();
    _readyTimeout?.cancel();
    _clearInput();
    unawaited(setPaused(true));
    _notify();
  }

  Future<void> _evaluate(String code) {
    final generation = _generation;
    _inputQueue = _inputQueue.then((_) async {
      if (_disposed || generation != _generation) return;
      try {
        await _web?.evaluateJavascript(source: code);
      } catch (_) {}
    });
    return _inputQueue;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> close() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _captureTimer?.cancel();
    _readyTimeout?.cancel();
    _clearInput();
    final browser = _browser;
    _browser = null;
    _web = null;
    try {
      await browser?.dispose();
    } finally {
      await _server?.close();
      loader.close();
    }
    final image = _image;
    _image = null;
    if (image != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) => image.dispose());
      SchedulerBinding.instance.ensureVisualUpdate();
    }
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}
