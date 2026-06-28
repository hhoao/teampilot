import 'dart:convert';
import 'dart:math' as math;

import 'package:vm_service_protos/vm_service_protos.dart';

const uiBeginFrameName = 'Animator::BeginFrame';
const rasterEventName = 'Rasterizer::DoDraw';
const frameNumberArg = 'frame_number';
const devtoolsTagArg = 'devtoolsTag';
const shadersTag = 'shaders';

class TraceSlice {
  TraceSlice({
    required this.name,
    required this.category,
    required this.track,
    required this.startNs,
    required this.durationNs,
    this.flutterFrameNumber,
    this.isShaderEvent = false,
    this.args = const {},
  });

  final String name;
  final String category;
  final String track;
  final int startNs;
  final int durationNs;
  final int? flutterFrameNumber;
  final bool isShaderEvent;
  final Map<String, String> args;

  double get durationMs => durationNs / 1e6;
  int get endNs => startNs + durationNs;

  String get trackLabel {
    if (track.isNotEmpty && !track.startsWith('track:')) return track;
    if (category.isNotEmpty) return category;
    return track.isEmpty ? '(global)' : track;
  }
}

class TraceInstant {
  TraceInstant({
    required this.name,
    required this.category,
    required this.track,
    required this.timestampNs,
    this.flutterFrameNumber,
    this.isShaderEvent = false,
  });

  final String name;
  final String category;
  final String track;
  final int timestampNs;
  final int? flutterFrameNumber;
  final bool isShaderEvent;
}

class CpuSample {
  CpuSample({
    required this.timestampNs,
    required this.tid,
    required this.frames,
  });

  final int timestampNs;
  final int tid;
  final List<String> frames;
}

class DecodedTrace {
  DecodedTrace({
    required this.slices,
    required this.instants,
    required this.cpuSamples,
    required this.tracks,
    required this.uiTrackUuid,
    required this.rasterTrackUuid,
    required this.uiFrameBeginNs,
    required this.rasterFrameBeginNs,
  });

  final List<TraceSlice> slices;
  final List<TraceInstant> instants;
  final List<CpuSample> cpuSamples;
  final Map<int, String> tracks;
  final int? uiTrackUuid;
  final int? rasterTrackUuid;

  /// Flutter frame number -> UI `Animator::BeginFrame` timestamp (ns).
  final Map<int, int> uiFrameBeginNs;

  /// Flutter frame number -> raster `Rasterizer::DoDraw` timestamp (ns).
  final Map<int, int> rasterFrameBeginNs;

  FrameTimeRange? timeRangeForFrame(int frameNumber, int elapsedUs) {
    final beginNs = uiFrameBeginNs[frameNumber];
    if (beginNs == null) return null;

    final sortedFrames = uiFrameBeginNs.keys.toList()..sort();
    final index = sortedFrames.indexOf(frameNumber);
    final nextBegin = index >= 0 && index + 1 < sortedFrames.length
        ? uiFrameBeginNs[sortedFrames[index + 1]]
        : null;
    final endNs = nextBegin ?? (beginNs + elapsedUs * 1000);
    return FrameTimeRange(beginNs: beginNs, endNs: endNs, source: 'timeline');
  }
}

class FrameTimeRange {
  FrameTimeRange({
    required this.beginNs,
    required this.endNs,
    required this.source,
  });

  final int beginNs;
  final int endNs;
  final String source;
}

DecodedTrace decodeTrace(List<int> bytes) {
  final trace = Trace.fromBuffer(bytes);
  final internedNames = <int, String>{};
  final internedCategories = <int, String>{};
  final internedAnnotationNames = <int, String>{};
  final internedStrings = <int, String>{};
  final profileFrames = <int, Frame>{};
  final profileCallstacks = <int, Callstack>{};
  final tracks = <int, String>{};
  int? uiTrackUuid;
  int? rasterTrackUuid;

  final openStacks = <int, List<_OpenSlice>>{};
  final slices = <TraceSlice>[];
  final instants = <TraceInstant>[];
  final cpuSamples = <CpuSample>[];
  final uiFrameBeginNs = <int, int>{};
  final rasterFrameBeginNs = <int, int>{};

  for (final packet in trace.packet) {
    if (packet.hasInternedData()) {
      final data = packet.internedData;
      for (final item in data.eventNames) {
        internedNames[item.iid.toInt()] = item.name;
      }
      for (final item in data.eventCategories) {
        internedCategories[item.iid.toInt()] = item.name;
      }
      for (final item in data.debugAnnotationNames) {
        internedAnnotationNames[item.iid.toInt()] = item.name;
      }
      for (final item in data.frames) {
        profileFrames[item.iid.toInt()] = item;
      }
      for (final item in data.callstacks) {
        profileCallstacks[item.iid.toInt()] = item;
      }
      for (final item in data.functionNames) {
        internedStrings[item.iid.toInt()] = _decodeInternedString(item);
      }
    }

    if (packet.hasTrackDescriptor()) {
      final td = packet.trackDescriptor;
      final uuid = td.uuid.toInt();
      final name = td.name.isNotEmpty ? td.name : td.thread.threadName;
      tracks[uuid] = name;
      if (name.contains('.ui')) uiTrackUuid ??= uuid;
      if (name.contains('.raster')) rasterTrackUuid ??= uuid;
      if (name.contains('.platform') && rasterTrackUuid == null) {
        rasterTrackUuid = uuid;
      }
    }

    if (packet.hasPerfSample()) {
      final sample = packet.perfSample;
      final ts = packet.timestamp.toInt();
      final stack = _resolveCallstack(
        sample.callstackIid.toInt(),
        profileCallstacks,
        profileFrames,
        internedStrings,
      );
      if (stack.isNotEmpty) {
        cpuSamples.add(
          CpuSample(
            timestampNs: ts,
            tid: sample.tid,
            frames: stack,
          ),
        );
      }
    }

    if (!packet.hasTrackEvent()) continue;
    final ev = packet.trackEvent;
    final ts = packet.timestamp.toInt();
    final trackUuid = ev.trackUuid.toInt();
    final trackName = tracks[trackUuid] ?? 'track:$trackUuid';

    final name = ev.hasName()
        ? ev.name
        : internedNames[ev.nameIid.toInt()] ?? 'event:${ev.nameIid}';
    final category = _resolveCategories(ev, internedCategories);
    final args = _parseDebugAnnotations(ev, internedAnnotationNames);
    final frameNumber = _parseFrameNumber(args);
    final isShader = args[devtoolsTagArg] == shadersTag;

    if (name == uiBeginFrameName && frameNumber != null) {
      uiFrameBeginNs[frameNumber] = ts;
    } else if (name == rasterEventName && frameNumber != null) {
      rasterFrameBeginNs[frameNumber] = ts;
    }

    switch (ev.type) {
      case TrackEvent_Type.TYPE_SLICE_BEGIN:
        openStacks.putIfAbsent(trackUuid, () => []).add(
          _OpenSlice(
            name: name,
            category: category,
            track: trackName,
            startNs: ts,
            flutterFrameNumber: frameNumber,
            isShaderEvent: isShader,
            args: args,
          ),
        );
      case TrackEvent_Type.TYPE_SLICE_END:
        final stack = openStacks[trackUuid];
        if (stack == null || stack.isEmpty) break;
        final open = stack.removeLast();
        if (ts > open.startNs) {
          slices.add(
            TraceSlice(
              name: open.name,
              category: open.category,
              track: open.track,
              startNs: open.startNs,
              durationNs: ts - open.startNs,
              flutterFrameNumber: open.flutterFrameNumber,
              isShaderEvent: open.isShaderEvent,
              args: open.args,
            ),
          );
        }
      case TrackEvent_Type.TYPE_INSTANT:
        instants.add(
          TraceInstant(
            name: name,
            category: category,
            track: trackName,
            timestampNs: ts,
            flutterFrameNumber: frameNumber,
            isShaderEvent: isShader,
          ),
        );
      default:
        break;
    }
  }

  return DecodedTrace(
    slices: slices,
    instants: instants,
    cpuSamples: cpuSamples,
    tracks: tracks,
    uiTrackUuid: uiTrackUuid,
    rasterTrackUuid: rasterTrackUuid,
    uiFrameBeginNs: uiFrameBeginNs,
    rasterFrameBeginNs: rasterFrameBeginNs,
  );
}

class _OpenSlice {
  _OpenSlice({
    required this.name,
    required this.category,
    required this.track,
    required this.startNs,
    this.flutterFrameNumber,
    this.isShaderEvent = false,
    this.args = const {},
  });

  final String name;
  final String category;
  final String track;
  final int startNs;
  final int? flutterFrameNumber;
  final bool isShaderEvent;
  final Map<String, String> args;
}

String _resolveCategories(
  TrackEvent ev,
  Map<int, String> internedCategories,
) {
  if (ev.categories.isNotEmpty) return ev.categories.join(',');
  if (ev.categoryIids.isEmpty) return '';
  return ev.categoryIids
      .map((id) => internedCategories[id.toInt()] ?? 'cat:$id')
      .join(',');
}

Map<String, String> _parseDebugAnnotations(
  TrackEvent ev,
  Map<int, String> internedAnnotationNames,
) {
  final args = <String, String>{};
  for (final annotation in ev.debugAnnotations) {
    final key = annotation.hasName()
        ? annotation.name
        : internedAnnotationNames[annotation.nameIid.toInt()];
    if (key == null || key.isEmpty) continue;

    if (annotation.hasStringValue()) {
      args[key] = annotation.stringValue;
    } else if (annotation.hasLegacyJsonValue()) {
      args[key] = annotation.legacyJsonValue;
    }
  }
  return args;
}

int? _parseFrameNumber(Map<String, String> args) {
  final raw = args[frameNumberArg];
  if (raw == null) return null;
  return int.tryParse(raw);
}

String _decodeInternedString(InternedString item) {
  if (item.str.isEmpty) return '';
  return utf8.decode(item.str, allowMalformed: true);
}

List<String> _resolveCallstack(
  int callstackIid,
  Map<int, Callstack> callstacks,
  Map<int, Frame> frames,
  Map<int, String> internedStrings,
) {
  final callstack = callstacks[callstackIid];
  if (callstack == null) return const [];

  final symbols = <String>[];
  for (final frameId in callstack.frameIds) {
    final frame = frames[frameId.toInt()];
    if (frame == null) continue;
    final symbol = internedStrings[frame.functionNameId.toInt()];
    if (symbol != null && symbol.isNotEmpty) {
      symbols.add(symbol);
    }
  }
  return symbols;
}

List<TraceSlice> slicesForFrame({
  required DecodedTrace trace,
  required int frameNumber,
  required int startTimeUs,
  required int elapsedUs,
}) {
  final markerRange = trace.timeRangeForFrame(frameNumber, elapsedUs);
  final startNs = markerRange?.beginNs ?? startTimeUs * 1000;
  final endNs = markerRange?.endNs ?? (startTimeUs + elapsedUs) * 1000;
  const padNs = 500000;

  return trace.slices
      .where(
        (s) =>
            s.startNs + s.durationNs >= startNs - padNs &&
            s.startNs <= endNs + padNs,
      )
      .toList()
    ..sort((a, b) => b.durationNs.compareTo(a.durationNs));
}

Map<String, int> topCpuSymbols(
  List<CpuSample> samples, {
  int limit = 20,
}) {
  final counts = <String, int>{};
  for (final sample in samples) {
    for (final symbol in sample.frames.take(5)) {
      counts[symbol] = (counts[symbol] ?? 0) + 1;
    }
  }
  final ranked = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return {for (final e in ranked.take(limit)) e.key: e.value};
}

String shortLabel(String value, int maxLen) {
  if (value.length <= maxLen) return value;
  return '${value.substring(0, maxLen - 3)}...';
}

bool isInterestingDartEvent(String name) {
  if (name == 'BUILD' || name == 'LAYOUT' || name.startsWith('LAYOUT')) {
    return true;
  }
  if (name.startsWith('Render') || name.startsWith('_Render')) return true;
  if (name.contains('Panel') || name.contains('Widget')) return true;
  return false;
}

List<MapEntry<String, SliceAggregate>> aggregateSlices(List<TraceSlice> slices) {
  final byName = <String, SliceAggregate>{};
  for (final s in slices) {
    final key = s.category.isEmpty ? s.name : '${s.category}::${s.name}';
    final agg = byName.putIfAbsent(
      key,
      () => SliceAggregate(count: 0, totalNs: 0, maxNs: 0),
    );
    agg.count++;
    agg.totalNs += s.durationNs;
    agg.maxNs = math.max(agg.maxNs, s.durationNs);
  }
  return byName.entries.toList()
    ..sort((a, b) => b.value.totalNs.compareTo(a.value.totalNs));
}

class SliceAggregate {
  SliceAggregate({required this.count, required this.totalNs, required this.maxNs});
  int count;
  int totalNs;
  int maxNs;
}
