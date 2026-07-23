import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/resource_manager/process_table_parser.dart';

void main() {
  late String unixFixture;
  late String windowsFixture;

  setUpAll(() {
    final dir = Directory.current.path.endsWith('client')
        ? Directory.current.path
        : '${Directory.current.path}/client';
    unixFixture = File(
      '$dir/test/services/resource_manager/fixtures/ps_unix.txt',
    ).readAsStringSync();
    windowsFixture = File(
      '$dir/test/services/resource_manager/fixtures/ps_windows_cim.txt',
    ).readAsStringSync();
  });

  group('parseUnixProcessTable', () {
    test('parses headered fixture into rows with RSS KB converted to bytes', () {
      final rows = parseUnixProcessTable(unixFixture);

      expect(rows, hasLength(3));
      expect(rows[0].pid, 1);
      expect(rows[0].ppid, 0);
      expect(rows[0].cpuPercent, 0.0);
      expect(rows[0].rssBytes, 1024 * 1024);

      expect(rows[1].pid, 42);
      expect(rows[1].ppid, 1);
      expect(rows[1].cpuPercent, 1.5);
      expect(rows[1].rssBytes, 20480 * 1024);

      expect(rows[2].pid, 43);
      expect(rows[2].ppid, 42);
      expect(rows[2].cpuPercent, 0.2);
      expect(rows[2].rssBytes, 4096 * 1024);
    });

    test('parses headerless ps -eo style output', () {
      const text = '''
    1     0  0.0  1024
   42     1  1.5 20480
''';
      final rows = parseUnixProcessTable(text);
      expect(rows, hasLength(2));
      expect(rows[0].pid, 1);
      expect(rows[1].rssBytes, 20480 * 1024);
    });

    test('skips malformed lines', () {
      const text = '''
PID PPID %CPU RSS
not a row
42 1 1.5 20480
43 x 0.2 4096
''';
      final rows = parseUnixProcessTable(text);
      expect(rows, hasLength(1));
      expect(rows.single.pid, 42);
    });
  });

  group('parseWindowsProcessTable', () {
    test('parses tab-delimited CIM rows (WorkingSetSize already bytes)', () {
      final rows = parseWindowsProcessTable(windowsFixture);

      expect(rows, hasLength(3));
      expect(rows[0].pid, 1);
      expect(rows[0].ppid, 0);
      expect(rows[0].rssBytes, 1048576);
      expect(rows[0].cpuPercent, 0.0);

      expect(rows[1].pid, 42);
      expect(rows[1].rssBytes, 20971520);
      expect(rows[1].cpuPercent, 1.5);

      expect(rows[2].pid, 43);
      expect(rows[2].rssBytes, 4194304);
      expect(rows[2].cpuPercent, 0.2);
    });

    test('defaults missing cpu field to 0 and clamps invalid memory', () {
      const text = '100\t1\t2048\r\n200\t100\t-50\t1.0\n';
      final rows = parseWindowsProcessTable(text);
      expect(rows, hasLength(2));
      expect(rows[0].cpuPercent, 0.0);
      expect(rows[0].rssBytes, 2048);
      expect(rows[1].rssBytes, 0);
      expect(rows[1].cpuPercent, 1.0);
    });

    test('skips malformed CIM rows', () {
      const text = 'garbage\nabc\t1\t100\n10\txyz\t100\n20\t1\t100\n';
      final rows = parseWindowsProcessTable(text);
      expect(rows, hasLength(1));
      expect(rows.single.pid, 20);
    });
  });

  group('subtreeUsage', () {
    test('sums pid and descendants cpu and rss for unix fixture', () {
      final rows = parseUnixProcessTable(unixFixture);
      final usage = subtreeUsage(rows, 42);

      expect(usage.cpuPercent, closeTo(1.7, 1e-9));
      expect(usage.memoryBytes, (20480 + 4096) * 1024);
    });

    test('sums pid and descendants for windows fixture', () {
      final rows = parseWindowsProcessTable(windowsFixture);
      final usage = subtreeUsage(rows, 42);

      expect(usage.cpuPercent, closeTo(1.7, 1e-9));
      expect(usage.memoryBytes, 20971520 + 4194304);
    });

    test('returns zeros when root pid is missing', () {
      final rows = parseUnixProcessTable(unixFixture);
      final usage = subtreeUsage(rows, 999);
      expect(usage.cpuPercent, 0.0);
      expect(usage.memoryBytes, 0);
    });

    test('sums entire descendant tree rooted at pid 1', () {
      final rows = parseUnixProcessTable(unixFixture);
      final usage = subtreeUsage(rows, 1);
      expect(usage.cpuPercent, closeTo(1.7, 1e-9));
      expect(usage.memoryBytes, (1024 + 20480 + 4096) * 1024);
    });

    test('leaf pid sums only itself', () {
      final rows = parseUnixProcessTable(unixFixture);
      final usage = subtreeUsage(rows, 43);
      expect(usage.cpuPercent, closeTo(0.2, 1e-9));
      expect(usage.memoryBytes, 4096 * 1024);
    });
  });
}
