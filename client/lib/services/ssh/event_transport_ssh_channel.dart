import 'dart:convert';

import '../../models/ssh_profile.dart';
import '../../utils/logging/logger.dart';
import '../event/event_transport_client.dart';
import '../storage/home_storage.dart';
import 'ssh_client_factory.dart';

/// Adapts the SSH layer's app-owned forward into the event byte-stream seam.
///
/// Lives next to the SSH layer so `services/event/` never imports dartssh2.
final class SshForwardEventTransportChannel
    implements EventTransportByteChannel {
  SshForwardEventTransportChannel(this._channel);

  final SshForwardByteChannel _channel;

  @override
  Stream<List<int>> get incoming => _channel.incoming;

  @override
  void add(List<int> data) => _channel.add(data);

  @override
  Future<void> close() => _channel.close();
}

/// Reads `<teampilotRoot>/event-transport.json` then `forwardLocal`.
///
/// Missing advertisement or a failed forward throws — [EventTransportClient]
/// backoff retries `open`. Callers must not surface this to the UI.
Future<EventTransportByteChannel> openSshEventTransportChannel({
  required HomeStorage homeStorage,
  required SshClientFactory sshClientFactory,
  required SshProfile? Function() homeProfile,
}) async {
  final path = homeStorage.paths.eventTransportJson;
  final raw = await homeStorage.fs.readString(path);
  if (raw == null || raw.trim().isEmpty) {
    throw StateError('event-transport advertisement missing');
  }
  final Object decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException catch (error, stackTrace) {
    appLogger.w(
      '[event-transport] advertisement is not JSON',
      error: error,
      stackTrace: stackTrace,
    );
    throw StateError('event-transport advertisement is not JSON');
  }
  if (decoded is! Map) {
    throw StateError('event-transport advertisement is not an object');
  }
  final portRaw = decoded['port'];
  final port = portRaw is int ? portRaw : int.tryParse('$portRaw');
  if (port == null || port <= 0) {
    throw StateError('event-transport advertisement missing port');
  }
  final profile = homeProfile();
  if (profile == null) {
    throw StateError('event-transport ssh home profile missing');
  }
  final forward = await sshClientFactory.openForwardChannel(
    profile,
    '127.0.0.1',
    port,
  );
  return SshForwardEventTransportChannel(forward);
}
