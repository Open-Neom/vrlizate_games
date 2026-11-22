import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:vrlizate_apps/vrlizate_apps.dart'
    show isPrivateLanOrLoopbackHost;

/// Playback snapshot of the primary HTML5 `<video>` inside a domain WebView,
/// used to keep the Right Eye mirror synchronized in stereo VR Cinema mode.
typedef VrDomainWebVideoState = ({double currentTime, bool paused});

/// Controller for navigating, scrolling, and synchronizing a sandboxed
/// [VrHttpsDomainWebStage] from VR 1D/2D/3D joysticks or stereo eye mirrors.
class VrHttpsDomainWebStageController {
  InAppWebViewController? _web;

  void _attach(InAppWebViewController controller) => _web = controller;
  void _detach() => _web = null;

  bool get isAttached => _web != null;

  Future<void> loadUri(Uri uri) async {
    final web = _web;
    if (web == null || !VrHttpsDomainWebStage.isSafePublicDomainUri(uri)) {
      return;
    }
    await web.loadUrl(urlRequest: URLRequest(url: WebUri.uri(uri)));
  }

  Future<bool> canGoBack() async => (await _web?.canGoBack()) ?? false;
  Future<bool> canGoForward() async => (await _web?.canGoForward()) ?? false;

  Future<void> goBack() async {
    final web = _web;
    if (web != null && await web.canGoBack()) {
      await web.goBack();
    }
  }

  Future<void> goForward() async {
    final web = _web;
    if (web != null && await web.canGoForward()) {
      await web.goForward();
    }
  }

  Future<void> scrollBy(int deltaY) async {
    final web = _web;
    if (web == null || deltaY == 0) return;
    try {
      await web.evaluateJavascript(
        source: 'window.scrollBy({top:$deltaY,behavior:"auto"});',
      );
    } catch (_) {}
  }

  Future<void> scrollTo(int x, int y) async {
    final web = _web;
    if (web == null) return;
    try {
      await web.evaluateJavascript(
        source: 'window.scrollTo({left:$x,top:$y,behavior:"auto"});',
      );
    } catch (_) {}
  }

  Future<({int x, int y})?> getScrollPosition() async {
    final web = _web;
    if (web == null) return null;
    try {
      final raw = await web.evaluateJavascript(
        source:
            'JSON.stringify({x:Math.round(window.scrollX||0),y:Math.round(window.scrollY||0)});',
      );
      if (raw is! String || raw.isEmpty) return null;
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final x = (map['x'] as num?)?.round();
      final y = (map['y'] as num?)?.round();
      if (x == null || y == null) return null;
      return (x: x, y: y);
    } catch (_) {
      return null;
    }
  }

  /// Dispatches a synthetic click at normalized viewport coordinates
  /// `(nx, ny) ∈ [0.0, 1.0]` so joystick/laser `A` interactions trigger the
  /// exact same link or play control in both Left and Right stereo eyes.
  Future<void> dispatchClickNormalized(double nx, double ny) async {
    final web = _web;
    if (web == null || !nx.isFinite || !ny.isFinite) return;
    final cx = nx.clamp(0.0, 1.0);
    final cy = ny.clamp(0.0, 1.0);
    try {
      await web.evaluateJavascript(
        source: '''
(function(){
  var x = Math.round(window.innerWidth * $cx);
  var y = Math.round(window.innerHeight * $cy);
  var el = document.elementFromPoint(x, y);
  if (!el) return;
  if (typeof el.focus === 'function') { try { el.focus(); } catch(e){} }
  ['pointerdown','mousedown','pointerup','mouseup','click'].forEach(function(t){
    try {
      el.dispatchEvent(new MouseEvent(t, {bubbles:true,cancelable:true,clientX:x,clientY:y,view:window}));
    } catch(e){}
  });
})();
''',
      );
    } catch (_) {}
  }

  /// Forces every `<video>` and `<audio>` element inside this WebView to stay
  /// muted (used by the Right Eye mirror in stereo VR Cinema mode to avoid
  /// duplicate audio).
  Future<void> enforceMuted() async {
    final web = _web;
    if (web == null) return;
    try {
      await web.evaluateJavascript(source: _muteObserverScript);
    } catch (_) {}
  }

  Future<VrDomainWebVideoState?> getPrimaryVideoState() async {
    final web = _web;
    if (web == null) return null;
    try {
      final raw = await web.evaluateJavascript(
        source: '''
(function(){
  var vids = document.querySelectorAll('video');
  var best = null;
  var bestArea = -1;
  for (var i = 0; i < vids.length; i++) {
    var v = vids[i];
    if (v.readyState < 1) continue;
    var r = v.getBoundingClientRect();
    var area = Math.max(0, r.width * r.height);
    if (area > bestArea) { bestArea = area; best = v; }
  }
  if (!best) return '';
  return JSON.stringify({t: best.currentTime || 0, p: !!best.paused});
})();
''',
      );
      if (raw is! String || raw.isEmpty) return null;
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final t = (map['t'] as num?)?.toDouble();
      final p = map['p'] as bool?;
      if (t == null || !t.isFinite || p == null) return null;
      return (currentTime: t, paused: p);
    } catch (_) {
      return null;
    }
  }

  Future<void> syncVideoState({
    required double currentTime,
    required bool paused,
  }) async {
    final web = _web;
    if (web == null || !currentTime.isFinite) return;
    try {
      await web.evaluateJavascript(
        source: '''
(function(){
  var vids = document.querySelectorAll('video');
  for (var i = 0; i < vids.length; i++) {
    var v = vids[i];
    v.muted = true;
    v.volume = 0;
    if (v.readyState < 1) continue;
    if (Math.abs((v.currentTime || 0) - $currentTime) > 0.38) {
      try { v.currentTime = $currentTime; } catch(e){}
    }
    if ($paused) {
      if (!v.paused) { try { v.pause(); } catch(e){} }
    } else {
      if (v.paused) { try { var pr = v.play(); if (pr && pr.catch) pr.catch(function(){}); } catch(e){} }
    }
  }
})();
''',
      );
    } catch (_) {}
  }

  static const String _muteObserverScript = '''
(function(){
  function muteAll(){
    var els = document.querySelectorAll('video,audio');
    for (var i = 0; i < els.length; i++) {
      els[i].muted = true;
      els[i].volume = 0;
    }
  }
  muteAll();
  if (!window.__vrlzMuteObserver) {
    window.__vrlzMuteObserver = new MutationObserver(muteAll);
    if (document.documentElement) {
      window.__vrlzMuteObserver.observe(document.documentElement, {childList:true,subtree:true});
    }
  }
})();
''';
}

/// Sandboxed live HTTPS WebView stage for projecting user-owned public domains
/// and official streaming portals inside VR storefronts and Cine VR without
/// exposing local files, private LAN hosts, popups, or native permissions.
class VrHttpsDomainWebStage extends StatefulWidget {
  const VrHttpsDomainWebStage({
    super.key,
    required this.initialUri,
    this.controller,
    this.muted = false,
    this.onProgressChanged,
    this.onTitleChanged,
    this.onUriLoaded,
  });

  final Uri initialUri;
  final VrHttpsDomainWebStageController? controller;

  /// When `true` (e.g. the Right Eye mirror in Side-by-Side Stereo VR mode),
  /// keeps all HTML5 `<video>`/`<audio>` elements muted so only the Left Eye
  /// outputs audio.
  final bool muted;

  final ValueChanged<double>? onProgressChanged;
  final ValueChanged<String>? onTitleChanged;
  final ValueChanged<Uri>? onUriLoaded;

  static bool isSafePublicDomainUri(Uri uri) {
    if (uri.scheme != 'https') return false;
    if (uri.userInfo.isNotEmpty) return false;
    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty || host.length > 253) return false;
    if (!host.contains('.')) return false;
    if (host.startsWith('.') || host.endsWith('.') || host.contains('..')) {
      return false;
    }
    if (!RegExp(r'^[a-z0-9.-]+$').hasMatch(host)) return false;
    if (host.endsWith('.local') || host.endsWith('.internal')) return false;
    if (isPrivateLanOrLoopbackHost(host)) return false;
    return true;
  }

  @override
  State<VrHttpsDomainWebStage> createState() => _VrHttpsDomainWebStageState();
}

class _VrHttpsDomainWebStageState extends State<VrHttpsDomainWebStage> {
  @override
  void dispose() {
    widget.controller?._detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri.uri(widget.initialUri)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        javaScriptCanOpenWindowsAutomatically: false,
        supportMultipleWindows: false,
        useShouldOverrideUrlLoading: true,
        allowFileAccess: false,
        allowContentAccess: false,
        allowFileAccessFromFileURLs: false,
        allowUniversalAccessFromFileURLs: false,
        geolocationEnabled: false,
        thirdPartyCookiesEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
      ),
      onWebViewCreated: (controller) {
        widget.controller?._attach(controller);
      },
      onProgressChanged: (_, progress) {
        widget.onProgressChanged?.call(progress / 100.0);
      },
      onTitleChanged: (_, title) {
        if (title != null) widget.onTitleChanged?.call(title);
      },
      onLoadStop: (_, url) {
        if (widget.muted) {
          unawaited(widget.controller?.enforceMuted());
        }
        final parsed = url == null ? null : Uri.tryParse(url.toString());
        if (parsed != null &&
            VrHttpsDomainWebStage.isSafePublicDomainUri(parsed)) {
          widget.onUriLoaded?.call(parsed);
        }
      },
      shouldOverrideUrlLoading: (_, action) async {
        final target = action.request.url?.uriValue;
        if (target != null &&
            VrHttpsDomainWebStage.isSafePublicDomainUri(target)) {
          return NavigationActionPolicy.ALLOW;
        }
        return NavigationActionPolicy.CANCEL;
      },
    );
  }
}
