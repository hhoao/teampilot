import '../models/ssh_profile.dart';
import '../services/app/connection_mode_service.dart';
import '../services/session_sync/session_protocol_controller.dart';
import '../services/ssh/session_protocol_ssh_channel.dart';
import '../services/ssh/ssh_client_factory.dart';
import '../services/storage/home_storage.dart';
import '../utils/logging/logger.dart';

/// Selects Server / Client / none from the current home and applies it.
Future<void> applySessionProtocolForHome({
  required SessionProtocolController controller,
  required ConnectionModeService connectionMode,
  required HomeStorage homeStorage,
  required SshClientFactory sshClientFactory,
  required SshProfile? Function() homeProfile,
  bool restart = false,
}) async {
  try {
    if (restart) await controller.applyNone();
    if (connectionMode.isLocalMode) {
      await controller.applyServer(
        SessionProtocolServerConfig(
          fs: homeStorage.fs,
          advertisePath: homeStorage.paths.sessionProtocolJson,
        ),
      );
    } else if (connectionMode.isSshMode) {
      await controller.applyClient(
        homeId: homeStorage.context.target.id,
        open: () => openSshSessionProtocolChannel(
          homeStorage: homeStorage,
          sshClientFactory: sshClientFactory,
          homeProfile: homeProfile,
        ),
      );
    } else {
      await controller.applyNone();
    }
  } on Object catch (error, stackTrace) {
    appLogger.w(
      '[session-protocol] apply failed',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
