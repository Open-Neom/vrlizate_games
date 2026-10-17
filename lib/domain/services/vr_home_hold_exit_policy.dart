import '../../utils/constants/vr_games_constants.dart';

/// Tracks holding the center/home button for 3 to 5 seconds to prevent
/// accidental exits during active VR gameplay, exposing [progress] (`0.0..1.0`),
/// [shouldShowAlert], and [shouldTriggerExit].
class VrHomeHoldExitPolicy {
  VrHomeHoldExitPolicy({
    int requiredHoldMs = VrGamesConstants.defaultHoldDurationMs,
    this.alertThresholdProgress = VrGamesConstants.defaultAlertThresholdProgress,
  }) : requiredHoldMs = requiredHoldMs.clamp(
         VrGamesConstants.minHoldDurationMs,
         VrGamesConstants.maxHoldDurationMs,
       ),
       assert(
         alertThresholdProgress >= VrGamesConstants.minProgress &&
             alertThresholdProgress <= VrGamesConstants.maxProgress,
       );

  /// Required continuous hold duration in milliseconds, clamped to `3000..5000` ms.
  final int requiredHoldMs;

  /// Progress threshold (`0.0..1.0`) at which the HUD exit-confirmation alert appears.
  final double alertThresholdProgress;

  bool _isHolding = false;
  int _heldMilliseconds = 0;

  /// Whether the center/home button is currently held down.
  bool get isHolding => _isHolding;

  /// Accumulated hold duration in milliseconds for the current press.
  int get heldMilliseconds => _heldMilliseconds;

  /// Normalized hold progress in `0.0..1.0`.
  double get progress =>
      (_heldMilliseconds / requiredHoldMs).clamp(
        VrGamesConstants.minProgress,
        VrGamesConstants.maxProgress,
      );

  /// Whether the on-screen hold-to-exit alert indicator should be displayed.
  bool get shouldShowAlert =>
      _isHolding && progress >= alertThresholdProgress && !shouldTriggerExit;

  /// Whether the button has been held continuously long enough (`3..5` s) to exit.
  bool get shouldTriggerExit =>
      _isHolding && _heldMilliseconds >= requiredHoldMs;

  /// Begins tracking a center/home button press.
  void onButtonDown() {
    if (!_isHolding) {
      _isHolding = true;
      _heldMilliseconds = 0;
    }
  }

  /// Releases the center/home button and clears accumulated hold progress.
  void onButtonUp() {
    reset();
  }

  /// Advances the hold timer by [deltaMs] milliseconds while the button is held.
  void advanceMs(int deltaMs) {
    if (!_isHolding || deltaMs <= 0) {
      return;
    }
    _heldMilliseconds = (_heldMilliseconds + deltaMs).clamp(
      0,
      requiredHoldMs,
    );
  }

  /// Advances the hold timer by [delta].
  void update(Duration delta) => advanceMs(delta.inMilliseconds);

  /// Resets the policy to its idle state.
  void reset() {
    _isHolding = false;
    _heldMilliseconds = 0;
  }
}
