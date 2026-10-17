import 'dart:convert';

import '../../utils/constants/vr_games_constants.dart';
import '../models/vr_game_save_entry.dart';

/// In-memory and JSON-serializable store for `.vrlz` game high scores and save states.
class VrGameSaveStore {
  final Map<String, Map<int, VrGameSaveEntry>> _byGameAndSlot =
      <String, Map<int, VrGameSaveEntry>>{};

  /// Saves [entry] into its `(gameId, slotIndex)` slot, preserving the maximum
  /// high score recorded for that slot unless overridden.
  void saveEntry(VrGameSaveEntry entry) {
    if (!entry.isValid) {
      throw ArgumentError.value(entry, 'entry', 'Invalid VrGameSaveEntry');
    }
    final slots = _byGameAndSlot.putIfAbsent(
      entry.gameId,
      () => <int, VrGameSaveEntry>{},
    );
    final existing = slots[entry.slotIndex];
    final bestScore =
        existing != null && existing.highScore > entry.highScore
        ? existing.highScore
        : entry.highScore;
    slots[entry.slotIndex] = entry.copyWith(highScore: bestScore);
  }

  /// Updates the high score for [gameId] on [slotIndex] if [score] exceeds
  /// the existing record.
  VrGameSaveEntry recordHighScore(
    String gameId,
    int score, {
    int slotIndex = VrGamesConstants.defaultSaveSlotIndex,
    String updatedAtIso = VrGamesConstants.defaultEpochIso,
  }) {
    final existing = loadEntry(gameId, slotIndex: slotIndex);
    final nextScore =
        existing != null && existing.highScore > score
        ? existing.highScore
        : score;
    final updated = VrGameSaveEntry(
      gameId: gameId,
      slotIndex: slotIndex,
      highScore: nextScore,
      stateBytes: existing?.stateBytes,
      updatedAtIso: updatedAtIso,
    );
    saveEntry(updated);
    return updated;
  }

  /// Retrieves a save entry for [gameId] and [slotIndex], or `null` if absent.
  VrGameSaveEntry? loadEntry(
    String gameId, {
    int slotIndex = VrGamesConstants.defaultSaveSlotIndex,
  }) => _byGameAndSlot[gameId]?[slotIndex];

  /// Returns all save entries for [gameId] ordered by `slotIndex`.
  List<VrGameSaveEntry> entriesForGame(String gameId) {
    final slots = _byGameAndSlot[gameId];
    if (slots == null || slots.isEmpty) {
      return const <VrGameSaveEntry>[];
    }
    final sortedKeys = slots.keys.toList()..sort();
    return List<VrGameSaveEntry>.unmodifiable(
      sortedKeys.map((slot) => slots[slot]!),
    );
  }

  /// Returns the highest score across all save slots for [gameId].
  int highScoreFor(String gameId) {
    var best = 0;
    for (final entry in entriesForGame(gameId)) {
      if (entry.highScore > best) {
        best = entry.highScore;
      }
    }
    return best;
  }

  /// Deletes all save slots for [gameId].
  bool deleteGameSaves(String gameId) => _byGameAndSlot.remove(gameId) != null;

  /// Clears all entries in the store.
  void clear() => _byGameAndSlot.clear();

  /// Serializes all save entries to a JSON map.
  Map<String, Object?> toJson() {
    final allEntries = <Map<String, Object?>>[];
    final gameIds = _byGameAndSlot.keys.toList()..sort();
    for (final gameId in gameIds) {
      for (final entry in entriesForGame(gameId)) {
        allEntries.add(entry.toJson());
      }
    }
    return <String, Object?>{VrGamesConstants.keyEntries: allEntries};
  }

  /// Serializes all save entries to a JSON string.
  String toJsonString() => jsonEncode(toJson());

  /// Restores save entries from a decoded JSON map.
  void restoreFromJson(Map<String, Object?> json) {
    _byGameAndSlot.clear();
    final rawList = json[VrGamesConstants.keyEntries];
    if (rawList is! List) {
      return;
    }
    for (final item in rawList) {
      if (item is Map<String, Object?>) {
        final entry = VrGameSaveEntry.fromJson(item);
        if (entry.isValid) {
          saveEntry(entry);
        }
      } else if (item is Map) {
        final entry = VrGameSaveEntry.fromJson(Map<String, Object?>.from(item));
        if (entry.isValid) {
          saveEntry(entry);
        }
      }
    }
  }

  /// Restores save entries from a serialized JSON string.
  void restoreFromJsonString(String jsonStr) {
    final decoded = jsonDecode(jsonStr);
    if (decoded is Map<String, Object?>) {
      restoreFromJson(decoded);
    } else if (decoded is Map) {
      restoreFromJson(Map<String, Object?>.from(decoded));
    }
  }
}
