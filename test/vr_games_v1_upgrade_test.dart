import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_games/vrlizate_games.dart';

void main() {
  group('VrArcadeCabinetStyle & VrArcadeCabinetSpec', () {
    test('validates dimensions and roundtrips JSON', () {
      const spec = VrArcadeCabinetSpec(
        gameId: 'org.vrlizate.games.neon_bastion',
        style: VrArcadeCabinetStyle.neonCyber,
        widthMeters: 0.78,
        heightMeters: 1.85,
        depthMeters: 0.84,
        screenTiltDegrees: 22.0,
        primaryMarqueeArgb: 0xFF00F0FF,
        accentMarqueeArgb: 0xFFFF00A0,
      );

      expect(spec.isValid, isTrue);
      final restored = VrArcadeCabinetSpec.fromJson(spec.toJson());
      expect(restored, equals(spec));

      final invalid = spec.copyWith(screenTiltDegrees: 85.0);
      expect(invalid.isValid, isFalse);
    });
  });

  group('VrGameSaveEntry & VrGameSaveStore', () {
    test('stores high scores and save states and serializes to JSON', () {
      final store = VrGameSaveStore();
      store.recordHighScore(
        'org.vrlizate.games.nova',
        12500,
        slotIndex: 0,
        updatedAtIso: '2026-10-17T12:00:00Z',
      );
      store.recordHighScore(
        'org.vrlizate.games.nova',
        9800,
        slotIndex: 0,
        updatedAtIso: '2026-10-17T12:05:00Z',
      );
      expect(store.highScoreFor('org.vrlizate.games.nova'), 12500);

      store.saveEntry(
        VrGameSaveEntry(
          gameId: 'org.vrlizate.games.nova',
          slotIndex: 1,
          highScore: 18400,
          stateBytes: Uint8List.fromList(<int>[1, 2, 3, 4, 5]),
          updatedAtIso: '2026-10-17T12:10:00Z',
        ),
      );
      expect(store.highScoreFor('org.vrlizate.games.nova'), 18400);

      final serialized = store.toJsonString();
      final restoredStore = VrGameSaveStore()..restoreFromJsonString(serialized);
      expect(restoredStore.highScoreFor('org.vrlizate.games.nova'), 18400);
      final slot1 = restoredStore.loadEntry(
        'org.vrlizate.games.nova',
        slotIndex: 1,
      );
      expect(slot1, isNotNull);
      expect(slot1!.stateBytes, orderedEquals(<int>[1, 2, 3, 4, 5]));
    });
  });

  group('VrHomeHoldExitPolicy', () {
    test('tracks holding center/home button for 3 to 5 seconds with alert and exit triggers', () {
      final policy = VrHomeHoldExitPolicy(
        requiredHoldMs: 4000,
        alertThresholdProgress: 0.25,
      );

      expect(policy.progress, 0.0);
      expect(policy.shouldShowAlert, isFalse);
      expect(policy.shouldTriggerExit, isFalse);

      policy.onButtonDown();
      policy.advanceMs(500);
      expect(policy.progress, closeTo(0.125, 1e-6));
      expect(policy.shouldShowAlert, isFalse);

      policy.advanceMs(600); // 1100 ms -> 0.275 progress
      expect(policy.shouldShowAlert, isTrue);
      expect(policy.shouldTriggerExit, isFalse);

      policy.onButtonUp();
      expect(policy.isHolding, isFalse);
      expect(policy.progress, 0.0);
      expect(policy.shouldShowAlert, isFalse);

      policy.onButtonDown();
      policy.update(const Duration(milliseconds: 4000));
      expect(policy.progress, 1.0);
      expect(policy.shouldShowAlert, isFalse);
      expect(policy.shouldTriggerExit, isTrue);
    });
  });
}
