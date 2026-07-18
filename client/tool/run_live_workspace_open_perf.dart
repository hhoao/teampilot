// ignore_for_file: avoid_print
//
// Live performance capture against real local TeamPilot app data.
//
// Usage (from `client/`):
//   dart run tool/run_live_workspace_open_perf.dart
//   dart run tool/run_live_workspace_open_perf.dart --workspace <id>
//   dart run tool/run_live_workspace_open_perf.dart --output build/perf_live.json
//
// Requires a debug app started with --dart-define=PERF_DRIVER=true, or this
// tool will launch one. No Computer Use; navigates via LivePerfDriver HTTP.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'performance_snapshot/analyzer.dart';
import 'performance_snapshot/models.dart';
import 'performance_snapshot/options.dart';
import 'performance_snapshot/report_summary.dart';
import 'performance_snapshot/snapshot_writer.dart';

const _defaultPort = 17999;
const _defaultSettleMs = 1500;

Future<void> main(List<String> args) async {
  if (args.contains('-h') || args.contains('--help')) {
    _printUsage();
    return;
  }

  final clientDir = _clientDirectory();
  final output =
      _readArg(args, '--output') ?? 'build/perf_live_workspace_open.json';
  final workspaceArg = _readArg(args, '--workspace') ?? 'first';
  final settleMs =
      int.tryParse(_readArg(args, '--settle-ms') ?? '') ?? _defaultSettleMs;
  final port =
      int.tryParse(_readArg(args, '--port') ?? '') ?? _defaultPort;
  final noLaunch = args.contains('--no-launch');
  final base = 'http://127.0.0.1:$port';

  final workspaceId = await _resolveWorkspaceId(workspaceArg);
  print('Workspace: $workspaceId');

  Process? launched;
  var attached = await _waitHealth(base, readyRequired: false, timeout: const Duration(seconds: 2));
  if (attached == null) {
    if (noLaunch) {
      stderr.writeln(
        'LivePerfDriver not reachable at $base. Start the app with '
        '--dart-define=PERF_DRIVER=true or omit --no-launch.',
      );
      exit(1);
    }
    print('Launching flutter run with PERF_DRIVER…');
    launched = await Process.start(
      'flutter',
      [
        'run',
        '-d',
        'linux',
        '--dart-define=PERF_DRIVER=true',
        '--dart-define=PERF_DRIVER_PORT=$port',
      ],
      workingDirectory: clientDir.path,
      mode: ProcessStartMode.inheritStdio,
    );
  } else {
    print('Attached to existing LivePerfDriver at $base');
  }

  try {
    final health = await _waitHealth(
      base,
      readyRequired: true,
      timeout: const Duration(minutes: 4),
    );
    if (health == null) {
      stderr.writeln('Timed out waiting for LivePerfDriver ready=$base/health');
      exit(1);
    }

    // Warm: land on home first so the open-workspace transition is measurable.
    await _postJson(base, '/go', {'location': '/home-v2'});
    await Future<void>.delayed(Duration(milliseconds: settleMs));

    final vmUri = await _getVmServiceUri(base);
    final vm = await _connectVm(vmUri);
    try {
      await vm.setVMTimelineFlags(['Dart', 'GC', 'Embedder']);
      await vm.clearVMTimeline();

      await _postJson(base, '/capture/start', {});
      await _postJson(base, '/go', {
        'location': '/home-v2/workspace/$workspaceId',
      });
      await Future<void>.delayed(Duration(milliseconds: settleMs));

      final stop = await _postJson(base, '/capture/stop', {});
      final frameMaps =
          (stop['frames'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final frames = [
        for (final m in frameMaps)
          FlutterFrame(
            number: (m['number'] as num).toInt(),
            startTimeUs: (m['startTime'] as num).toInt(),
            elapsedUs: (m['elapsed'] as num).toInt(),
            buildUs: (m['build'] as num).toInt(),
            rasterUs: (m['raster'] as num).toInt(),
            vsyncUs: (m['vsyncOverhead'] as num?)?.toInt() ?? 0,
          ),
      ];

      final perfetto = await vm.getPerfettoVMTimeline();
      final traceText = perfetto.trace ?? '';
      final traceBinary = traceText.isEmpty
          ? <int>[]
          : base64.decode(traceText);

      final snapshot = buildCapturedSnapshot(
        frames: frames,
        traceBinary: traceBinary,
        displayRefreshRateHz: 60,
        isProfileBuild: false,
      );
      final outFile = output.startsWith('/')
          ? File(output)
          : File('${clientDir.path}/$output');
      await writeDevToolsSnapshotFile(outFile.path, snapshot);
      print('Wrote ${outFile.path} (${frames.length} frames)');

      print('\n=== Performance analysis (${outFile.path}) ===\n');
      final analysis = analyzeSnapshot(
        snapshot,
        AnalyzeOptions.forSummary(),
        snapshotLabel: outFile.path,
      );
      printPerformanceSummary(analysis);
    } finally {
      await vm.dispose();
    }
  } finally {
    // Leave a user-launched app running; only stop the process we started.
    if (launched != null) {
      print('Leaving launched app running (pid ${launched.pid}).');
    }
  }
}

void _printUsage() {
  print('''
Live workspace-open performance capture (real local app data).

  dart run tool/run_live_workspace_open_perf.dart [options]

Options:
  --workspace <id|first>   Workspace to open (default: first on disk)
  --output <path>          Snapshot JSON path
  --settle-ms <n>          Wait after navigation (default: $_defaultSettleMs)
  --port <n>               LivePerfDriver port (default: $_defaultPort)
  --no-launch              Fail if driver is not already running
  -h, --help               Show help
''');
}

Future<String> _resolveWorkspaceId(String arg) async {
  if (arg != 'first' && arg.isNotEmpty) return arg;
  final root = _teampilotRoot();
  final dir = Directory('$root/workspace/workspaces');
  if (!dir.existsSync()) {
    throw StateError('No workspaces at ${dir.path}');
  }
  final ids =
      dir
          .listSync()
          .whereType<Directory>()
          .map((d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last)
          .toList()
        ..sort();
  if (ids.isEmpty) {
    throw StateError('No workspace folders under ${dir.path}');
  }
  return ids.first;
}

String _teampilotRoot() {
  final xdg = Platform.environment['XDG_DATA_HOME'];
  final home = Platform.environment['HOME'] ?? '';
  final base = (xdg != null && xdg.isNotEmpty) ? xdg : '$home/.local/share';
  return '$base/com.hhoa.teampilot';
}

Future<Map<String, dynamic>?> _waitHealth(
  String base, {
  required bool readyRequired,
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    try {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse('$base/health'));
      final res = await req.close().timeout(const Duration(seconds: 2));
      final body = await utf8.decoder.bind(res).join();
      client.close(force: true);
      if (res.statusCode == 200) {
        final map = jsonDecode(body) as Map<String, dynamic>;
        if (!readyRequired || map['ready'] == true) return map;
      }
    } on Object {
      // Retry until timeout.
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  return null;
}

Future<String> _getVmServiceUri(String base) async {
  final client = HttpClient();
  final req = await client.getUrl(Uri.parse('$base/vm-service'));
  final res = await req.close();
  final body = await utf8.decoder.bind(res).join();
  client.close(force: true);
  final map = jsonDecode(body) as Map<String, dynamic>;
  final uri = map['uri'] as String?;
  if (uri == null || uri.isEmpty) {
    throw StateError('VM service URI unavailable from LivePerfDriver');
  }
  return uri;
}

Future<VmService> _connectVm(String serverUri) async {
  var uri = Uri.parse(serverUri);
  if (uri.scheme == 'http') {
    uri = uri.replace(scheme: 'ws');
  }
  return vmServiceConnectUri(uri.toString());
}

Future<Map<String, dynamic>> _postJson(
  String base,
  String path,
  Map<String, Object?> body,
) async {
  final client = HttpClient();
  final req = await client.postUrl(Uri.parse('$base$path'));
  req.headers.contentType = ContentType.json;
  req.write(jsonEncode(body));
  final res = await req.close();
  final text = await utf8.decoder.bind(res).join();
  client.close(force: true);
  final map = jsonDecode(text) as Map<String, dynamic>;
  if (map['ok'] != true) {
    throw StateError('POST $path failed: $text');
  }
  return map;
}

Directory _clientDirectory() {
  final script = Platform.script.toFilePath();
  return File(script).parent.parent;
}

String? _readArg(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i < 0 || i + 1 >= args.length) return null;
  return args[i + 1];
}
