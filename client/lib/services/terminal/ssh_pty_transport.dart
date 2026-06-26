import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../ssh/ssh_member_session.dart';
import 'terminal_transport.dart';

class SshPtyTransport implements TerminalTransport {
  SshPtyTransport({required this.session});

  final SSHSession session;
  Stream<Uint8List>? _output;

  @override
  Stream<Uint8List> get output => _output ??= _mergeOutputStreams();

  @override
  Future<int> get done => session.done.then((_) => session.exitCode ?? 0);

  @override
  void write(Uint8List data) {
    session.write(data);
  }

  @override
  void resize(int rows, int columns) {
    session.resizeTerminal(columns, rows);
  }

  @override
  void close() {
    session.close();
  }

  Stream<Uint8List> _mergeOutputStreams() {
    late StreamSubscription<Uint8List> stdoutSub;
    late StreamSubscription<Uint8List> stderrSub;
    var closed = 0;
    final controller = StreamController<Uint8List>();

    void markClosed() {
      closed += 1;
      if (closed == 2 && !controller.isClosed) {
        controller.close();
      }
    }

    controller.onListen = () {
      stdoutSub = session.stdout.listen(
        controller.add,
        onError: controller.addError,
        onDone: markClosed,
      );
      stderrSub = session.stderr.listen(
        controller.add,
        onError: controller.addError,
        onDone: markClosed,
      );
    };
    controller.onCancel = () async {
      await stdoutSub.cancel();
      await stderrSub.cancel();
    };

    return controller.stream;
  }

  static Future<SshPtyTransport> start({
    required SshMemberSession memberSession,
    required String command,
    int columns = 80,
    int rows = 24,
    Map<String, String>? environment,
  }) async {
    final session = await memberSession.openPty(
      command: command,
      columns: columns,
      rows: rows,
      environment: environment,
    );
    return SshPtyTransport(session: session);
  }

  static String buildSessionCommand(
    String command, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    final parts = <String>[];
    if (environment != null && environment.isNotEmpty) {
      for (final entry in environment.entries) {
        parts.add('export ${entry.key}=${_shellQuote(entry.value)}');
      }
    }
    if (workingDirectory != null && workingDirectory.isNotEmpty) {
      parts.add('cd ${_shellQuote(workingDirectory)}');
    }
    parts.add(command);
    return parts.join(' && ');
  }

  static String _shellQuote(String arg) {
    if (arg.isEmpty) return "''";
    if (!arg.contains("'")) return "'$arg'";
    return "'${arg.replaceAll("'", "'\"'\"'")}'";
  }
}
