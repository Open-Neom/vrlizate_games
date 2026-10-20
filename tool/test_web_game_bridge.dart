import 'dart:io';
import 'package:vrlizate_games/src/web/vr_web_game_bridge.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    throw ArgumentError('Pass the Node.js executable.');
  }
  final directory = await Directory.systemTemp.createTemp('vr-bridge-test-');
  try {
    final script = File('${directory.path}/bridge.js');
    await script.writeAsString(
      vrWebGameBridgeScript({'A': 'KeyZ', 'UP': 'KeyW'}, 'dpad'),
    );
    final result = await Process.run(arguments.single, [
      'tool/test_web_game_bridge.mjs',
      script.path,
    ]);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) exitCode = result.exitCode;
  } finally {
    await directory.delete(recursive: true);
  }
}
