import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// A spawned process backing an `exec` channel. Implemented by the app with
/// flutter_pty / `Process.run`; faked in tests.
abstract class SSHServerProcess {
  /// The process's standard output, as raw bytes. Must close when the
  /// process exits, so the channel can drain it before reporting the exit
  /// status.
  Stream<Uint8List> get stdout;

  /// The process's standard error, as raw bytes. Must close when the
  /// process exits, like [stdout].
  Stream<Uint8List> get stderr;

  /// The process's standard input. The channel closes it when the client
  /// sends EOF.
  StreamSink<List<int>> get stdin;

  /// The process's exit code. Completes when the process exits.
  Future<int> get exitCode;

  /// Kills the process. Must be safe to call more than once, after exit,
  /// and from connection teardown — the channel never orphans a process.
  void kill();
}

/// Terminal geometry and environment a client asked for with `pty-req`
/// (RFC 4254 §6.2), stashed until the shell request that consumes it.
class SSHPtyDimensions {
  const SSHPtyDimensions({
    required this.columns,
    required this.rows,
    this.pixelWidth = 0,
    this.pixelHeight = 0,
    this.environment = const {},
  });

  /// Terminal width in character cells.
  final int columns;

  /// Terminal height in character rows.
  final int rows;

  /// Terminal width in pixels, `0` when the client does not know.
  final int pixelWidth;

  /// Terminal height in pixels, `0` when the client does not know.
  final int pixelHeight;

  /// Terminal environment: `TERM` from the `pty-req`, plus any variables
  /// the client passed with `env` requests before the shell. Terminal modes
  /// are not parsed — they stay the client's raw bytes.
  final Map<String, String> environment;
}

/// A pseudo-terminal backing a `shell` channel: a [SSHServerProcess] the
/// client can also resize and signal once it is running. Implemented by the
/// app with flutter_pty; faked in tests.
abstract class SSHServerPty extends SSHServerProcess {
  /// Resizes the terminal to [columns] x [rows] cells (a `window-change`
  /// request, RFC 4254 §6.7).
  void resize(int columns, int rows);

  /// Delivers a signal by its RFC 4254 §6.9 name (`'INT'`, `'TERM'`, …,
  /// without the `SIG` prefix) — the exact name the client sent, which the
  /// fork's own client emits from its `SSHSignal` enum.
  void signal(String name);
}

/// Spawns the [SSHServerPty] backing one `shell` request.
///
/// Receives the dimensions stashed from the channel's `pty-req` (with `env`
/// request variables merged in); returns the pty, or `null` to refuse the
/// request. An unconfigured factory refuses every shell.
typedef SSHPtyFactory = Future<SSHServerPty?> Function(
  SSHPtyDimensions initial,
);

/// Spawns the [SSHServerProcess] backing one structured `exec` request.
///
/// Receives the decoded argv, working directory and environment; returns the
/// process, or `null` to refuse the request (an unconfigured factory refuses
/// every exec). The argv is never interpreted by a shell — the factory is
/// handed the argument vector exactly as the client structured it.
typedef SSHProcessFactory = Future<SSHServerProcess?> Function(
  List<String> argv,
  String? cwd,
  Map<String, String> env,
);

/// Snapshot of host facts the server reports for the `tp1:` host-info query.
///
/// Answered by the app from `Platform` and self-inspection; faked in tests.
/// The query is served by the server itself — no process is ever spawned for
/// it — and [shell] is a display name only, never used to execute commands.
class SSHHostInfo {
  const SSHHostInfo({
    required this.platform,
    required this.osUser,
    required this.elevated,
    required this.inDocker,
    required this.shell,
  });

  /// Host operating system: `'windows'`, `'macos'` or `'linux'`.
  final String platform;

  /// The user the server runs as.
  final String osUser;

  /// Whether the server process runs with elevated privileges.
  final bool elevated;

  /// Whether the server runs inside a Docker container.
  final bool inDocker;

  /// Display name of the user's shell.
  final String shell;

  /// Wire format of the host-info answer, one object with exactly the five
  /// host facts:
  /// `{"platform":…,"osUser":…,"elevated":…,"inDocker":…,"shell":…}`.
  Map<String, dynamic> toJson() => {
        'platform': platform,
        'osUser': osUser,
        'elevated': elevated,
        'inDocker': inDocker,
        'shell': shell,
      };

  /// Parses a host-info answer produced by [toJson]. Throws a
  /// [FormatException] on anything else — malformed JSON, a non-object
  /// payload, or a missing/mistyped field.
  factory SSHHostInfo.fromJson(String source) => _fromMap(_decodeJsonMap(
        source,
        'host-info payload',
      ));

  static SSHHostInfo _fromMap(Map<String, dynamic> map) {
    final platform = map['platform'];
    final osUser = map['osUser'];
    final elevated = map['elevated'];
    final inDocker = map['inDocker'];
    final shell = map['shell'];
    if (platform is! String ||
        osUser is! String ||
        elevated is! bool ||
        inDocker is! bool ||
        shell is! String) {
      throw const FormatException(
        'host-info payload is missing or has mistyped fields',
      );
    }
    return SSHHostInfo(
      platform: platform,
      osUser: osUser,
      elevated: elevated,
      inDocker: inDocker,
      shell: shell,
    );
  }
}

/// One decoded structured exec request: the process to spawn and the
/// environment it runs in.
class SSHExecRequest {
  const SSHExecRequest({required this.argv, this.cwd, this.env = const {}});

  /// The process to spawn: the executable followed by its arguments. Never
  /// re-interpreted by a shell on the server side.
  final List<String> argv;

  /// Working directory for the process, or `null` for the server default.
  final String? cwd;

  /// Environment variables for the process.
  final Map<String, String> env;
}

/// `tp1:` payload codec — the only exec grammar this server speaks.
///
/// A structured exec command is the [prefix] followed by one JSON object:
///
/// ```
/// tp1:{"argv":["claude","--version"],"cwd":"C:\\work","env":{"K":"V"}}
/// ```
///
/// Anything else — a plain shell string, a missing prefix, malformed JSON,
/// wrong-typed fields — is not this grammar, and the server refuses it rather
/// than handing it to a shell.
class TpExecCodec {
  TpExecCodec._();

  /// The prefix every structured exec command starts with.
  static const prefix = 'tp1:';

  /// The exact host-info query command, `tp1:{"query":"host-info"}`.
  static const _hostInfoQuery = '$prefix{"query":"host-info"}';

  /// Encodes [request] as a structured exec command. The `cwd` and `env`
  /// fields are omitted when empty.
  static String encode(SSHExecRequest request) {
    return '$prefix${jsonEncode({
          'argv': request.argv,
          if (request.cwd != null) 'cwd': request.cwd,
          if (request.env.isNotEmpty) 'env': request.env,
        })}';
  }

  /// Decodes a structured exec command. Returns `null` unless [command] is a
  /// [prefix]-prefixed, well-formed exec payload: the prefix missing, the
  /// JSON malformed, `argv` absent/empty/non-string, or `cwd`/`env` mistyped
  /// all fail closed. The host-info query is not an exec payload; see
  /// [isHostInfoQuery].
  static SSHExecRequest? tryDecode(String command) {
    if (!command.startsWith(prefix)) return null;
    final Map<String, dynamic> map;
    try {
      map = _decodeJsonMap(command.substring(prefix.length), 'exec payload');
    } on FormatException {
      return null;
    }
    final argv = map['argv'];
    if (argv is! List || argv.isEmpty || argv.any((e) => e is! String)) {
      return null;
    }
    final cwd = map['cwd'];
    if (cwd != null && cwd is! String) return null;
    final env = map['env'];
    if (env != null && env is! Map<String, dynamic>) return null;
    if (env != null && env.values.any((value) => value is! String)) {
      return null;
    }
    return SSHExecRequest(
      argv: List<String>.from(argv),
      cwd: cwd as String?,
      env: env == null ? const {} : Map<String, String>.from(env),
    );
  }

  /// Whether [command] is the host-info query.
  static bool isHostInfoQuery(String command) => command == _hostInfoQuery;

  /// Produces the host-info query command.
  static String encodeHostInfoQuery() => _hostInfoQuery;

  /// Encodes [info] as the host-info answer written back on stdout.
  static String encodeHostInfo(SSHHostInfo info) => jsonEncode(info.toJson());
}

/// Decodes [source] as a JSON object, throwing a [FormatException] naming
/// [what] on anything else.
Map<String, dynamic> _decodeJsonMap(String source, String what) {
  Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on Object {
    throw FormatException('malformed JSON in $what');
  }
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('$what is not a JSON object');
  }
  return decoded;
}
