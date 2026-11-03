import 'package:flutter/foundation.dart';

import '../../models/session_usage.dart';
import '../../models/team_config.dart';
import '../../models/session_usage_dashboard.dart';
import '../../models/session_usage_pricing.dart';
import 'usage_aggregator.dart';

/// Dashboard computation for the usage page: the memo cache, the isolate
/// dispatch and the heatmap memo.
///
/// The engine holds no inputs and no UI state: every call passes the events,
/// pricing and attribution, and the caller clears the cache when those inputs
/// change. That keeps the calculator testable without a cubit.
final class UsageDashboardEngine {
  UsageDashboardEngine({this.isolateThreshold = 4000});

  /// Below this many events the dashboard is computed inline; above it the
  /// compute runs in an isolate so the UI thread stays responsive.
  final int isolateThreshold;

  final Map<String, UsageDashboard> _cache = {};
  List<UsageHeatmapDay>? _heatmapCache;
  List<SessionUsageEvent>? _heatmapCacheEvents;
  CliTool? _heatmapCacheCli;
  UsagePricingCatalog? _heatmapCachePricing;

  void clearCache() => _cache.clear();

  /// Cache key: the filter plus the window bucket, so "today" invalidates as
  /// time moves while a closed range stays cached.
  static String keyFor(UsageFilter filter, int nowMs) {
    final nowLocal = DateTime.fromMillisecondsSinceEpoch(nowMs).toLocal();
    final bucket = filter.liveEnd || filter.range == UsageRange.last24Hours
        ? nowMs ~/ 60000
        : DateTime(
            nowLocal.year,
            nowLocal.month,
            nowLocal.day,
          ).millisecondsSinceEpoch;
    return '${filter.range.name}|${filter.cli?.value}|${filter.groupBy.name}|'
        '${filter.query}|${filter.customStartMs}|${filter.customEndMs}|'
        '${filter.accountId ?? '*'}|'
        '${filter.liveEnd}|$bucket';
  }

  /// Cached dashboard for [filter] in the current bucket, if any.
  UsageDashboard? cached(UsageFilter filter, int nowMs) =>
      _cache[keyFor(filter, nowMs)];

  /// Computes on the calling thread and memoises the result.
  UsageDashboard dashboardFor({
    required List<SessionUsageEvent> events,
    required UsageAttribution attribution,
    required UsagePricingCatalog pricing,
    required UsageFilter filter,
    required int nowMs,
  }) {
    final key = keyFor(filter, nowMs);
    final hit = _cache[key];
    if (hit != null) return hit;
    final dashboard = buildUsageDashboard(
      events: events,
      attribution: attribution,
      filter: filter,
      nowMs: nowMs,
      pricing: pricing,
      heatmap: heatmapFor(events: events, pricing: pricing, cli: filter.cli),
    );
    _store(key, dashboard);
    return dashboard;
  }

  /// Computes in an isolate when the event list is large enough to justify it.
  Future<UsageDashboard> dashboardForAsync({
    required List<SessionUsageEvent> events,
    required UsageAttribution attribution,
    required UsagePricingCatalog pricing,
    required UsageFilter filter,
    required int nowMs,
  }) async {
    final key = keyFor(filter, nowMs);
    final hit = _cache[key];
    if (hit != null) return hit;
    if (events.length < isolateThreshold) {
      return dashboardFor(
        events: events,
        attribution: attribution,
        pricing: pricing,
        filter: filter,
        nowMs: nowMs,
      );
    }
    final dashboard = await compute(
      buildUsageDashboardRequest,
      UsageDashboardRequest(
        events: events,
        attribution: attribution,
        filter: filter,
        nowMs: nowMs,
        pricing: pricing,
        heatmap: heatmapFor(
          events: events,
          pricing: pricing,
          cli: filter.cli,
        ),
      ),
    );
    _store(key, dashboard);
    return dashboard;
  }

  /// Heatmap memo keyed on the input identities, which is what the cubit keeps
  /// stable between reloads.
  List<UsageHeatmapDay> heatmapFor({
    required List<SessionUsageEvent> events,
    required UsagePricingCatalog pricing,
    CliTool? cli,
  }) {
    final cached = _heatmapCache;
    if (cached != null &&
        identical(_heatmapCacheEvents, events) &&
        _heatmapCacheCli == cli &&
        identical(_heatmapCachePricing, pricing)) {
      return cached;
    }
    final next = buildUsageHeatmap(events: events, cli: cli, pricing: pricing);
    _heatmapCache = next;
    _heatmapCacheEvents = events;
    _heatmapCacheCli = cli;
    _heatmapCachePricing = pricing;
    return next;
  }

  void _store(String key, UsageDashboard dashboard) {
    if (_cache.length >= 16) _cache.remove(_cache.keys.first);
    _cache[key] = dashboard;
  }
}
