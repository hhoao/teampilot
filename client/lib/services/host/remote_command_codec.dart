import 'dart:convert';

import '../cli/flashskyai/remote_flashskyai_command_builder.dart';

/// Structured description of a command to run on a remote target.
///
/// [argv] is the executable followed by its arguments — never re-interpreted
/// by a shell on the embedded path. [cwd] and [env] are optional; empty or
/// null values are omitted from the encoded command.
class RemoteCommandSpec {
  const RemoteCommandSpec({required this.argv, this.cwd, this.env});

  /// The executable followed by its arguments. Must not be empty.
  final List<String> argv;

  /// Working directory for the process, or `null` for the target default.
  final String? cwd;

  /// Environment variables for the process, or `null`/empty for none.
  final Map<String, String>? env;
}

/// Encodes [RemoteCommandSpec]s for both remote target kinds.
///
/// Legacy SSH targets get a POSIX shell string (byte-for-byte what
/// [RemoteFlashskyaiCommandBuilder] has always produced); embedded targets
/// ([SshProfile.embeddedTarget]) get the `tp1:` structured-exec payload the
/// embedded server speaks. The embedded branch must stay free of any shell
/// quoting — structured exec has no shell, so there is nothing to inject.
class RemoteCommandCodec {
  const RemoteCommandCodec();

  /// The prefix every embedded structured-exec command starts with — the
  /// same grammar as `tp_sshd`'s `TpExecCodec` (kept in sync by tests, not
  /// by an import: the host layer does not depend on `tp_sshd`).
  static const _embeddedPrefix = 'tp1:';

  /// Legacy target: POSIX shell string, byte-for-byte what
  /// [RemoteFlashskyaiCommandBuilder.buildCommand] produces today.
  String encodeLegacy(RemoteCommandSpec spec, {bool useLoginShell = false}) {
    return const RemoteFlashskyaiCommandBuilder().buildCommand(
      remoteExecutablePath: spec.argv.first,
      arguments: spec.argv.skip(1).toList(),
      workingDirectory: spec.cwd,
      environment: spec.env,
      useLoginShell: useLoginShell,
    );
  }

  /// Embedded target: `tp1:{...}` payload for the structured exec path.
  /// `cwd` and `env` are omitted when null/empty, matching the server-side
  /// encoder's field-omission rules exactly.
  String encodeEmbedded(RemoteCommandSpec spec) {
    return '$_embeddedPrefix${jsonEncode({'argv': spec.argv, if (spec.cwd != null) 'cwd': spec.cwd, if (spec.env != null && spec.env!.isNotEmpty) 'env': spec.env})}';
  }
}
