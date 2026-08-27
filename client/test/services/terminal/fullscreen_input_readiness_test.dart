import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/codex/capabilities/terminal_behavior.dart';
import 'package:teampilot/services/terminal/fullscreen_input_readiness.dart';

void main() {
  test('boot-frame-only surfaces are ready without a dwell', () {
    final watch = FullscreenInputSurfaceWatch();
    expect(
      watch.observe(
        readiness: FullscreenInputReadiness.bootFrameOnly,
        probeWindow: '',
      ),
      isTrue,
    );
  });

  test('Codex composer chrome is not submit-ready until dwell elapses', () {
    var now = DateTime(2026, 8, 19, 16);
    final watch = FullscreenInputSurfaceWatch(now: () => now);
    final readiness = const CodexTerminalBehavior().inputReadiness;

    expect(
      watch.observe(readiness: readiness, probeWindow: '› hello'),
      isFalse,
    );

    now = now.add(const Duration(milliseconds: 999));
    expect(
      watch.observe(readiness: readiness, probeWindow: '› hello'),
      isFalse,
    );

    now = now.add(const Duration(milliseconds: 1));
    expect(
      watch.observe(readiness: readiness, probeWindow: '› hello'),
      isTrue,
    );
  });

  test('losing composer chrome restarts the Codex dwell', () {
    var now = DateTime(2026, 8, 19, 16);
    final watch = FullscreenInputSurfaceWatch(now: () => now);
    final readiness = const CodexTerminalBehavior().inputReadiness;

    watch.observe(readiness: readiness, probeWindow: '› hello');
    now = now.add(const Duration(milliseconds: 800));
    expect(
      watch.observe(
        readiness: readiness,
        probeWindow: 'Do you trust this directory?',
      ),
      isFalse,
    );

    now = now.add(const Duration(milliseconds: 200));
    expect(
      watch.observe(readiness: readiness, probeWindow: '› hello'),
      isFalse,
      reason: 'dwell must restart after the composer disappears',
    );

    now = now.add(const Duration(seconds: 1));
    expect(
      watch.observe(readiness: readiness, probeWindow: '› hello'),
      isTrue,
    );
  });

  test('history still painting restarts the Codex dwell', () {
    var now = DateTime(2026, 8, 27, 16);
    final watch = FullscreenInputSurfaceWatch(now: () => now);
    final readiness = const CodexTerminalBehavior().inputReadiness;

    // Resume paints composer chrome immediately, then streams transcript.
    expect(
      watch.observe(
        readiness: readiness,
        probeWindow: 'gpt-5.6-luna default · /tmp\n› ',
      ),
      isFalse,
    );

    now = now.add(const Duration(milliseconds: 800));
    expect(
      watch.observe(
        readiness: readiness,
        probeWindow: 'user: 提交吧\ngpt-5.6-luna default · /tmp\n› ',
      ),
      isFalse,
      reason: 'dwell must restart while resume history is still painting',
    );

    now = now.add(const Duration(milliseconds: 800));
    expect(
      watch.observe(
        readiness: readiness,
        probeWindow: 'assistant: ok\nuser: 提交吧\ngpt-5.6-luna default · /tmp\n› ',
      ),
      isFalse,
      reason: 'each new history frame must restart dwell',
    );

    const settled = 'assistant: ok\nuser: 提交吧\ngpt-5.6-luna default · /tmp\n› ';
    now = now.add(const Duration(milliseconds: 999));
    expect(
      watch.observe(readiness: readiness, probeWindow: settled),
      isFalse,
    );
    now = now.add(const Duration(milliseconds: 1));
    expect(
      watch.observe(readiness: readiness, probeWindow: settled),
      isTrue,
    );

    // Delayed resume replay: chrome can sit still, then history starts later.
    now = now.add(const Duration(milliseconds: 50));
    expect(
      watch.observe(
        readiness: readiness,
        probeWindow: 'later history\n$settled',
      ),
      isFalse,
      reason: 'history starting after chrome was already ready must unready',
    );
  });
}
