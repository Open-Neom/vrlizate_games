/// Native WebView runtime for integrity-checked, independently compiled games.
/// Import separately: basic cartridge authoring does not import WebView or IO.
library;

export 'src/web/vr_web_game_controller.dart';
export 'src/web/vr_web_game_origin_store.dart';
export 'src/web/vr_web_game_server.dart';

export 'src/web/vr_https_domain_web_stage.dart';
export 'src/web/vr_lan_stereo_web_stage.dart';
export 'src/web/vr_web_game_capabilities.dart';
export 'src/web/vr_web_game_document_policy.dart';
