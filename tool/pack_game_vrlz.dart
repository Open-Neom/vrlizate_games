import 'dart:convert';
import 'dart:io';

import 'package:vrlizate_games/vrlizate_games.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help') || arguments.isEmpty) {
    stdout.writeln(
      'Usage:\n'
      '  dart run tool/pack_game_vrlz.dart --nes INPUT.nes OUTPUT.vrlz '
      '--id org.example.nes_game --title "NES Game" '
      '--license-file LICENSE.txt --source-url https://example.org/source '
      '[--description "Text"]\n'
      '  dart run tool/pack_game_vrlz.dart --retro INPUT.level.json OUTPUT.vrlz '
      '--id org.example.retro_game --title "Retro Game" '
      '--license-file LICENSE.txt [--description "Text"]\n',
    );
    if (arguments.isEmpty) exitCode = 64;
    return;
  }
  try {
    final options = <String, String>{};
    final positional = <String>[];
    const allowed = {
      '--id',
      '--title',
      '--description',
      '--nes',
      '--retro',
      '--license-file',
      '--source-url',
    };
    for (var i = 0; i < arguments.length; i++) {
      final arg = arguments[i];
      if (arg.startsWith('--')) {
        if (!allowed.contains(arg) ||
            options.containsKey(arg) ||
            i + 1 >= arguments.length) {
          throw FormatException('Unknown, duplicate or incomplete option: $arg');
        }
        options[arg] = arguments[++i];
      } else {
        positional.add(arg);
      }
    }
    final nesPath = options['--nes'];
    final retroPath = options['--retro'];
    if ((nesPath == null && retroPath == null) ||
        (nesPath != null && retroPath != null)) {
      throw const FormatException('Specify exactly one of --nes or --retro.');
    }
    if (positional.length != 1 ||
        !options.containsKey('--id') ||
        !options.containsKey('--title') ||
        !options.containsKey('--license-file')) {
      throw const FormatException(
        'Provide OUTPUT.vrlz, --id, --title, and --license-file.',
      );
    }
    final output = File(positional.single);
    if (!output.path.toLowerCase().endsWith('.vrlz')) {
      throw const FormatException('Output must end with .vrlz');
    }
    final license = await File(options['--license-file']!).readAsString();
    final description = options['--description'] ?? '';
    final bytes = nesPath != null
        ? VrlzGameAuthoring.encodeNesGame(
            romBytes: await File(nesPath).readAsBytes(),
            id: options['--id']!,
            title: options['--title']!,
            description: description,
            license: license,
            sourceUrl: options['--source-url'] ?? '',
          )
        : VrlzGameAuthoring.encodeRetroGame(
            level: VrlzRetroLevel.fromJson(
              jsonDecode(await File(retroPath!).readAsString())
                  as Map<String, Object?>,
            ),
            id: options['--id']!,
            title: options['--title']!,
            description: description,
            license: license,
          );
    await output.parent.create(recursive: true);
    await output.writeAsBytes(bytes, flush: true);
    final decoded = VrlzGamePackage.decode(bytes);
    stdout.writeln(
      '${output.path}: ${bytes.length} bytes · ${decoded.runtime} (${decoded.kind.name})',
    );
  } on Object catch (error) {
    stderr.writeln('Cannot pack VRLZ game: $error');
    exitCode = 1;
  }
}
