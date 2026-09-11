// ignore_for_file: avoid_print
//
// Manual live performance capture for jank triage.
//
// Usage (from `client/`), with the app already running with the driver:
//   flutter run -d linux --dart-define=PERF_DRIVER=true
//   dart run tool/dump_live_perf.dart              # default output
//   dart run tool/dump_live_perf.dart --output /tmp/jank.json --seconds 0
//
// `--seconds 0` (default) = interactive mode: press Enter to start recording,
// use the app (reproduce the jank), press Enter again to stop. A positive
// `--seconds` records for that fixed duration instead.
//
// Do NOT open DevTools → Performance while recording (fights over the same
// timeline buffer). Load the saved JSON in DevTools later for a flame chart.

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

Future<void> main(List<String> args) async {
  if (args.contains('-h') || args.contains('--help')) {
    print(
      'Usage: dart run tool/dump_live_perf.dart '
      '[--output <file>] [--seconds <n>] [--port <n>]',
    );
    return;
  }

  final clientDir = _clientDirectory();
  final output =
      _readArg(args, '--output') ?? 'build/perf_live_dump.json';
  final seconds = int.tryParse(_readArg(args, '--seconds') ?? '') ?? 0;
  final port = int.tryParse(_readArg(args, '--port') ?? '') ?? _defaultPort;
  final base = 'http://127.0.0.1:$port';

  final health = await _waitHealth(base, timeout: const Duration(seconds: 3));
  if (health == null) {
    stderr.writeln(
      'LivePerfDriver not reachable at $base — start the app with '
      '--dart-define=PERF_DRIVER=true first.',
    );
    exitCode = 1;
    return;
  }
  print('Driver OK: $health');

  final vmUri = await _getVmServiceUri(base);
  final vm = await _connectVm(vmUri);
  try {
    if (seconds > 0) {
      print('Recording for $seconds s — reproduce the jank now…');
      await _recordAndDump(
        vm: vm,
        base: base,
        outFile: output.startsWith('/')
            ? File(output)
            : File('${clientDir.path}/$output'),
        record: () => Future<void>.delayed(Duration(seconds: seconds)),
      );
    } else {
      stdout.write('Press Enter to START recording > ');
      await readLineFromStdin();
      await _recordAndDump(
        vm: vm,
        base: base,
        outFile: output.startsWith('/')
            ? File(output)
            : File('${clientDir.path}/$output'),
        record: () {
          stdout.write(
            'Recording… reproduce the jank, then press Enter to STOP > ',
          );
          return readLineFromStdin();
        },
      );
    }
  } finally {
    await vm.dispose();
  }
}

Future<void> _recordAndDump({
  required VmService vm,
  required String base,
  required File outFile,
  required Future<void> Function() record,
}) async {
  await vm.setVMTimelineFlags(['Dart', 'GC', 'Embedder']);
  await vm.clearVMTimeline();

  await _postJson(base, '/capture/start', {});
  await record();
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
  final traceBinary =
      traceText.isEmpty ? <int>[] : base64.decode(traceText);

  final snapshot = buildCapturedSnapshot(
    frames: frames,
    traceBinary: traceBinary,
    displayRefreshRateHz: 60,
    isProfileBuild: false,
  );
  await writeDevToolsSnapshotFile(outFile.path, snapshot);
  print('Wrote ${outFile.path} (${frames.length} frames)');

  print('\n=== Performance analysis (${outFile.path}) ===\n');
  final analysis = analyzeSnapshot(
    snapshot,
    AnalyzeOptions.forSummary(),
    snapshotLabel: outFile.path,
  );
  printPerformanceSummary(analysis);
}

/// One line from [stdin]. [Stdin] is single-subscription, so all reads must
/// share the single subscription created lazily here.
final _stdinLineQueue = <Completer<String>>[];
StreamSubscription<String>? _stdinSub;

Future<String> readLineFromStdin() {
  final completer = Completer<String>();
  _stdinLineQueue.add(completer);
  _startStdinSubscriptionIfNeeded();
  return completer.future;
}

void _startStdinSubscriptionIfNeeded() {
  if (_stdinSub != null) return;
  _stdinSub = stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(
        (line) {
          if (_stdinLineQueue.isEmpty) return;
          _stdinLineQueue.removeAt(0).complete(line);
        },
        onDone: () {
          for (final c in _stdinLineQueue) {
            c.completeError(
              StateError('stdin closed before a line was read'),
            );
          }
          _stdinLineQueue.clear();
        },
      );
}

/// Reads `--name value` from [args].
String? _readArg(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i < 0 || i + 1 >= args.length) return null;
  return args[i + 1];
}

Map<String, dynamic>? _readHealthJson(String body) {
  try {
    return jsonDecode(body) as Map<String, dynamic>;
  } on FormatException {
    return null;
  }
}

Future<Map<String, dynamic>?> _waitHealth(
  String base, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    try {
      final req = await HttpClient().getUrl(Uri.parse('$base/health'));
      final res = await req.close();
      if (res.statusCode == HttpStatus.ok) {
        final text = await utf8.decoder.bind(res).join();
        return _readHealthJson(text);
      }
    } on Object {
      // not up yet
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  return null;
}

Future<String> _getVmServiceUri(String base) async {
  final req = await HttpClient().getUrl(Uri.parse('$base/vm-service'));
  final res = await req.close();
  final map = _readHealthJson(await utf8.decoder.bind(res).join());
  final uri = map?['uri'] as String?;
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
  Object body,
) async {
  final req = await HttpClient().postUrl(Uri.parse('$base$path'));
  req.headers.contentType = ContentType.json;
  req.write(jsonEncode(body));
  final res = await req.close();
  final text = await utf8.decoder.bind(res).join();
  return _readHealthJson(text) ?? <String, dynamic>{};
}

Directory _clientDirectory() {
  var dir = Directory.current;
  while (!File('${dir.path}/pubspec.yaml').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('Run from the client/ directory (or a subdirectory).');
    }
    dir = parent;
  }
  return dir;
}
