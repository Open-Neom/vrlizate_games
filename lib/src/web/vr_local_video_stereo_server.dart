import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// Projection format for a local video played in `1D`, `2D` stereo, or `3D` VR.
enum VrLocalVideoStereoFormat {
  cinemaFlat,
  cinemaSbs3d,
  equirect360Mono,
  equirect360Sbs,
  equirect360TopBottom,
  vr180Sbs;

  String get labelEs => switch (this) {
    VrLocalVideoStereoFormat.cinemaFlat => 'Cine 2D en Sala',
    VrLocalVideoStereoFormat.cinemaSbs3d => 'Cine 3D SBS',
    VrLocalVideoStereoFormat.equirect360Mono => 'Domo 360°',
    VrLocalVideoStereoFormat.equirect360Sbs => '360° Estéreo SBS',
    VrLocalVideoStereoFormat.equirect360TopBottom => '360° Top-Bottom',
    VrLocalVideoStereoFormat.vr180Sbs => 'VR 180° SBS',
  };

  static VrLocalVideoStereoFormat inferFromFileName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.contains('180') &&
        (lower.contains('sbs') || lower.contains('lr'))) {
      return VrLocalVideoStereoFormat.vr180Sbs;
    }
    if (lower.contains('360') &&
        (lower.contains('tb') || lower.contains('ou'))) {
      return VrLocalVideoStereoFormat.equirect360TopBottom;
    }
    if (lower.contains('360') &&
        (lower.contains('sbs') || lower.contains('lr'))) {
      return VrLocalVideoStereoFormat.equirect360Sbs;
    }
    if (lower.contains('360')) {
      return VrLocalVideoStereoFormat.equirect360Mono;
    }
    if (lower.contains('sbs') || lower.contains('3d')) {
      return VrLocalVideoStereoFormat.cinemaSbs3d;
    }
    return VrLocalVideoStereoFormat.cinemaFlat;
  }
}

/// Loopback (`127.0.0.1`) capability-scoped HTTP `206 Byte-Range` server for a
/// single user-selected local video file, paired with an HTML5 Canvas dual-eye
/// (`2D`/`3D` stereo) and monoscopic (`1D`) projector compatible with
/// `VrLanStereoWebStage`.
///
/// Never exposes arbitrary directories or files outside the authorized [file].
class VrLocalVideoStereoServer {
  VrLocalVideoStereoServer._({
    required this.file,
    required this.title,
    required this.initialFormat,
    required this.initialStereo,
    required this.mimeType,
    required HttpServer server,
    required String token,
  }) : _server = server,
       _token = token;

  static const Set<String> supportedExtensions = {
    'mp4',
    'webm',
    'mov',
    'm4v',
    'mkv',
  };

  final File file;
  final String title;
  final VrLocalVideoStereoFormat initialFormat;
  final bool initialStereo;
  final String mimeType;
  final HttpServer _server;
  final String _token;
  bool _closed = false;

  /// Capability URL for `VrLanStereoWebStage` (`http://127.0.0.1:<port>/<token>/player`).
  Uri get playerUri =>
      Uri.parse('http://127.0.0.1:${_server.port}/$_token/player');

  /// Raw HTTP `206 Byte-Range` video URL (`http://127.0.0.1:<port>/<token>/video`).
  Uri get videoUri =>
      Uri.parse('http://127.0.0.1:${_server.port}/$_token/video');

  int get port => _server.port;

  static String mimeTypeForName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    return 'video/mp4';
  }

  /// Starts a loopback server authorized exclusively for [filePath].
  static Future<VrLocalVideoStereoServer> start({
    required String filePath,
    String? title,
    VrLocalVideoStereoFormat? format,
    bool stereo = false,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('El archivo de video no existe.', filePath);
    }
    final fileName = file.uri.pathSegments.lastWhere(
      (segment) => segment.isNotEmpty,
      orElse: () => 'video.mp4',
    );
    final resolvedTitle = (title != null && title.trim().isNotEmpty)
        ? title.trim()
        : fileName;
    final resolvedFormat =
        format ?? VrLocalVideoStereoFormat.inferFromFileName(fileName);
    final token = _randomToken();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final instance = VrLocalVideoStereoServer._(
      file: file,
      title: resolvedTitle,
      initialFormat: resolvedFormat,
      initialStereo: stereo,
      mimeType: mimeTypeForName(fileName),
      server: server,
      token: token,
    );
    server.listen(instance._handleRequest);
    return instance;
  }

  static String _randomToken() {
    final rng = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    try {
      final path = request.uri.path;
      if (path == '/$_token/player') {
        if (request.method != 'GET' && request.method != 'HEAD') {
          response.statusCode = HttpStatus.methodNotAllowed;
          await response.close();
          return;
        }
        final html = _buildPlayerHtml();
        final bytes = utf8.encode(html);
        response.statusCode = HttpStatus.ok;
        response.headers
          ..set(HttpHeaders.contentTypeHeader, 'text/html; charset=utf-8')
          ..set(HttpHeaders.cacheControlHeader, 'no-store');
        response.contentLength = bytes.length;
        if (request.method == 'GET') response.add(bytes);
        await response.close();
        return;
      }

      if (path == '/$_token/video') {
        if (request.method != 'GET' && request.method != 'HEAD') {
          response.statusCode = HttpStatus.methodNotAllowed;
          await response.close();
          return;
        }
        await _serveVideoWithRanges(request, response);
        return;
      }

      response.statusCode = HttpStatus.notFound;
      await response.close();
    } catch (_) {
      try {
        response.statusCode = HttpStatus.internalServerError;
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> _serveVideoWithRanges(
    HttpRequest request,
    HttpResponse response,
  ) async {
    final total = await file.length();
    response.headers
      ..set(HttpHeaders.contentTypeHeader, mimeType)
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.cacheControlHeader, 'no-store');

    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    if (rangeHeader == null || !rangeHeader.startsWith('bytes=')) {
      response.statusCode = HttpStatus.ok;
      response.contentLength = total;
      if (request.method == 'GET') {
        await response.addStream(file.openRead());
      }
      await response.close();
      return;
    }

    final spec = rangeHeader.substring(6).split(',').first.trim();
    final parts = spec.split('-');
    if (parts.length != 2) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
      await response.close();
      return;
    }
    int start;
    int end;
    if (parts[0].isEmpty) {
      final suffix = int.tryParse(parts[1]) ?? 0;
      start = math.max(0, total - suffix);
      end = math.max(0, total - 1);
    } else {
      start = int.tryParse(parts[0]) ?? 0;
      end = parts[1].isEmpty ? total - 1 : (int.tryParse(parts[1]) ?? total - 1);
    }
    if (total <= 0 || start < 0 || start >= total || end < start) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
      await response.close();
      return;
    }
    end = math.min(end, total - 1);
    final length = end - start + 1;
    response.statusCode = HttpStatus.partialContent;
    response.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes $start-$end/$total',
    );
    response.contentLength = length;
    if (request.method == 'GET') {
      await response.addStream(file.openRead(start, end + 1));
    }
    await response.close();
  }

  String _buildPlayerHtml() {
    final cfg = jsonEncode({
      'title': title,
      'videoUrl': '/$_token/video',
      'format': initialFormat.name,
      'stereo': initialStereo,
    });
    return '''<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<style>
html,body{margin:0;padding:0;width:100%;height:100%;background:#040711;overflow:hidden;touch-action:none;font-family:system-ui,sans-serif;}
#stage{position:fixed;inset:0;width:100vw;height:100vh;display:block;}
#srcVideo{position:fixed;width:2px;height:2px;opacity:0.001;pointer-events:none;}
</style>
</head>
<body>
<canvas id="stage"></canvas>
<video id="srcVideo" playsinline webkit-playsinline preload="auto" crossorigin="anonymous"></video>
<script>
const CFG = $cfg;
const canvas = document.getElementById('stage');
const ctx = canvas.getContext('2d', { alpha: false });
const video = document.getElementById('srcVideo');
let stereo = !!CFG.stereo;
let format = CFG.format || 'cinemaFlat';
let yaw = 0, pitch = 0, yawOffset = 0, zoom = 1.0;
let stickX = 0, stickY = 0;
let headX = 0, headY = 0;
let dragActive = false, lastX = 0, lastY = 0;

function resize() {
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  canvas.width = Math.max(2, Math.floor(window.innerWidth * dpr));
  canvas.height = Math.max(2, Math.floor(window.innerHeight * dpr));
}
window.addEventListener('resize', resize);
resize();

video.src = CFG.videoUrl;
video.loop = false;
video.play().catch(() => { video.muted = true; video.play().catch(() => {}); });

canvas.addEventListener('pointerdown', (e) => {
  dragActive = true;
  lastX = e.clientX;
  lastY = e.clientY;
  if (video.paused) {
    video.muted = false;
    video.play().catch(() => {});
  }
});
window.addEventListener('pointermove', (e) => {
  if (!dragActive) return;
  const dx = e.clientX - lastX;
  const dy = e.clientY - lastY;
  lastX = e.clientX;
  lastY = e.clientY;
  yaw -= dx * 0.0045;
  pitch = Math.max(-1.1, Math.min(1.1, pitch - dy * 0.0038));
});
window.addEventListener('pointerup', () => { dragActive = false; });

window.__vrlizatePushPose = function(p) {
  if (!p) return;
  if (p.head) {
    headX = Number(p.head.x || 0);
    headY = Number(p.head.y || 1.6) - 1.6;
  }
  if (typeof p.stereo === 'boolean') stereo = p.stereo;
};

window.__vrlizateVaultInput = function(msg) {
  if (!msg) return;
  if (typeof msg.sx === 'number') stickX = msg.sx;
  if (typeof msg.sy === 'number') stickY = msg.sy;
  if (typeof msg.stereo === 'boolean') stereo = msg.stereo;
  if (typeof msg.format === 'string') format = msg.format;
  switch (msg.action) {
    case 'togglePlay':
      if (video.paused) { video.muted = false; video.play().catch(() => {}); }
      else { video.pause(); }
      break;
    case 'play':
      video.muted = false; video.play().catch(() => {});
      break;
    case 'pause':
      video.pause();
      break;
    case 'toggleMute':
      video.muted = !video.muted;
      break;
    case 'seekDelta': {
      const delta = Number(msg.seconds || 0);
      const dur = Number.isFinite(video.duration) ? video.duration : 1e9;
      video.currentTime = Math.max(0, Math.min(dur, (video.currentTime || 0) + delta));
      break;
    }
    case 'recenter':
      yawOffset = yaw;
      pitch = 0;
      zoom = 1.0;
      break;
    case 'toggleStereo':
      stereo = !stereo;
      break;
  }
};

function drawViewport(eyeIndex, eyeCount) {
  const vpW = canvas.width / eyeCount;
  const vpH = canvas.height;
  const ox = eyeIndex * vpW;
  ctx.save();
  ctx.beginPath();
  ctx.rect(ox, 0, vpW, vpH);
  ctx.clip();
  ctx.translate(ox, 0);

  const bg = ctx.createRadialGradient(vpW * 0.5, vpH * 0.45, vpH * 0.05, vpW * 0.5, vpH * 0.5, vpW * 0.9);
  bg.addColorStop(0, '#0f1d38');
  bg.addColorStop(1, '#03060d');
  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, vpW, vpH);

  const lookYaw = (yaw - yawOffset) + stickX * 0.65;
  const lookPitch = Math.max(-1.1, Math.min(1.1, pitch + stickY * 0.45));

  if (video.readyState >= 2) {
    const vw = video.videoWidth || 1920;
    const vh = video.videoHeight || 1080;
    let sx = 0, sy = 0, sw = vw, sh = vh;
    const activeEye = eyeCount === 2 ? eyeIndex : 0;
    if (format === 'equirect360Sbs' || format === 'vr180Sbs' || format === 'cinemaSbs3d') {
      sw = vw * 0.5;
      sx = activeEye === 0 ? 0 : sw;
    } else if (format === 'equirect360TopBottom') {
      sh = vh * 0.5;
      sy = activeEye === 0 ? 0 : sh;
    }

    if (format.startsWith('equirect360') || format === 'vr180Sbs') {
      const panU = (((lookYaw / (Math.PI * 2)) % 1) + 1) % 1;
      const cropW = sw * (format === 'vr180Sbs' ? 0.65 : 0.48);
      const cropH = sh * 0.62;
      const uStart = sx + Math.max(0, Math.min(sw - cropW, panU * (sw - cropW)));
      const vStart = sy + Math.max(0, Math.min(sh - cropH, (0.5 - lookPitch * 0.45) * (sh - cropH)));
      ctx.drawImage(video, uStart, vStart, cropW, cropH, 0, 0, vpW, vpH);
    } else {
      const aspect = (sw / Math.max(1, sh));
      const pad = eyeCount === 2 ? 0.88 : 0.94;
      let drawW = vpW * pad * zoom;
      let drawH = drawW / aspect;
      if (drawH > vpH * pad) {
        drawH = vpH * pad;
        drawW = drawH * aspect;
      }
      const parallaxX = (eyeCount === 2 ? (eyeIndex === 0 ? 8 : -8) : 0) - headX * 60;
      const parallaxY = headY * 45;
      const dx = (vpW - drawW) * 0.5 + parallaxX;
      const dy = (vpH - drawH) * 0.5 + parallaxY;
      ctx.strokeStyle = 'rgba(0, 229, 255, 0.55)';
      ctx.lineWidth = 2;
      ctx.strokeRect(dx - 2, dy - 2, drawW + 4, drawH + 4);
      ctx.drawImage(video, sx, sy, sw, sh, dx, dy, drawW, drawH);
    }
  } else {
    ctx.fillStyle = '#d8e9ff';
    ctx.font = '600 ' + Math.max(14, Math.floor(vpH * 0.032)) + 'px system-ui';
    ctx.textAlign = 'center';
    ctx.fillText('Cargando video local…', vpW * 0.5, vpH * 0.5);
  }
  ctx.restore();
}

function frame() {
  if (Math.abs(stickX) > 0.08 && (format.startsWith('equirect360') || format === 'vr180Sbs')) {
    yaw += stickX * 0.024;
  }
  if (stereo) {
    drawViewport(0, 2);
    drawViewport(1, 2);
    ctx.fillStyle = '#000';
    ctx.fillRect(canvas.width * 0.5 - 1, 0, 2, canvas.height);
  } else {
    drawViewport(0, 1);
  }
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
</script>
</body>
</html>''';
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _server.close(force: true);
  }
}
