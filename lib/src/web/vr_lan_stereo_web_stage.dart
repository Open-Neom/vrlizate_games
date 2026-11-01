import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:vrlizate_apps/vrlizate_apps.dart'
    show isPrivateLanOrLoopbackHost;

/// Bridge controller for injecting 60 Hz 3-Node Faro poses and Joystick input
/// into an active Dual-Eye Stereo (`3D-VR`) LAN Web Stage.
class VrLanStereoWebStageController {
  InAppWebViewController? _web;
  bool _ready = false;

  bool get isReady => _ready && _web != null;

  void _attach(InAppWebViewController controller) {
    _web = controller;
  }

  void _markReady(bool value) {
    _ready = value;
  }

  void _detach() {
    _ready = false;
    _web = null;
  }

  Future<void> pushFaroPose(Map<String, Object?> pose) async {
    final web = _web;
    if (!_ready || web == null) return;
    final payload = jsonEncode(pose);
    try {
      await web.evaluateJavascript(
        source:
            'if(window.__vrlizatePushPose)window.__vrlizatePushPose($payload);',
      );
    } catch (_) {}
  }

  Future<void> sendVaultInput(Map<String, Object?> input) async {
    final web = _web;
    if (!_ready || web == null) return;
    final payload = jsonEncode(input);
    try {
      await web.evaluateJavascript(
        source:
            'if(window.__vrlizateVaultInput)window.__vrlizateVaultInput($payload);',
      );
    } catch (_) {}
  }
}

/// Renders an authenticated Desktop Bóveda LAN Dual-Eye Stereo (`3D-VR`) web
/// stream inside the Smartphone Visor while strictly confining navigation to
/// the paired private-LAN capability token prefix.
class VrLanStereoWebStage extends StatefulWidget {
  VrLanStereoWebStage({
    super.key,
    required this.stereoWebUrl,
    this.controller,
    this.onLoadReady,
    this.onLoadError,
  }) : _capabilityPrefix = _extractCapabilityPrefix(stereoWebUrl);

  final Uri stereoWebUrl;
  final VrLanStereoWebStageController? controller;
  final VoidCallback? onLoadReady;
  final void Function(String message)? onLoadError;
  final String _capabilityPrefix;

  static bool isAllowedVaultStereoUri(Uri uri) =>
      uri.scheme == 'http' &&
      isPrivateLanOrLoopbackHost(uri.host) &&
      uri.userInfo.isEmpty &&
      !uri.hasFragment &&
      uri.port >= 1 &&
      uri.port <= 65535 &&
      uri.pathSegments.where((s) => s.isNotEmpty).length >= 2;

  static String _extractCapabilityPrefix(Uri uri) {
    if (!isAllowedVaultStereoUri(uri)) {
      throw const FormatException(
        'Se requiere una URL privada de Bóveda LAN autenticada.',
      );
    }
    final token = uri.pathSegments.firstWhere((s) => s.isNotEmpty);
    return '/$token/';
  }

  bool ownsNavigationUri(Uri candidate) =>
      candidate.scheme == 'http' &&
      candidate.host == stereoWebUrl.host &&
      candidate.port == stereoWebUrl.port &&
      candidate.userInfo.isEmpty &&
      candidate.path.startsWith(_capabilityPrefix);

  @override
  State<VrLanStereoWebStage> createState() => _VrLanStereoWebStageState();
}

class _VrLanStereoWebStageState extends State<VrLanStereoWebStage> {
  @override
  void dispose() {
    widget.controller?._detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri.uri(widget.stereoWebUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        supportZoom: false,
        disableContextMenu: true,
        transparentBackground: false,
      ),
      onWebViewCreated: (controller) {
        widget.controller?._attach(controller);
      },
      shouldOverrideUrlLoading: (_, action) async {
        final target = action.request.url?.uriValue;
        if (target != null && widget.ownsNavigationUri(target)) {
          return NavigationActionPolicy.ALLOW;
        }
        return NavigationActionPolicy.CANCEL;
      },
      onLoadStop: (_, _) {
        widget.controller?._markReady(true);
        widget.onLoadReady?.call();
      },
      onReceivedError: (_, _, error) {
        widget.controller?._markReady(false);
        widget.onLoadError?.call(error.description);
      },
    );
  }
}
