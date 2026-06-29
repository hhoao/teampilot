import 'models.dart';
import 'trace_decoder.dart';

/// Dart-track method slices (e.g. `RenderParagraph.getDryLayout`) that DevTools
/// shows as the widest bars but are excluded from `io.flutter.ui` widget tree.
bool isDartMethodSlice(TraceSlice slice) {
  if (slice.isShaderEvent) return false;
  if (!_isDartTrack(slice)) return false;
  if (slice.name == 'Frame') return false;

  if (slice.name.startsWith('Render') || slice.name.startsWith('_Render')) {
    return true;
  }
  return false;
}

bool _isDartTrack(TraceSlice slice) {
  if (slice.category == 'Dart') return true;
  if (slice.track == 'Dart' || slice.trackLabel == 'Dart') return true;
  return false;
}

/// Render-object class name without method suffix: `RenderParagraph.getDryLayout` → `RenderParagraph`.
String dartRenderClassName(String sliceName) {
  final dot = sliceName.indexOf('.');
  if (dot > 0) return sliceName.substring(0, dot);
  return sliceName;
}

List<TraceSlice> dartMethodSlicesInWindow(List<TraceSlice> inWindow) {
  return [for (final s in inWindow) if (isDartMethodSlice(s)) s];
}

List<DartMethodHotspot> aggregateDartMethodHotspots({
  required Map<String, DartMethodAccumulator> agg,
  required int limit,
}) {
  final entries = agg.entries.toList()
    ..sort((a, b) => b.value.totalMs.compareTo(a.value.totalMs));

  return [
    for (final e in entries.take(limit))
      DartMethodHotspot(
        name: e.key,
        renderClass: dartRenderClassName(e.key),
        totalMs: e.value.totalMs,
        maxMsInSingleFrame: e.value.maxMs,
        frameNumbers: [...e.value.frameNumbers]..sort(),
        occurrenceCount: e.value.frameNumbers.length,
      ),
  ];
}

void accumulateDartMethodSlices(
  Map<String, DartMethodAccumulator> agg,
  List<TraceSlice> inWindow,
  int frameNumber, {
  double minMs = 0,
}) {
  for (final slice in dartMethodSlicesInWindow(inWindow)) {
    if (slice.durationMs < minMs) continue;
    final bucket = agg.putIfAbsent(slice.name, DartMethodAccumulator.new);
    bucket.totalMs += slice.durationMs;
    bucket.maxMs =
        bucket.maxMs < slice.durationMs ? slice.durationMs : bucket.maxMs;
    if (!bucket.frameNumbers.contains(frameNumber)) {
      bucket.frameNumbers.add(frameNumber);
    }
  }
}

class DartMethodAccumulator {
  double totalMs = 0;
  double maxMs = 0;
  final frameNumbers = <int>[];
}

/// Links widget rebuild names to Dart method slices (e.g. `Text` → `RenderParagraph.*`).
bool widgetMatchesDartMethodSlice(String widgetName, String sliceName) {
  if (!sliceName.startsWith('Render') && !sliceName.startsWith('_Render')) {
    return false;
  }

  final normalized = _stripGenerics(widgetName);
  final renderClass = dartRenderClassName(sliceName);

  if (renderClass == normalized || sliceName.contains(normalized)) {
    return true;
  }

  const textWidgets = {'Text', 'RichText', 'SelectableText', 'TextSpan'};
  if (textWidgets.contains(normalized) && renderClass.contains('Paragraph')) {
    return true;
  }

  if (normalized == 'TextField' &&
      (renderClass.contains('Editable') ||
          sliceName.contains('Editable') ||
          sliceName.contains('Paragraph'))) {
    return true;
  }

  if (renderClass.length > 6) {
    final tail = renderClass.substring(6);
    if (tail.contains(normalized) || normalized.contains(tail)) {
      return true;
    }
  }

  return false;
}

String _stripGenerics(String name) {
  final lt = name.indexOf('<');
  if (lt > 0) return name.substring(0, lt);
  return name;
}
