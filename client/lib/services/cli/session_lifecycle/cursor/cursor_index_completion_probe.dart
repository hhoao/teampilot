/// Result of scanning a cursor project `worker.log` tail for index completion.
enum IndexProbeResult {
  pending,
  done,
  failed,
}

/// Pure scanner for cursor workspace index completion markers.
abstract final class CursorIndexCompletionProbe {
  CursorIndexCompletionProbe._();

  static const _doneMarker = 'Indexing finished';
  static const _failedMarker = 'Indexing run failed';

  static IndexProbeResult scan(String logTail) {
    if (logTail.contains(_failedMarker)) return IndexProbeResult.failed;
    if (logTail.contains(_doneMarker)) return IndexProbeResult.done;
    return IndexProbeResult.pending;
  }
}
