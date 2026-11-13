import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import '../../models/session_usage.dart';
import '../../models/session_usage_dashboard.dart';
import '../../models/session_usage_pricing.dart';
import 'usage_dashboard_engine.dart';

/// Raw event-store bytes plus account events that are already decoded.
///
/// [bytes] is transferable so a multi-MB store is handed to the worker without
/// a copy. Materialize it exactly once, on the isolate that decodes it.
final class UsageSource {
  UsageSource({
    required Uint8List eventsJsonl,
    this.cursorEvents = const [],
  }) : bytes = TransferableTypedData.fromList([eventsJsonl]);

  final TransferableTypedData bytes;
  final List<SessionUsageEvent> cursorEvents;

  factory UsageSource.fromEvents(List<SessionUsageEvent> events) {
    final buffer = StringBuffer();
    for (final event in events) {
      buffer.writeln(jsonEncode({'rev': 0, 'event': event.toJson()}));
    }
    return UsageSource(
      eventsJsonl: Uint8List.fromList(utf8.encode(buffer.toString())),
    );
  }

  Uint8List materialize() => bytes.materialize().asUint8List();
}

/// Everything the worker needs to (re)load the event set and build a dashboard.
final class UsageLoad {
  const UsageLoad({
    required this.source,
    required this.attribution,
    required this.pricing,
    required this.filter,
    required this.nowMs,
  });

  final UsageSource source;
  final UsageAttribution attribution;
  final UsagePricingCatalog pricing;
  final UsageFilter filter;
  final int nowMs;
}

/// Parses the append-only store into the latest revision per request id,
/// overlays account events, and sorts by timestamp.
List<SessionUsageEvent> decodeUsageEvents(UsageSource source) {
  final raw = utf8.decode(source.materialize(), allowMalformed: true);
  final index = <String, ({SessionUsageEvent event, int revision})>{};
  for (final line in const LineSplitter().convert(raw)) {
    if (line.trim().isEmpty) continue;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) continue;
      final revision = (decoded['rev'] as num?)?.toInt() ?? 0;
      final eventRaw = decoded['event'];
      if (eventRaw is! Map) continue;
      final event = SessionUsageEvent.fromJson(
        Map<String, Object?>.from(eventRaw),
      );
      if (event.requestId.isEmpty) continue;
      final previous = index[event.requestId];
      if (previous == null || revision >= previous.revision) {
        index[event.requestId] = (event: event, revision: revision);
      }
    } on Object {
      // A crash can leave a torn last line in the append-only store.
    }
  }
  final merged = <String, SessionUsageEvent>{
    for (final entry in index.entries) entry.key: entry.value.event,
  };
  for (final event in source.cursorEvents) {
    merged[event.requestId] = event;
  }
  final events = merged.values.toList();
  events.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
  return events;
}

/// Owns the decoded events and the dashboard memo. Shared by both worker
/// implementations so there is one definition of load/compute.
final class _UsageState {
  final UsageDashboardEngine _engine = UsageDashboardEngine();
  List<SessionUsageEvent> _events = const [];
  UsageAttribution _attribution = const UsageAttribution();
  UsagePricingCatalog _pricing = const UsagePricingCatalog();

  UsageDashboard load(UsageLoad input) {
    _events = decodeUsageEvents(input.source);
    _attribution = input.attribution;
    _pricing = input.pricing;
    _engine.clearCache();
    return _dashboard(input.filter, input.nowMs);
  }

  UsageDashboard compute(
    UsageFilter filter,
    int nowMs, {
    UsagePricingCatalog? pricing,
  }) {
    if (pricing != null) {
      _pricing = pricing;
      _engine.clearCache();
    }
    return _dashboard(filter, nowMs);
  }

  UsageDashboard _dashboard(UsageFilter filter, int nowMs) =>
      _engine.dashboardFor(
        events: _events,
        attribution: _attribution,
        pricing: _pricing,
        filter: filter,
        nowMs: nowMs,
      );
}

/// The UI isolate only ever receives a [UsageDashboard], never the event list.
abstract interface class UsageDataWorker {
  Future<UsageDashboard> load(UsageLoad input);

  Future<UsageDashboard> compute(
    UsageFilter filter,
    int nowMs, {
    UsagePricingCatalog? pricing,
  });

  void close();
}

/// Runs on the calling isolate. Used by tests and as the default.
final class InlineUsageDataWorker implements UsageDataWorker {
  final _UsageState _state = _UsageState();

  @override
  Future<UsageDashboard> load(UsageLoad input) =>
      Future.value(_state.load(input));

  @override
  Future<UsageDashboard> compute(
    UsageFilter filter,
    int nowMs, {
    UsagePricingCatalog? pricing,
  }) => Future.value(_state.compute(filter, nowMs, pricing: pricing));

  @override
  void close() {}
}

/// One resident isolate, spawned on first use. A long-lived spawn avoids the
/// per-request `compute()` copies and the debug cold-start hang of
/// `Isolate.run`.
final class IsolateUsageDataWorker implements UsageDataWorker {
  ReceivePort? _responses;
  StreamSubscription<dynamic>? _responsesSub;
  Isolate? _isolate;
  SendPort? _requestPort;
  Future<void>? _started;
  bool _closed = false;
  final _pending = <int, Completer<UsageDashboard>>{};
  var _nextId = 0;

  @override
  Future<UsageDashboard> load(UsageLoad input) =>
      _send(_LoadRequest(_nextId++, input));

  @override
  Future<UsageDashboard> compute(
    UsageFilter filter,
    int nowMs, {
    UsagePricingCatalog? pricing,
  }) => _send(
    _ComputeRequest(_nextId++, filter, nowMs, pricing),
  );

  Future<UsageDashboard> _send(_UsageRequest request) async {
    await _ensureStarted();
    final completer = Completer<UsageDashboard>();
    _pending[request.id] = completer;
    _requestPort!.send(request);
    return completer.future;
  }

  Future<void> _ensureStarted() => _started ??= _start();

  Future<void> _start() async {
    final responses = ReceivePort();
    _responses = responses;
    final ready = Completer<SendPort>();
    _responsesSub = responses.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
        return;
      }
      final response = message as _UsageResponse;
      _pending.remove(response.id)?.complete(response.dashboard);
    });
    final isolate = await Isolate.spawn(
      _usageWorkerEntry,
      _UsageSpawnArgs(responses.sendPort),
      debugName: 'usage-dashboard-worker',
    );
    if (_closed) {
      isolate.kill(priority: Isolate.immediate);
      return;
    }
    _isolate = isolate;
    _requestPort = await ready.future;
  }

  @override
  void close() {
    _closed = true;
    unawaited(_responsesSub?.cancel());
    _responses?.close();
    _isolate?.kill(priority: Isolate.immediate);
    final error = StateError('usage worker closed');
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
  }
}

sealed class _UsageRequest {
  const _UsageRequest(this.id);

  final int id;
}

final class _LoadRequest extends _UsageRequest {
  const _LoadRequest(super.id, this.input);

  final UsageLoad input;
}

final class _ComputeRequest extends _UsageRequest {
  const _ComputeRequest(super.id, this.filter, this.nowMs, this.pricing);

  final UsageFilter filter;
  final int nowMs;
  final UsagePricingCatalog? pricing;
}

final class _UsageResponse {
  const _UsageResponse(this.id, this.dashboard);

  final int id;
  final UsageDashboard dashboard;
}

final class _UsageSpawnArgs {
  const _UsageSpawnArgs(this.responses);

  final SendPort responses;
}

void _usageWorkerEntry(_UsageSpawnArgs args) {
  final requests = ReceivePort();
  args.responses.send(requests.sendPort);
  final state = _UsageState();
  requests.listen((message) {
    if (message is _LoadRequest) {
      args.responses.send(
        _UsageResponse(message.id, state.load(message.input)),
      );
      return;
    }
    if (message is _ComputeRequest) {
      args.responses.send(
        _UsageResponse(
          message.id,
          state.compute(
            message.filter,
            message.nowMs,
            pricing: message.pricing,
          ),
        ),
      );
    }
  });
}
