const String kResourceMetricEmDash = '—';

/// Formats byte counts as `{n.n} MB`, or [kResourceMetricEmDash] when null.
String formatResourceMemory(num? bytes) {
  if (bytes == null) {
    return kResourceMetricEmDash;
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Formats CPU percent as `{n.n}%`, or [kResourceMetricEmDash] when null.
String formatResourceCpu(num? cpu) {
  if (cpu == null) {
    return kResourceMetricEmDash;
  }
  return '${cpu.toStringAsFixed(1)}%';
}
