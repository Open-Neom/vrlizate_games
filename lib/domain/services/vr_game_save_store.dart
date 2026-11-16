import 'dart:convert';

import '../../utils/constants/vr_games_constants.dart';
import '../models/vr_game_save_entry.dart';

/// In-memory and JSON-serializable store for `.vrlz` game high scores and save states.
///
/// Restoration via [restoreFromJson] and [restoreFromJsonString] is strictly
/// transactional: all entries and bounds are validated in a staging map before
/// replacing any previously stored save data.
class VrGameSaveStore {
  final Map<String, Map<int, VrGameSaveEntry>> _byGameAndSlot =
      <String, Map<int, VrGameSaveEntry>>{};

  /// Total number of saved slots across all games.
  int get entryCount =>
      _byGameAndSlot.values.fold<int>(0, (sum, slots) => sum + slots.length);

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
    if (!slots.containsKey(entry.slotIndex) &&
        entryCount >= VrGamesConstants.maxRestoredSaveEntries) {
      throw StateError('Maximum number of saved game entries reached.');
    }
    final existing = slots[entry.slotIndex];
    final bestScore = existing != null && existing.highScore > entry.highScore
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
    final nextScore = existing != null && existing.highScore > score
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
    return updated.copyWith();
  }

  /// Retrieves a detached copy of the save entry for [gameId] and [slotIndex],
  /// or `null` if absent.
  VrGameSaveEntry? loadEntry(
    String gameId, {
    int slotIndex = VrGamesConstants.defaultSaveSlotIndex,
  }) => _byGameAndSlot[gameId]?[slotIndex]?.copyWith();

  /// Returns all save entries for [gameId] ordered by `slotIndex`.
  List<VrGameSaveEntry> entriesForGame(String gameId) {
    final slots = _byGameAndSlot[gameId];
    if (slots == null || slots.isEmpty) {
      return const <VrGameSaveEntry>[];
    }
    final sortedKeys = slots.keys.toList()..sort();
    return List<VrGameSaveEntry>.unmodifiable(
      sortedKeys.map((slot) => slots[slot]!.copyWith()),
    );
  }

  /// Returns the highest score across all save slots for [gameId].
  int highScoreFor(String gameId) {
    final slots = _byGameAndSlot[gameId];
    if (slots == null || slots.isEmpty) {
      return 0;
    }
    var best = 0;
    for (final entry in slots.values) {
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
      final slots = _byGameAndSlot[gameId]!;
      final sortedSlots = slots.keys.toList()..sort();
      for (final slot in sortedSlots) {
        allEntries.add(slots[slot]!.toJson());
      }
    }
    return <String, Object?>{VrGamesConstants.keyEntries: allEntries};
  }

  /// Serializes all save entries to a JSON string.
  String toJsonString() => jsonEncode(toJson());

  /// Atomically restores save entries from a decoded JSON map.
  ///
  /// Supports unversioned legacy maps (`{"entries": [...]}`) and explicit
  /// `schemaVersion: 1`. Throws [FormatException] without modifying existing
  /// saves if the root structure, schema version, entry count, base64 payload,
  /// or any entry field is invalid.
  void restoreFromJson(Map<String, Object?> json) {
    for (final key in json.keys) {
      if (key != VrGamesConstants.keyEntries &&
          key != VrGamesConstants.keySchemaVersion) {
        throw FormatException('Unknown save store field: $key');
      }
    }
    if (json.containsKey(VrGamesConstants.keySchemaVersion)) {
      final version = json[VrGamesConstants.keySchemaVersion];
      if (version is! int || version != VrGamesConstants.saveSchemaVersion) {
        throw FormatException('Unsupported save schemaVersion: $version');
      }
    }
    final rawList = json[VrGamesConstants.keyEntries];
    if (rawList is! List) {
      throw const FormatException(
        'Save payload must contain an entries array.',
      );
    }
    if (rawList.length > VrGamesConstants.maxRestoredSaveEntries) {
      throw const FormatException(
        'Save payload exceeds maximum allowed entry count.',
      );
    }

    final staged = VrGameSaveStore();
    for (final item in rawList) {
      if (item is Map<String, Object?>) {
        staged.saveEntry(VrGameSaveEntry.fromJson(item));
      } else if (item is Map) {
        final typed = <String, Object?>{};
        for (final entry in item.entries) {
          if (entry.key is! String) {
            throw const FormatException('Save entry keys must be strings.');
          }
          typed[entry.key as String] = entry.value;
        }
        staged.saveEntry(VrGameSaveEntry.fromJson(typed));
      } else {
        throw const FormatException('Each save entry must be a JSON object.');
      }
    }

    _byGameAndSlot
      ..clear()
      ..addAll(staged._byGameAndSlot);
  }

  /// Atomically restores save entries from a serialized JSON string.
  ///
  /// Interrupted/truncated JSON or non-object roots throw [FormatException]
  /// while leaving previously stored saves intact.
  void restoreFromJsonString(String jsonStr) {
    if (jsonStr.length > VrGamesConstants.maxSavePayloadJsonChars) {
      throw const FormatException(
        'Serialized save payload exceeds maximum allowed size.',
      );
    }
    final decoded = jsonDecode(jsonStr);
    if (decoded is Map<String, Object?>) {
      restoreFromJson(decoded);
      return;
    }
    if (decoded is Map) {
      final typed = <String, Object?>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String) {
          throw const FormatException('Save root keys must be strings.');
        }
        typed[entry.key as String] = entry.value;
      }
      restoreFromJson(typed);
      return;
    }
    throw const FormatException('Save payload root must be a JSON object.');
  }
}
