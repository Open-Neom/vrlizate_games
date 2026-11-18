import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:vrlizate_apps/vrlizate_apps.dart'
    show isPrivateLanOrLoopbackHost;

/// Controller for navigating and scrolling a sandboxed [VrHttpsDomainWebStage]
/// from VR 1D/2D/3D joysticks or spatial pointers.
class VrHttpsDomainWebStageController {
  InAppWebViewController? _web;

  void _attach(InAppWebViewController controller) => _web = controller;
  void _detach() => _web = null;

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
}

/// Sandboxed live HTTPS WebView stage for projecting user-owned public domains
/// inside rentable VR storefronts (`EN RENTA · Tu Dominio VR`) without
/// exposing local files, private LAN hosts, popups, or native permissions.
class VrHttpsDomainWebStage extends StatefulWidget {
  const VrHttpsDomainWebStage({
    super.key,
    required this.initialUri,
    this.controller,
    this.onProgressChanged,
    this.onTitleChanged,
    this.onUriLoaded,
  });

  final Uri initialUri;
  final VrHttpsDomainWebStageController? controller;
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
        thirdPartyCookiesEnabled: false,
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
