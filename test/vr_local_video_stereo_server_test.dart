import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vrlizate_games/vrlizate_games_web_runtime.dart';

void main() {
  test('VrLocalVideoStereoServer infers stereo formats from filenames', () {
    expect(
      VrLocalVideoStereoFormat.inferFromFileName('concert_360_sbs.mp4'),
      VrLocalVideoStereoFormat.equirect360Sbs,
    );
    expect(
      VrLocalVideoStereoFormat.inferFromFileName('reef_vr180_lr.webm'),
      VrLocalVideoStereoFormat.vr180Sbs,
    );
    expect(
      VrLocalVideoStereoFormat.inferFromFileName('nature_360_tb.mp4'),
      VrLocalVideoStereoFormat.equirect360TopBottom,
    );
    expect(
      VrLocalVideoStereoFormat.inferFromFileName('documental_360.mov'),
      VrLocalVideoStereoFormat.equirect360Mono,
    );
    expect(
      VrLocalVideoStereoFormat.inferFromFileName('avatar_3d_sbs.mp4'),
      VrLocalVideoStereoFormat.cinemaSbs3d,
    );
    expect(
      VrLocalVideoStereoFormat.inferFromFileName('pelicula_clasica.mp4'),
      VrLocalVideoStereoFormat.cinemaFlat,
    );
  });

  test(
    'VrLocalVideoStereoServer serves player HTML, HTTP 206 byte ranges, and blocks wrong tokens',
    () async {
      final dir = Directory.systemTemp.createTempSync('vr_local_vid_test_');
      final file = File('${dir.path}/demo_360_sbs.mp4')
        ..writeAsBytesSync(List<int>.generate(1024, (i) => i % 251));
      final server = await VrLocalVideoStereoServer.start(
        filePath: file.path,
        title: 'Demo 360',
        stereo: true,
      );
      final client = http.Client();
      try {
        expect(VrLanStereoWebStage.isAllowedVaultStereoUri(server.playerUri), isTrue);

        final playerRes = await client.get(server.playerUri);
        expect(playerRes.statusCode, 200);
        expect(playerRes.body, contains('__vrlizateVaultInput'));
        expect(playerRes.body, contains('equirect360Sbs'));

        final rangeRes = await client.get(
          server.videoUri,
          headers: const {'Range': 'bytes=10-19'},
        );
        expect(rangeRes.statusCode, 206);
        expect(rangeRes.headers['content-range'], 'bytes 10-19/1024');
        expect(rangeRes.bodyBytes, List<int>.generate(10, (i) => (i + 10) % 251));

        final wrongToken = server.videoUri.replace(path: '/wrongtoken/video');
        final forbidden = await client.get(wrongToken);
        expect(forbidden.statusCode, 404);
      } finally {
        client.close();
        await server.close();
        dir.deleteSync(recursive: true);
      }
    },
  );
}
