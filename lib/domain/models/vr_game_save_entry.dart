import 'dart:convert';
import 'dart:typed_data';

import '../../utils/constants/vr_games_constants.dart';

/// Serializable save-slot and high-score record for a `.vrlz` game.
///
/// Internal state buffers are defensively copied on construction and on every
/// read of [stateBytes] so callers cannot mutate stored save states in place.
class VrGameSaveEntry {
  VrGameSaveEntry({
    required this.gameId,
    this.slotIndex = VrGamesConstants.defaultSaveSlotIndex,
    this.highScore = 0,
    Uint8List? stateBytes,
    this.updatedAtIso = VrGamesConstants.defaultEpochIso,
  }) : _stateBytes = stateBytes != null
           ? Uint8List.fromList(stateBytes)
           : Uint8List(0);

  final String gameId;
  final int slotIndex;
  final int highScore;
  final Uint8List _stateBytes;
  final String updatedAtIso;

  /// Returns a fresh defensive copy of the saved state bytes.
  Uint8List get stateBytes => Uint8List.fromList(_stateBytes);

  /// Length in bytes of the saved state without allocating a copy.
  int get stateByteLength => _stateBytes.length;

  bool get isValid =>
      gameId.trim().isNotEmpty &&
      gameId.length <= VrGamesConstants.maxGameIdLength &&
      !gameId.contains('\u0000') &&
      slotIndex >= 0 &&
      slotIndex < VrGamesConstants.maxSaveSlotsPerGame &&
      highScore >= 0 &&
      _stateBytes.length <= VrGamesConstants.maxSaveStateBytes &&
      updatedAtIso.trim().isNotEmpty &&
      updatedAtIso.length <= VrGamesConstants.maxUpdatedAtIsoLength &&
      !updatedAtIso.contains('\u0000');

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
      stateBytes: stateBytes ?? _stateBytes,
      updatedAtIso: updatedAtIso ?? this.updatedAtIso,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    VrGamesConstants.keyGameId: gameId,
    VrGamesConstants.keySlotIndex: slotIndex,
    VrGamesConstants.keyHighScore: highScore,
    VrGamesConstants.keyStateBytesBase64: base64Encode(_stateBytes),
    VrGamesConstants.keyUpdatedAtIso: updatedAtIso,
  };

  factory VrGameSaveEntry.fromJson(Map<String, Object?> json) {
    final rawGameId = json[VrGamesConstants.keyGameId];
    if (rawGameId is! String) {
      throw const FormatException('Save entry requires a string gameId.');
    }
    final rawSlot = json.containsKey(VrGamesConstants.keySlotIndex)
        ? json[VrGamesConstants.keySlotIndex]
        : VrGamesConstants.defaultSaveSlotIndex;
    if (rawSlot is! int) {
      throw const FormatException('Save entry slotIndex must be an integer.');
    }
    final rawHighScore = json.containsKey(VrGamesConstants.keyHighScore)
        ? json[VrGamesConstants.keyHighScore]
        : 0;
    if (rawHighScore is! int) {
      throw const FormatException('Save entry highScore must be an integer.');
    }
    final rawState = json.containsKey(VrGamesConstants.keyStateBytesBase64)
        ? json[VrGamesConstants.keyStateBytesBase64]
        : '';
    if (rawState is! String) {
      throw const FormatException(
        'Save entry stateBytesBase64 must be a base64 string.',
      );
    }
    final maxBase64Chars =
        ((VrGamesConstants.maxSaveStateBytes + 2) ~/ 3) * 4 + 16;
    if (rawState.length > maxBase64Chars) {
      throw const FormatException(
        'Save entry stateBytesBase64 exceeds maximum byte budget.',
      );
    }
    final decodedBytes = rawState.isEmpty
        ? Uint8List(0)
        : base64Decode(rawState);
    if (decodedBytes.length > VrGamesConstants.maxSaveStateBytes) {
      throw const FormatException(
        'Save entry decoded stateBytes exceeds maximum byte budget.',
      );
    }
    final rawUpdatedAt = json.containsKey(VrGamesConstants.keyUpdatedAtIso)
        ? json[VrGamesConstants.keyUpdatedAtIso]
        : VrGamesConstants.defaultEpochIso;
    if (rawUpdatedAt is! String) {
      throw const FormatException('Save entry updatedAtIso must be a string.');
    }

    final entry = VrGameSaveEntry(
      gameId: rawGameId,
      slotIndex: rawSlot,
      highScore: rawHighScore,
      stateBytes: decodedBytes,
      updatedAtIso: rawUpdatedAt,
    );
    if (!entry.isValid) {
      throw const FormatException('Save entry failed bounds validation.');
    }
    return entry;
  }
}
