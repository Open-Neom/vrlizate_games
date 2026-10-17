/// Constants for `vrlizate_games` packages, arcade cabinets, save store,
/// and the 3-to-5 second center/home button hold-to-exit policy.
abstract final class VrGamesConstants {
  static const int defaultHttpTimeoutSeconds = 30;
  static const String defaultAssetPrefix = 'assets/vrlz/';
  static const String assetUriPrefix = 'asset:///';
  static const String vrlzExtension = '.vrlz';
  static const String nesExtension = '.nes';
  static const String defaultCartridgeFileName = 'cartridge.nes';
  static const String deduplicationSeparator = ':';
  static const String pathSeparator = '/';

  static const int inesMinHeaderBytes = 16;
  static const int inesMagicByte0 = 0x4E;
  static const int inesMagicByte1 = 0x45;
  static const int inesMagicByte2 = 0x53;
  static const int inesMagicByte3 = 0x1A;

  static const String keyName = 'name';
  static const String keyTheme = 'theme';
  static const String keyMode = 'mode';
  static const String keyRows = 'rows';

  static const String keyGameId = 'gameId';
  static const String keyStyle = 'style';
  static const String keyWidthMeters = 'widthMeters';
  static const String keyHeightMeters = 'heightMeters';
  static const String keyDepthMeters = 'depthMeters';
  static const String keyScreenTiltDegrees = 'screenTiltDegrees';
  static const String keyPrimaryMarqueeArgb = 'primaryMarqueeArgb';
  static const String keyAccentMarqueeArgb = 'accentMarqueeArgb';

  static const String keySlotIndex = 'slotIndex';
  static const String keyHighScore = 'highScore';
  static const String keyStateBytesBase64 = 'stateBytesBase64';
  static const String keyUpdatedAtIso = 'updatedAtIso';
  static const String keyEntries = 'entries';

  static const String styleClassicUprightId = 'classic_upright';
  static const String styleNeonCyberId = 'neon_cyber';
  static const String styleTabletopMiniId = 'tabletop_mini';
  static const String styleWallMountedId = 'wall_mounted';

  static const double defaultCabinetWidthMeters = 0.72;
  static const double defaultCabinetHeightMeters = 1.78;
  static const double defaultCabinetDepthMeters = 0.80;
  static const double minCabinetDimensionMeters = 0.20;
  static const double maxCabinetDimensionMeters = 3.50;
  static const double defaultScreenTiltDegrees = 18.0;
  static const double minScreenTiltDegrees = 0.0;
  static const double maxScreenTiltDegrees = 60.0;
  static const int defaultPrimaryMarqueeArgb = 0xFF00E5FF;
  static const int defaultAccentMarqueeArgb = 0xFFFF2E93;

  static const int defaultSaveSlotIndex = 0;
  static const int maxSaveSlotsPerGame = 8;
  static const String defaultEpochIso = '1970-01-01T00:00:00.000Z';

  static const int minHoldDurationMs = 3000;
  static const int maxHoldDurationMs = 5000;
  static const int defaultHoldDurationMs = 3500;
  static const double defaultAlertThresholdProgress = 0.25;
  static const double minProgress = 0.0;
  static const double maxProgress = 1.0;

  static const List<String> defaultBundledGameAssets = <String>[
    'assets/vrlz/nova_the_squirrel.vrlz',
    'assets/vrlz/thwaite_missile_defense.vrlz',
    'assets/vrlz/concentration_room.vrlz',
    'assets/vrlz/mega_buster_arena.vrlz',
    'assets/vrlz/open_nes_snake.vrlz',
    'assets/vrlz/darkness_dungeon.vrlz',
    'assets/vrlz/super_dash_run.vrlz',
    'assets/vrlz/celeste_classic_peak.vrlz',
    'assets/vrlz/bonfire_solaria_quest.vrlz',
    'assets/vrlz/pinball_cyber_arena.vrlz',
    'assets/vrlz/sunny_gardens.vrlz',
    'assets/vrlz/neon_bastion.vrlz',
  ];
}
