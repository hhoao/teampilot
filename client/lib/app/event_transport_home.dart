import '../models/ssh_profile.dart';
import '../services/app/connection_mode_service.dart';
import '../services/event/event_transport_controller.dart';
import '../services/ssh/event_transport_ssh_channel.dart';
import '../services/ssh/ssh_client_factory.dart';
import '../services/storage/home_storage.dart';
import '../utils/logging/logger.dart';

/// Selects Server / Client / none from the current home and applies it.
///
/// Failures are logged; they never throw to the UI.
Future<void> applyEventTransportForHome({
  required EventTransportController controller,
  required ConnectionModeService connectionMode,
  required HomeStorage homeStorage,
  required SshClientFactory sshClientFactory,
  required SshProfile? Function() homeProfile,
  bool restart = false,
}) async {
  try {
    if (restart) {
      await controller.apply(EventTransportRole.none);
    }
    if (connectionMode.isLocalMode) {
      await controller.apply(EventTransportRole.server);
    } else if (connectionMode.isSshMode) {
      await controller.apply(
        EventTransportRole.client,
        open: () => openSshEventTransportChannel(
          homeStorage: homeStorage,
          sshClientFactory: sshClientFactory,
          homeProfile: homeProfile,
        ),
      );
    } else {
      await controller.apply(EventTransportRole.none);
    }
  } on Object catch (error, stackTrace) {
    appLogger.w(
      '[event-transport] apply failed',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
