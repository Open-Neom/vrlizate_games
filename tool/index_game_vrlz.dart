import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:vrlizate_games/vrlizate_games.dart';
import 'package:vrlizate_games/vrlizate_games_io.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.contains('--help')) {
    stdout.writeln(
      'Usage: dart run tool/index_game_vrlz.dart DIRECTORY [--output catalog.json]',
    );
    if (arguments.isEmpty) exitCode = 64;
    return;
  }
  final directoryPath = arguments.first;
  String? outputPath;
  if (arguments.length >= 3 && arguments[1] == '--output') {
    outputPath = arguments[2];
  }
  final store = VrlzDirectoryStore(directoryPath);
  final snapshot = await store.scan();
  final packages = [
    for (final entry in snapshot.entries)
      if (entry.metadata.kind == VrlzPackageKind.nes ||
          entry.metadata.kind == VrlzPackageKind.retro)
        {
          'id': entry.metadata.id,
          'title': entry.metadata.title,
          'url': Uri.encodeComponent(entry.fileName),
          'sha256': entry.fingerprint,
        },
  ];
  final bytes = Uint8List.fromList(
    utf8.encode(
      '${const JsonEncoder.withIndent('  ').convert({'formatVersion': 1, 'packages': packages})}\n',
    ),
  );
  VrlzWebCatalog.decode(
    bytes,
    source: Uri.parse('https://vrlz-games-index.invalid/catalog.json'),
  );
  final out = outputPath != null
      ? File(outputPath)
      : File('${Directory(directoryPath).path}/catalog.json');
  await out.parent.create(recursive: true);
  await out.writeAsBytes(bytes, flush: true);
  stdout.writeln(
    'Indexed ${packages.length} VRLZ game packages into ${out.path}.',
  );
}
