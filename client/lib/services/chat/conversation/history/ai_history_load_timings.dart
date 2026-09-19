/// Optional load-phase timings and counters for chat history.
///
/// Production loaders leave [AiHistoryLoader] timings unset; nothing is
/// recorded and live refresh does not log. Tests inject an instance and assert
/// counts, identity, and order — never wall-clock milliseconds.
///
/// Debug builds always emit a one-line `[ai-history-timing]` summary for cold
/// loads so first-paint regressions are visible in app logs without a test
/// harness.
enum AiHistoryLoadPhase {
  locate,
  read,
  decode,
  parse,
  enrich,
  inflate,
  merge,
  firstPublish,
}

final class AiHistoryLoadTimings {
  final Map<AiHistoryLoadPhase, Duration> phases = {};
  int decoderBatches = 0;
  int decoderLines = 0;
  int sideTranscriptReads = 0;
  final List<AiHistoryLoadPhase> order = [];

  void record(AiHistoryLoadPhase phase, Duration elapsed) {
    phases[phase] = (phases[phase] ?? Duration.zero) + elapsed;
    order.add(phase);
  }

  void addDecoderBatch({required int lines}) {
    decoderBatches++;
    decoderLines += lines;
  }

  void addSideTranscriptRead() => sideTranscriptReads++;
}
