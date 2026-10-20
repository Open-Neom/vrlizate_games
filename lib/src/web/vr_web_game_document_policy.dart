import 'package:vrlizate_apps/vrlizate_apps.dart';

/// Main documents must be explicit HTML resources on this token's origin.
/// A package may contain a selector and several games without gaining access
/// to arbitrary manifest scripts, external sites, query endpoints or siblings.
final class VrWebGameDocumentPolicy {
  VrWebGameDocumentPolicy(VrlzWebGameManifest manifest, this.baseUri)
    : _documents = {
        for (final file in manifest.files)
          if (const {
            'text/html',
            'application/xhtml+xml',
          }.contains(file.mediaType.split(';').first.trim().toLowerCase()))
            baseUri.resolve(file.path).toString(),
      };

  final Uri baseUri;
  final Set<String> _documents;

  bool allows(Uri candidate) =>
      candidate.userInfo.isEmpty &&
      candidate.query.isEmpty &&
      _documents.contains(candidate.removeFragment().toString());
}
