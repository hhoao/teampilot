/// Compact token count for UI labels: `300000` → `300K`, `1000000` → `1M`.
String compactTokenCount(int tokens) {
  if (tokens >= 1000000) {
    final millions = tokens / 1000000;
    return '${millions == millions.roundToDouble() ? millions.toInt() : millions.toStringAsFixed(1)}M';
  }
  if (tokens >= 1000) {
    final thousands = tokens / 1000;
    return '${thousands == thousands.roundToDouble() ? thousands.toInt() : thousands.toStringAsFixed(1)}K';
  }
  return '$tokens';
}
