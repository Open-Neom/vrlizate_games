import '../../utils/constants/vr_games_constants.dart';
import '../../utils/enums/vr_arcade_cabinet_style.dart';

/// Specification for a 3D arcade cabinet hosting a `.vrlz` game inside a VR room.
class VrArcadeCabinetSpec {
  const VrArcadeCabinetSpec({
    required this.gameId,
    this.style = VrArcadeCabinetStyle.classicUpright,
    this.widthMeters = VrGamesConstants.defaultCabinetWidthMeters,
    this.heightMeters = VrGamesConstants.defaultCabinetHeightMeters,
    this.depthMeters = VrGamesConstants.defaultCabinetDepthMeters,
    this.screenTiltDegrees = VrGamesConstants.defaultScreenTiltDegrees,
    this.primaryMarqueeArgb = VrGamesConstants.defaultPrimaryMarqueeArgb,
    this.accentMarqueeArgb = VrGamesConstants.defaultAccentMarqueeArgb,
  });

  final String gameId;
  final VrArcadeCabinetStyle style;
  final double widthMeters;
  final double heightMeters;
  final double depthMeters;
  final double screenTiltDegrees;
  final int primaryMarqueeArgb;
  final int accentMarqueeArgb;

  /// Whether cabinet dimensions, screen tilt angle, and gameId are within valid bounds.
  bool get isValid =>
      gameId.trim().isNotEmpty &&
      widthMeters >= VrGamesConstants.minCabinetDimensionMeters &&
      widthMeters <= VrGamesConstants.maxCabinetDimensionMeters &&
      heightMeters >= VrGamesConstants.minCabinetDimensionMeters &&
      heightMeters <= VrGamesConstants.maxCabinetDimensionMeters &&
      depthMeters >= VrGamesConstants.minCabinetDimensionMeters &&
      depthMeters <= VrGamesConstants.maxCabinetDimensionMeters &&
      screenTiltDegrees >= VrGamesConstants.minScreenTiltDegrees &&
      screenTiltDegrees <= VrGamesConstants.maxScreenTiltDegrees;

  VrArcadeCabinetSpec copyWith({
    String? gameId,
    VrArcadeCabinetStyle? style,
    double? widthMeters,
    double? heightMeters,
    double? depthMeters,
    double? screenTiltDegrees,
    int? primaryMarqueeArgb,
    int? accentMarqueeArgb,
  }) {
    return VrArcadeCabinetSpec(
      gameId: gameId ?? this.gameId,
      style: style ?? this.style,
      widthMeters: widthMeters ?? this.widthMeters,
      heightMeters: heightMeters ?? this.heightMeters,
      depthMeters: depthMeters ?? this.depthMeters,
      screenTiltDegrees: screenTiltDegrees ?? this.screenTiltDegrees,
      primaryMarqueeArgb: primaryMarqueeArgb ?? this.primaryMarqueeArgb,
      accentMarqueeArgb: accentMarqueeArgb ?? this.accentMarqueeArgb,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    VrGamesConstants.keyGameId: gameId,
    VrGamesConstants.keyStyle: style.id,
    VrGamesConstants.keyWidthMeters: widthMeters,
    VrGamesConstants.keyHeightMeters: heightMeters,
    VrGamesConstants.keyDepthMeters: depthMeters,
    VrGamesConstants.keyScreenTiltDegrees: screenTiltDegrees,
    VrGamesConstants.keyPrimaryMarqueeArgb: primaryMarqueeArgb,
    VrGamesConstants.keyAccentMarqueeArgb: accentMarqueeArgb,
  };

  factory VrArcadeCabinetSpec.fromJson(Map<String, Object?> json) {
    final widthRaw = json[VrGamesConstants.keyWidthMeters];
    final heightRaw = json[VrGamesConstants.keyHeightMeters];
    final depthRaw = json[VrGamesConstants.keyDepthMeters];
    final tiltRaw = json[VrGamesConstants.keyScreenTiltDegrees];
    final primaryRaw = json[VrGamesConstants.keyPrimaryMarqueeArgb];
    final accentRaw = json[VrGamesConstants.keyAccentMarqueeArgb];
    return VrArcadeCabinetSpec(
      gameId: (json[VrGamesConstants.keyGameId] as String?) ?? '',
      style: VrArcadeCabinetStyle.fromId(
        (json[VrGamesConstants.keyStyle] as String?) ?? '',
      ),
      widthMeters: widthRaw is num
          ? widthRaw.toDouble()
          : VrGamesConstants.defaultCabinetWidthMeters,
      heightMeters: heightRaw is num
          ? heightRaw.toDouble()
          : VrGamesConstants.defaultCabinetHeightMeters,
      depthMeters: depthRaw is num
          ? depthRaw.toDouble()
          : VrGamesConstants.defaultCabinetDepthMeters,
      screenTiltDegrees: tiltRaw is num
          ? tiltRaw.toDouble()
          : VrGamesConstants.defaultScreenTiltDegrees,
      primaryMarqueeArgb: primaryRaw is int
          ? primaryRaw
          : VrGamesConstants.defaultPrimaryMarqueeArgb,
      accentMarqueeArgb: accentRaw is int
          ? accentRaw
          : VrGamesConstants.defaultAccentMarqueeArgb,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VrArcadeCabinetSpec &&
          gameId == other.gameId &&
          style == other.style &&
          widthMeters == other.widthMeters &&
          heightMeters == other.heightMeters &&
          depthMeters == other.depthMeters &&
          screenTiltDegrees == other.screenTiltDegrees &&
          primaryMarqueeArgb == other.primaryMarqueeArgb &&
          accentMarqueeArgb == other.accentMarqueeArgb;

  @override
  int get hashCode => Object.hash(
    gameId,
    style,
    widthMeters,
    heightMeters,
    depthMeters,
    screenTiltDegrees,
    primaryMarqueeArgb,
    accentMarqueeArgb,
  );
}
