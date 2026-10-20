/// Supported game runtime profiles inside a `.vrlz` game build.
enum VrlzGameKind {
  /// 8-bit NES / Famicom cartridge (`vrlizate.nes.v1`, `game.nes`).
  nes,

  /// Stereoscopic 2.5D tile-based platformer or arcade blaster (`vrlizate.retro2d.v1`, `level.json`).
  retro2d,

  /// Independently compiled browser game, loaded through a verified file index.
  webgame,
}
