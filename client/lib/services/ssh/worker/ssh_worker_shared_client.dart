import 'dart:async';

import 'package:dartssh2/dartssh2.dart';

import '../../../models/ssh_profile.dart';
import 'ssh_worker_protocol.dart';

typedef SshWorkerClientOpener =
    Future<SSHClient> Function({
      required SshProfile profile,
      required SshWorkerDialTarget target,
      required Duration timeout,
    });

/// One authenticated dartssh2 client shared by the storage, member, and
/// forwarding planes of a profile worker generation.
///
/// Sharing keeps one TCP handshake/auth challenge per profile instead of one
/// per terminal, tunnel, and storage plane. Each plane still owns its own
/// channels, SFTP handles, and failure semantics; the transport itself is
/// closed only when the worker shuts down or keepalive reports it dead.
final class SshWorkerSharedClient {
  SshWorkerSharedClient({required this.profileId, required this.openClient});

  final String profileId;
  final SshWorkerClientOpener openClient;

  SSHClient? _client;
  Future<SSHClient>? _opening;
  String? _host;
  int? _port;
  var _closed = false;

  /// Returns the shared authenticated client, opening it once on demand.
  Future<SSHClient> acquire({
    required SshProfile profile,
    required SshWorkerDialTarget target,
    required Duration timeout,
  }) async {
    if (_closed) throw StateError('SSH worker client is closed');
    if (profile.id != profileId) {
      throw StateError('SSH worker client profile mismatch');
    }
    final key = '${target.host}:${target.port}';
    final currentKey = _host == null ? null : '$_host:$_port';
    if (currentKey != null && currentKey != key) {
      throw StateError('SSH worker dial target changed');
    }

    final existing = _client;
    if (existing != null && !existing.isClosed) return existing;

    final opening = _opening;
    if (opening != null) return opening;

    _host = target.host;
    _port = target.port;

    final future = _open(profile, target, timeout);
    _opening = future;
    try {
      return await future;
    } finally {
      if (identical(_opening, future)) _opening = null;
    }
  }

  Future<SSHClient> _open(
    SshProfile profile,
    SshWorkerDialTarget target,
    Duration timeout,
  ) async {
    SSHClient? client;
    try {
      client = await openClient(
        profile: profile,
        target: target,
        timeout: timeout,
      );
      await client.authenticated;
      if (_closed || client.isClosed) {
        await _closeQuietly(client);
        throw StateError('SSH worker client closed during connect');
      }
      _client = client;
      return client;
    } on Object {
      await _closeQuietly(client);
      _host = null;
      _port = null;
      rethrow;
    }
  }

  /// Closes the shared transport. Worker shutdown calls this after every plane
  /// has released its channels.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final opening = _opening;
    if (opening != null) {
      try {
        await opening;
      } on Object {
        // The opening path owns its own cleanup.
      }
    }
    final client = _client;
    _client = null;
    if (client != null) await _closeQuietly(client);
  }

  Future<void> _closeQuietly(SSHClient? client) async {
    if (client == null || client.isClosed) return;
    try {
      await client.close();
    } on Object {
      // Local close can race transport teardown.
    }
  }
}
