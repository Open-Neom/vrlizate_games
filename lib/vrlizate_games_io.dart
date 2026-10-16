/// Native directory and multi-source `.vrlz` game discovery for VRlizate hosts.
library;

export 'package:vrlizate_apps/vrlizate_apps_io.dart'
    show
        VrlzDirectoryEntry,
        VrlzDirectoryIssue,
        VrlzDirectorySnapshot,
        VrlzDirectoryStore,
        VrlzDiscoveryException,
        VrlzDiscoveryIssueKind,
        VrlzDiscoveryLimits,
        VrlzPackageMetadata;

export 'src/vrlz_game_directory_loader.dart';
