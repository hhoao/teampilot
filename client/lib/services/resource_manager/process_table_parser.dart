/// One process row from a host process-table sweep.
///
/// [rssBytes] is always in **bytes**. Unix `ps` RSS columns are kilobytes and
/// are converted here; Windows CIM `WorkingSetSize` is already bytes.
class ProcessTableRow {
  const ProcessTableRow({
    required this.pid,
    required this.ppid,
    required this.cpuPercent,
    required this.rssBytes,
  });

  final int pid;
  final int ppid;

  /// Percent of a single core (may exceed 100 on multi-core).
  final double cpuPercent;

  /// Resident set size in bytes (see class doc for unit conversion).
  final int rssBytes;
}

/// Parses Unix `ps` output with columns `pid ppid %cpu rss`.
///
/// Accepts an optional header line (`PID PPID %CPU RSS`). RSS values are
/// kilobytes and are converted to bytes on [ProcessTableRow.rssBytes].
List<ProcessTableRow> parseUnixProcessTable(String text) {
  final rows = <ProcessTableRow>[];
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (_looksLikeUnixHeader(line)) continue;

    final fields = line.split(RegExp(r'\s+'));
    if (fields.length < 4) continue;

    final pid = int.tryParse(fields[0]);
    final ppid = int.tryParse(fields[1]);
    final cpu = double.tryParse(fields[2]);
    final rssKb = int.tryParse(fields[3]);
    if (pid == null || ppid == null || cpu == null || rssKb == null) continue;

    final rssBytes = rssKb > 0 ? rssKb * 1024 : 0;
    rows.add(
      ProcessTableRow(
        pid: pid,
        ppid: ppid,
        cpuPercent: cpu.isFinite && cpu > 0 ? cpu : 0.0,
        rssBytes: rssBytes,
      ),
    );
  }
  return rows;
}

/// Parses tab-delimited Windows CIM / WMIC-style rows:
/// `ProcessId\tParentProcessId\tWorkingSetSize[\tcpuPercent]`.
///
/// [WorkingSetSize] is already bytes. Missing cpu defaults to `0`.
List<ProcessTableRow> parseWindowsProcessTable(String text) {
  final rows = <ProcessTableRow>[];
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) continue;

    // Preserve empty field positions (CIM nulls) — do not collapse tabs.
    final fields = line.split('\t');
    if (fields.length < 3) continue;

    final pid = int.tryParse(fields[0].trim());
    final ppid = int.tryParse(fields[1].trim());
    if (pid == null || ppid == null) continue;
    if (pid <= 0) continue;
    if (ppid < 0) continue;

    final memoryRaw = int.tryParse(fields[2].trim());
    final rssBytes = (memoryRaw != null && memoryRaw > 0) ? memoryRaw : 0;

    var cpu = 0.0;
    if (fields.length >= 4) {
      final parsed = double.tryParse(fields[3].trim());
      if (parsed != null && parsed.isFinite && parsed > 0) {
        cpu = parsed;
      }
    }

    rows.add(
      ProcessTableRow(
        pid: pid,
        ppid: ppid,
        cpuPercent: cpu,
        rssBytes: rssBytes,
      ),
    );
  }
  return rows;
}

/// Sums CPU % and RSS bytes for [rootPid] and all descendants via [ppid].
///
/// Missing [rootPid] yields `(cpuPercent: 0, memoryBytes: 0)`.
({double cpuPercent, int memoryBytes}) subtreeUsage(
  List<ProcessTableRow> rows,
  int rootPid,
) {
  final byPid = <int, ProcessTableRow>{};
  final childrenOf = <int, List<int>>{};
  for (final row in rows) {
    byPid[row.pid] = row;
    childrenOf.putIfAbsent(row.ppid, () => <int>[]).add(row.pid);
  }

  if (!byPid.containsKey(rootPid)) {
    return (cpuPercent: 0.0, memoryBytes: 0);
  }

  var cpu = 0.0;
  var memory = 0;
  final seen = <int>{};
  final queue = <int>[rootPid];
  while (queue.isNotEmpty) {
    final pid = queue.removeLast();
    if (!seen.add(pid)) continue;
    final row = byPid[pid];
    if (row != null) {
      cpu += row.cpuPercent;
      memory += row.rssBytes;
    }
    final kids = childrenOf[pid];
    if (kids != null) {
      queue.addAll(kids);
    }
  }
  return (cpuPercent: cpu, memoryBytes: memory);
}

bool _looksLikeUnixHeader(String line) {
  final upper = line.toUpperCase();
  return upper.startsWith('PID') && upper.contains('PPID');
}
