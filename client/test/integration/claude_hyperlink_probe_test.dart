@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:teampilot/services/terminal/pty_launch_environment.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

/// Probes Claude Code link output under [TerminalSession.buildPtyEnvironment].
///
/// Run (Linux, after `flutter build linux` for PTY):
/// ```bash
/// cd client
/// export LD_LIBRARY_PATH=build/linux/x64/debug/bundle/lib
/// flutter test test/integration/claude_hyperlink_probe_test.dart
/// ```
const _prompt = '随便给我发个链接，我要看看我的终端能不能点击';

const _listenTimeout = Duration(seconds: 90);

abstract final class _Osc8Patterns {
  static final open = RegExp(r'\x1b\]8;[^;\x1b\x07]*;');
  static final uriInOsc = RegExp(r'\x1b\]8;[^;]*;([^\x07\x1b]+)');
  static final plainUrl = RegExp(
    r'https?://[^\s<>"\]\x1b\x07]+',
    caseSensitive: false,
  );
}

class HyperlinkProbeReport {
  HyperlinkProbeReport({
    required this.rawOutput,
    required this.termProgram,
    required this.vteVersion,
    required this.term,
    required this.osc8OpenCount,
    required this.osc8Uris,
    required this.plainUrls,
    required this.usedPty,
    this.exitCode,
    this.error,
  });

  final String rawOutput;
  final String? termProgram;
  final String? vteVersion;
  final String? term;
  final int osc8OpenCount;
  final List<String> osc8Uris;
  final List<String> plainUrls;
  final bool usedPty;
  final int? exitCode;
  final String? error;

  bool get hasOsc8 => osc8OpenCount > 0;

  bool get hasPlainUrls => plainUrls.isNotEmpty;

  String get summary => [
    'transport: ${usedPty ? 'flutter_pty' : 'Process (pipe)'}',
    'TERM_PROGRAM: ${termProgram ?? '(not in output)'}',
    'VTE_VERSION: ${vteVersion ?? '(not in output)'}',
    'TERM: ${term ?? '(not in output)'}',
    'OSC 8 sequences: $osc8OpenCount',
    if (osc8Uris.isNotEmpty) 'OSC 8 URIs: ${osc8Uris.join(', ')}',
    'plain https?:// URLs: ${plainUrls.length}',
    if (plainUrls.isNotEmpty) '  ${plainUrls.take(5).join('\n  ')}',
    if (error != null) 'error: $error',
    if (exitCode != null) 'exit: $exitCode',
  ].join('\n');

  static HyperlinkProbeReport analyze(
    String output, {
    required bool usedPty,
    int? exitCode,
    String? error,
  }) {
    final envBlock = RegExp(
      r'TERM_PROGRAM=([^\s]+)\s+VTE_VERSION=([^\s]+)(?:\s+TERM=([^\s]+))?',
    ).firstMatch(output);
    final osc8Uris = <String>[];
    for (final m in _Osc8Patterns.uriInOsc.allMatches(output)) {
      final uri = m.group(1)?.trim();
      if (uri != null && uri.isNotEmpty) {
        osc8Uris.add(uri);
      }
    }
    final plainUrls = _Osc8Patterns.plainUrl
        .allMatches(output)
        .map((m) => m.group(0)!)
        .toSet()
        .toList();

    return HyperlinkProbeReport(
      rawOutput: output,
      termProgram: envBlock?.group(1),
      vteVersion: envBlock?.group(2),
      term: envBlock?.group(3),
      osc8OpenCount: _Osc8Patterns.open.allMatches(output).length,
      osc8Uris: osc8Uris,
      plainUrls: plainUrls,
      usedPty: usedPty,
      exitCode: exitCode,
      error: error,
    );
  }
}

String? _resolveClaudeExecutable() {
  try {
    final result = Process.runSync('which', ['claude']);
    if (result.exitCode != 0) return null;
    final line = result.stdout.toString().trim().split('\n').first.trim();
    return line.isEmpty ? null : line;
  } on ProcessException {
    return null;
  }
}

bool _linuxPtyLibraryAvailable() {
  if (!Platform.isLinux) return false;
  const candidates = [
    'libflutter_pty.so',
    'build/linux/x64/debug/bundle/lib/libflutter_pty.so',
    'build/linux/x64/debug/plugins/flutter_pty/shared/libflutter_pty.so',
  ];
  for (final path in candidates) {
    try {
      DynamicLibrary.open(path);
      return true;
    } catch (_) {}
  }
  return false;
}

String _shellQuote(String value) {
  return "'${value.replaceAll("'", r"'\''")}'";
}

List<String> _probeShellCommand(String claudePath) {
  final q = _shellQuote(claudePath);
  final p = _shellQuote(_prompt);
  return [
    '-lc',
    '''
echo "=== TeamPilot PTY environment ==="
echo "TERM_PROGRAM=\$TERM_PROGRAM VTE_VERSION=\$VTE_VERSION TERM=\$TERM"
echo "=== claude -p ==="
$q -p $p 2>&1
echo "=== probe done ==="
''',
  ];
}

Future<String> _collectStream(
  Stream<List<int>> stream,
  Duration timeout,
) async {
  final buffer = StringBuffer();
  final sub = stream.listen((data) {
    buffer.write(utf8.decode(data, allowMalformed: true));
  });
  await Future<void>.delayed(timeout);
  await sub.cancel();
  return buffer.toString();
}

Future<HyperlinkProbeReport> _runPtyProbe(
  String claudePath,
  Map<String, String> environment,
) async {
  Pty? pty;
  try {
    pty = Pty.start(
      '/bin/bash',
      arguments: _probeShellCommand(claudePath),
      workingDirectory: Directory.current.path,
      columns: 120,
      rows: 32,
      environment: environment,
    );
    final output = await _collectStream(pty.output, _listenTimeout);
    final exitCode = await pty.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        pty!.kill();
        return -1;
      },
    );
    return HyperlinkProbeReport.analyze(
      output,
      usedPty: true,
      exitCode: exitCode,
    );
  } on Object catch (e) {
    return HyperlinkProbeReport.analyze(
      '',
      usedPty: true,
      error: e.toString(),
    );
  }
}

Future<HyperlinkProbeReport> _runProcessProbe(
  String claudePath,
  Map<String, String> environment,
) async {
  try {
    final process = await Process.start(
      '/bin/bash',
      _probeShellCommand(claudePath),
      workingDirectory: Directory.current.path,
      environment: environment,
    );
    final output = await _collectStream(
      process.stdout,
      _listenTimeout,
    );
    final stderr = await _collectStream(
      process.stderr,
      const Duration(seconds: 2),
    );
    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    return HyperlinkProbeReport.analyze(
      '$output$stderr',
      usedPty: false,
      exitCode: exitCode,
    );
  } on Object catch (e) {
    return HyperlinkProbeReport.analyze(
      '',
      usedPty: false,
      error: e.toString(),
    );
  }
}

void _printReport(HyperlinkProbeReport report) {
  // ignore: avoid_print
  print('\n${'=' * 60}');
  // ignore: avoid_print
  print('Claude hyperlink integration probe');
  // ignore: avoid_print
  print('=' * 60);
  // ignore: avoid_print
  print(report.summary);
  // ignore: avoid_print
  print('-' * 60);
  // ignore: avoid_print
  print('--- raw output (ANSI stripped preview) ---');
  final preview = report.rawOutput
      .replaceAll(RegExp(r'\x1b\[[0-9;?]*[ -/]*[@-~]'), '')
      .replaceAll(RegExp(r'\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)'), '');
  // ignore: avoid_print
  print(preview.length > 4000 ? '${preview.substring(0, 4000)}…' : preview);
  // ignore: avoid_print
  print('-' * 60);
  if (report.hasOsc8) {
    // ignore: avoid_print
    print('✓ OSC 8 hyperlinks detected — TeamPilot xterm can open via Ctrl/Cmd+click');
  } else if (report.hasPlainUrls) {
    // ignore: avoid_print
    print(
      '○ Plain URLs only (no OSC 8). '
      'TeamPilot OSC-8-only mode will NOT make these clickable; '
      'Claude may need interactive TUI or a build with supportsHyperlinks.',
    );
  } else {
    // ignore: avoid_print
    print('✗ No URLs in output — check claude auth / API / timeout');
  }
  // ignore: avoid_print
  print('${'=' * 60}\n');
}

void main() {
  final claudePath = _resolveClaudeExecutable();
  final ptyAvailable = _linuxPtyLibraryAvailable();

  test(
    'claude link probe — TeamPilot PTY env + prompt',
    () async {
      if (claudePath == null) {
        markTestSkipped('claude not found on PATH');
      }

      final environment = TerminalSession.buildPtyEnvironment(null);
      expect(
        environment['TERM_PROGRAM'],
        PtyLaunchEnvironment.termProgram,
      );
      expect(environment['VTE_VERSION'], PtyLaunchEnvironment.vteVersion);

      final report = ptyAvailable
          ? await _runPtyProbe(claudePath!, environment)
          : await _runProcessProbe(claudePath!, environment);

      _printReport(report);

      expect(report.error, isNull, reason: report.error);
      expect(
        report.termProgram,
        PtyLaunchEnvironment.termProgram,
        reason: 'PTY child should see injected TERM_PROGRAM',
      );
      expect(
        report.vteVersion,
        PtyLaunchEnvironment.vteVersion,
        reason: 'PTY child should see injected VTE_VERSION',
      );
      expect(
        report.hasPlainUrls || report.hasOsc8,
        isTrue,
        reason: 'Claude should return at least one URL in the response',
      );

      // Informational: OSC 8 is desired but claude -p often emits plain URLs only.
      if (!report.hasOsc8) {
        // ignore: avoid_print
        print(
          'NOTE: claude -p returned plain URLs without OSC 8. '
          'This is expected for print mode; use interactive session in TeamPilot '
          'or verify supportsHyperlinks() in the installed claude binary.',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
