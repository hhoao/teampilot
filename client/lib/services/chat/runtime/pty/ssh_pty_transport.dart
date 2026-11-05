import 'dart:typed_data';

import '../../../ssh/ssh_member_session.dart';
import '../../../ssh/worker/ssh_worker_member_session.dart';
import '../../../terminal/terminal_transport.dart';

/// [TerminalTransport] over a UI-safe proxy for a worker-owned SSH PTY.
class SshPtyTransport implements TerminalTransport {
  SshPtyTransport({required this.channel});

  final SshWorkerPtyChannel channel;

  @override
  Stream<Uint8List> get output => channel.output;

  @override
  Future<int> get done => channel.done;

  @override
  int? get pid => null;

  @override
  void write(Uint8List data) => channel.write(data);

  @override
  void resize(int rows, int columns) => channel.resize(rows, columns);

  @override
  void close() => channel.close();

  /// Starts a remote PTY. [command] `null` opens a bare `shell` request.
  static Future<SshPtyTransport> start({
    required SshMemberSession memberSession,
    String? command,
    int columns = 80,
    int rows = 24,
    Map<String, String>? environment,
  }) async {
    final channel = await memberSession.openPty(
      command: command,
      columns: columns,
      rows: rows,
      environment: environment,
    );
    return SshPtyTransport(channel: channel);
  }
}
