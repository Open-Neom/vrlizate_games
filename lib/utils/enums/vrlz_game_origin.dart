/// Provenance of a loaded `.vrlz` game build.
enum VrlzGameOrigin {
  /// Bundled inside the application's Flutter `AssetBundle` (`assets/vrlz/*.vrlz`).
  asset,

  /// Loaded from a native device folder (`VrlzDirectoryStore`).
  directory,

  /// Downloaded and SHA-256 verified from an HTTPS URL or `VrlzWebCatalog`.
  cloud,
}
