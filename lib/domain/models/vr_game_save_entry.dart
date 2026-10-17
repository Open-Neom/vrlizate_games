import 'dart:convert';
import 'dart:typed_data';

import '../../utils/constants/vr_games_constants.dart';

/// Serializable save-slot and high-score record for a `.vrlz` game.
class VrGameSaveEntry {
  VrGameSaveEntry({
    required this.gameId,
    this.slotIndex = VrGamesConstants.defaultSaveSlotIndex,
    this.highScore = 0,
    Uint8List? stateBytes,
    this.updatedAtIso = VrGamesConstants.defaultEpochIso,
  }) : stateBytes = stateBytes != null
           ? Uint8List.fromList(stateBytes)
           : Uint8List(0);

  final String gameId;
  final int slotIndex;
  final int highScore;
  final Uint8List stateBytes;
  final String updatedAtIso;

  bool get isValid =>
      gameId.trim().isNotEmpty &&
      slotIndex >= 0 &&
      slotIndex < VrGamesConstants.maxSaveSlotsPerGame &&
      highScore >= 0 &&
      updatedAtIso.trim().isNotEmpty;

  VrGameSaveEntry copyWith({
    String? gameId,
    int? slotIndex,
    int? highScore,
    Uint8List? stateBytes,
    String? updatedAtIso,
  }) {
    return VrGameSaveEntry(
      gameId: gameId ?? this.gameId,
      slotIndex: slotIndex ?? this.slotIndex,
      highScore: highScore ?? this.highScore,
      stateBytes: stateBytes ?? this.stateBytes,
      updatedAtIso: updatedAtIso ?? this.updatedAtIso,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    VrGamesConstants.keyGameId: gameId,
    VrGamesConstants.keySlotIndex: slotIndex,
    VrGamesConstants.keyHighScore: highScore,
    VrGamesConstants.keyStateBytesBase64: base64Encode(stateBytes),
    VrGamesConstants.keyUpdatedAtIso: updatedAtIso,
  };

  factory VrGameSaveEntry.fromJson(Map<String, Object?> json) {
    final encodedState =
        (json[VrGamesConstants.keyStateBytesBase64] as String?) ?? '';
    return VrGameSaveEntry(
      gameId: (json[VrGamesConstants.keyGameId] as String?) ?? '',
      slotIndex:
          (json[VrGamesConstants.keySlotIndex] as int?) ??
          VrGamesConstants.defaultSaveSlotIndex,
      highScore: (json[VrGamesConstants.keyHighScore] as int?) ?? 0,
      stateBytes: encodedState.isEmpty
          ? Uint8List(0)
          : base64Decode(encodedState),
      updatedAtIso:
          (json[VrGamesConstants.keyUpdatedAtIso] as String?) ??
          VrGamesConstants.defaultEpochIso,
    );
  }
}
