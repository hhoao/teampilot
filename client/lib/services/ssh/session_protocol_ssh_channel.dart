import 'dart:convert';

import '../../models/ssh_profile.dart';
import '../../utils/logging/logger.dart';
import '../session_protocol/session_channel.dart';
import '../storage/home_storage.dart';
import 'ssh_client_factory.dart';

/// Adapts the SSH layer's forward channel to the session byte seam.
final class SshForwardSessionProtocolChannel implements SessionByteChannel {
  SshForwardSessionProtocolChannel(this._channel);

  final SshForwardByteChannel _channel;

  @override
  Stream<List<int>> get incoming => _channel.incoming;

  @override
  void add(List<int> data) => _channel.add(data);

  @override
  Future<void> close() => _channel.close();
}

/// Reads `<teampilotRoot>/session-protocol.json` then forwards to the
/// desktop's loopback port. Missing advertisement / failed forward throws so
/// the client backoff can retry.
Future<SessionByteChannel> openSshSessionProtocolChannel({
  required HomeStorage homeStorage,
  required SshClientFactory sshClientFactory,
  required SshProfile? Function() homeProfile,
}) async {
  final path = homeStorage.paths.sessionProtocolJson;
  final raw = await homeStorage.fs.readString(path);
  if (raw == null || raw.trim().isEmpty) {
    appLogger.w(
      '[session-protocol] advertisement missing path=$path '
      'homeRoot=${homeStorage.appDataRoot}',
    );
    throw StateError(
      'session-protocol advertisement missing: $path '
      '(homeRoot=${homeStorage.appDataRoot})',
    );
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException catch (error, stackTrace) {
    appLogger.w(
      '[session-protocol] advertisement is not JSON',
      error: error,
      stackTrace: stackTrace,
    );
    throw StateError('session-protocol advertisement is not JSON');
  }
  if (decoded is! Map) {
    throw StateError('session-protocol advertisement is not an object');
  }
  final portRaw = decoded['port'];
  final port = portRaw is int ? portRaw : int.tryParse('$portRaw');
  if (port == null || port <= 0) {
    throw StateError('session-protocol advertisement missing port');
  }
  final profile = homeProfile();
  if (profile == null) {
    throw StateError('session-protocol ssh home profile missing');
  }
  final forward = await sshClientFactory.openForwardChannel(
    profile,
    '127.0.0.1',
    port,
  );
  return SshForwardSessionProtocolChannel(forward);
}
