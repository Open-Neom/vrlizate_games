import 'dart:convert';

import 'package:vrlizate_apps/vrlizate_apps.dart';

/// A synchronous browser expression suitable for a host-owned isolated probe.
/// No game entrypoint, remote script or native permission is involved.
String vrWebGameCapabilitiesProbeScript(Iterable<String> requirements) =>
    '(${vrWebGameCapabilitiesReportScript(requirements)}).supported';

/// Returns a JavaScript expression evaluating to `{supported, missing}`.
/// WebGL resources are released even when extension lookup raises an error.
String vrWebGameCapabilitiesReportScript(Iterable<String> requirements) {
  final requested = List<String>.unmodifiable(requirements);
  if (requested.length > 3 ||
      requested.toSet().length != requested.length ||
      requested.any(
        (value) => !VrlzWebGameManifest.browserRequirements.contains(value),
      )) {
    throw ArgumentError.value(
      requested,
      'requirements',
      'Unsupported browser requirements',
    );
  }
  return '''(() => {
  const required = ${jsonEncode(requested)};
  const missing = [];
  for (const requirement of required) {
    let supported = false;
    try {
      if (requirement === 'wasm-gc') {
        // Same GC structure-type probe used by Flutter's web loader.
        supported = typeof WebAssembly === 'object' &&
          typeof WebAssembly.validate === 'function' &&
          WebAssembly.validate(new Uint8Array([0,97,115,109,1,0,0,0,1,5,1,95,1,120,0]));
      } else if (requirement === 'cross-origin-isolation') {
        supported = globalThis.crossOriginIsolated === true;
      } else if (requirement === 'webgl2') {
        let canvas;
        let context;
        try {
          canvas = document.createElement('canvas');
          context = canvas.getContext('webgl2');
          supported = context != null;
        } finally {
          try {
            context?.getExtension('WEBGL_lose_context')?.loseContext();
          } finally {
            if (canvas) { canvas.width = 0; canvas.height = 0; }
          }
        }
      }
    } catch (_) {
      supported = false;
    }
    if (!supported) missing.push(requirement);
  }
  return {supported: missing.length === 0, missing};
})()''';
}
