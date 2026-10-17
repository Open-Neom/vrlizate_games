import '../constants/vr_games_constants.dart';

/// Physical form-factor styles for 3D arcade cabinets inside VRlizate rooms.
enum VrArcadeCabinetStyle {
  classicUpright,
  neonCyber,
  tabletopMini,
  wallMounted;

  /// Stable identifier for serialization and configuration.
  String get id => switch (this) {
    VrArcadeCabinetStyle.classicUpright =>
      VrGamesConstants.styleClassicUprightId,
    VrArcadeCabinetStyle.neonCyber => VrGamesConstants.styleNeonCyberId,
    VrArcadeCabinetStyle.tabletopMini => VrGamesConstants.styleTabletopMiniId,
    VrArcadeCabinetStyle.wallMounted => VrGamesConstants.styleWallMountedId,
  };

  /// Resolves a [VrArcadeCabinetStyle] from [id], defaulting to [classicUpright].
  static VrArcadeCabinetStyle fromId(String id) {
    for (final style in VrArcadeCabinetStyle.values) {
      if (style.id == id || style.name == id) {
        return style;
      }
    }
    return VrArcadeCabinetStyle.classicUpright;
  }
}
