import 'dart:convert';

import '../models/automation.dart';
import '../models/automation_tab_scope.dart';
import '../services/automation/automation_launch_session_binding.dart';
import '../services/io/filesystem.dart';
import '../services/storage/workspace_layout.dart';
import '../utils/logger.dart';

class AutomationCatalogEntry {
  const AutomationCatalogEntry({
    required this.workspaceId,
    required this.launchProfileId,
    required this.path,
    required this.updatedAtMs,
  });

  factory AutomationCatalogEntry.fromJson(Map<String, Object?> json) {
    return AutomationCatalogEntry(
      workspaceId: json['workspaceId'] as String? ?? '',
      launchProfileId: json['profile'] as String? ?? '',
      path: json['path'] as String? ?? '',
      updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  final String workspaceId;
  final String launchProfileId;
  final String path;
  final int updatedAtMs;

  AutomationTabScope get tabScope => AutomationTabScope(
        workspaceId: workspaceId,
        launchProfileId: launchProfileId,
      );

  Map<String, Object?> toJson() => {
        'workspaceId': workspaceId,
        'profile': launchProfileId,
        'path': path,
        'updatedAtMs': updatedAtMs,
      };
}

class _TabAutomationStore {
  const _TabAutomationStore({
    required this.automations,
    required this.runs,
  });

  final List<Automation> automations;
  final List<AutomationRun> runs;

  Map<String, Object?> toJson() => {
        'automations': automations.map((a) => a.toJson()).toList(),
        'runs': runs.map((r) => r.toJson()).toList(),
      };

  factory _TabAutomationStore.fromJson(Map<String, Object?> json) {
    final automationsRaw = json['automations'];
    final runsRaw = json['runs'];
    return _TabAutomationStore(
      automations: automationsRaw is List
          ? automationsRaw
                .whereType<Map<String, Object?>>()
                .map(Automation.fromJson)
                .toList(growable: false)
          : const [],
      runs: runsRaw is List
          ? runsRaw
                .whereType<Map<String, Object?>>()
                .map(AutomationRun.fromJson)
                .toList(growable: false)
          : const [],
    );
  }

  _TabAutomationStore copyWith({
    List<Automation>? automations,
    List<AutomationRun>? runs,
  }) {
    return _TabAutomationStore(
      automations: automations ?? this.automations,
      runs: runs ?? this.runs,
    );
  }
}

class AutomationRepository {
  AutomationRepository({
    required Filesystem fs,
    required WorkspaceLayout layout,
    this.maxRunsPerTabScope = 100,
  })  : _fs = fs,
        _layout = layout;

  final Filesystem _fs;
  final WorkspaceLayout _layout;
  final int maxRunsPerTabScope;

  Future<List<Automation>> listForTabScope(AutomationTabScope scope) async {
    final store = await _readStore(scope);
    return store.automations;
  }

  Future<List<Automation>> listForSession(
    AutomationTabScope scope,
    String sessionId,
  ) async {
    final trimmedSession = sessionId.trim();
    final automations = await listForTabScope(scope);
    return automations
        .where((a) => a.sessionId == trimmedSession)
        .toList(growable: false);
  }

  Future<List<Automation>> listAll() async {
    final catalog = await _readCatalog();
    final all = <Automation>[];
    for (final entry in catalog) {
      all.addAll(await listForTabScope(entry.tabScope));
    }
    return all;
  }

  Future<List<AutomationRun>> runsForTabScope(AutomationTabScope scope) async {
    final store = await _readStore(scope);
    return store.runs;
  }

  Future<List<AutomationRun>> runsFor(
    AutomationTabScope scope, {
    String? automationId,
  }) async {
    final store = await _readStore(scope);
    final trimmedId = automationId?.trim();
    if (trimmedId == null || trimmedId.isEmpty) {
      return store.runs;
    }
    return store.runs
        .where((r) => r.automationId == trimmedId)
        .toList(growable: false);
  }

  Future<void> upsertRun(AutomationTabScope scope, AutomationRun run) async {
    final store = await _readStore(scope);
    final runs = List<AutomationRun>.from(store.runs);
    final index = runs.indexWhere((r) => r.id == run.id);
    if (index >= 0) {
      runs[index] = run;
    } else {
      runs.add(run);
    }
    final trimmed = runs.length > maxRunsPerTabScope
        ? runs.sublist(runs.length - maxRunsPerTabScope)
        : runs;
    await _writeStore(scope, store.copyWith(runs: trimmed));
  }

  Future<Automation> upsert(Automation automation) async {
    automation.validate();
    final scope = automation.tabScope;
    final store = await _readStore(scope);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final next = automation.copyWith(
      updatedAtMs: nowMs,
      createdAtMs: automation.createdAtMs > 0 ? automation.createdAtMs : nowMs,
    );
    final index = store.automations.indexWhere((a) => a.id == next.id);
    final automations = List<Automation>.from(store.automations);
    if (index >= 0) {
      automations[index] = next;
    } else {
      automations.add(next);
    }
    await _writeStore(scope, store.copyWith(automations: automations));
    await _upsertCatalogEntry(scope, nowMs);
    return next;
  }

  Future<void> delete(AutomationTabScope scope, String automationId) async {
    final store = await _readStore(scope);
    final automations = store.automations
        .where((a) => a.id != automationId)
        .toList(growable: false);
    final runs = store.runs
        .where((r) => r.automationId != automationId)
        .toList(growable: false);
    await _writeStore(
      scope,
      store.copyWith(automations: automations, runs: runs),
    );
    await _upsertCatalogEntry(
      scope,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> appendRun(AutomationTabScope scope, AutomationRun run) async {
    await upsertRun(scope, run);
  }

  Future<void> disableForSession(AutomationTabScope scope, String sessionId) async {
    final trimmedSession = sessionId.trim();
    final store = await _readStore(scope);
    var changed = false;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final automations = store.automations.map((a) {
      if (a.sessionId != trimmedSession) return a;
      final next = AutomationLaunchSessionBinding.onBoundSessionRemoved(a);
      if (next == a) return a;
      changed = true;
      return next.copyWith(updatedAtMs: nowMs);
    }).toList(growable: false);
    if (!changed) return;
    await _writeStore(scope, store.copyWith(automations: automations));
    await _upsertCatalogEntry(scope, nowMs);
  }

  Future<void> removeWorkspace(String workspaceId) async {
    final trimmed = workspaceId.trim();
    if (trimmed.isEmpty) return;
    final catalog = List<AutomationCatalogEntry>.from(await _readCatalog());
    final nextCatalog = catalog
        .where((e) => e.workspaceId != trimmed)
        .toList(growable: false);
    if (nextCatalog.length != catalog.length) {
      await _writeCatalog(nextCatalog);
    }
    final dir = _layout.workspaceAutomationsDir(trimmed);
    try {
      final stat = await _fs.stat(dir);
      if (stat.isDirectory) {
        await _fs.removeRecursive(dir);
      }
    } on Object catch (e) {
      appLogger.w('[automations] remove workspace dir failed ($trimmed): $e');
    }
  }

  Future<_TabAutomationStore> _readStore(AutomationTabScope scope) async {
    final path = _layout.workspaceTabAutomationsFile(
      scope.workspaceId,
      scope.launchProfileId,
    );
    try {
      final raw = await _fs.readString(path);
      if (raw == null || raw.trim().isEmpty) {
        return const _TabAutomationStore(automations: [], runs: []);
      }
      final decoded = json.decode(raw);
      if (decoded is! Map<String, Object?>) {
        return const _TabAutomationStore(automations: [], runs: []);
      }
      return _TabAutomationStore.fromJson(decoded);
    } on Object catch (e) {
      appLogger.w(
        '[automations] read store failed (${scope.tabKey}): $e',
      );
      return const _TabAutomationStore(automations: [], runs: []);
    }
  }

  Future<void> _writeStore(
    AutomationTabScope scope,
    _TabAutomationStore store,
  ) async {
    final path = _layout.workspaceTabAutomationsFile(
      scope.workspaceId,
      scope.launchProfileId,
    );
    await _fs.ensureDir(_layout.workspaceAutomationsDir(scope.workspaceId));
    final encoded = jsonEncode(store.toJson());
    await _fs.atomicWrite(path, encoded);
  }

  Future<List<AutomationCatalogEntry>> _readCatalog() async {
    final path = _layout.automationsCatalogFile();
    try {
      final raw = await _fs.readString(path);
      if (raw == null || raw.trim().isEmpty) return const [];
      final decoded = json.decode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, Object?>>()
          .map(AutomationCatalogEntry.fromJson)
          .where(
            (e) => e.workspaceId.isNotEmpty && e.launchProfileId.isNotEmpty,
          )
          .toList(growable: false);
    } on Object catch (e) {
      appLogger.w('[automations] read catalog failed: $e');
      return const [];
    }
  }

  Future<void> _writeCatalog(List<AutomationCatalogEntry> entries) async {
    final path = _layout.automationsCatalogFile();
    await _fs.ensureDir(_layout.automationsRootDir());
    final encoded = jsonEncode(entries.map((e) => e.toJson()).toList());
    await _fs.atomicWrite(path, encoded);
  }

  Future<void> _upsertCatalogEntry(
    AutomationTabScope scope,
    int updatedAtMs,
  ) async {
    final path = _layout.workspaceTabAutomationsFile(
      scope.workspaceId,
      scope.launchProfileId,
    );
    final catalog = List<AutomationCatalogEntry>.from(await _readCatalog());
    final index = catalog.indexWhere(
      (e) =>
          e.workspaceId == scope.workspaceId &&
          e.launchProfileId == scope.launchProfileId,
    );
    final entry = AutomationCatalogEntry(
      workspaceId: scope.workspaceId,
      launchProfileId: scope.launchProfileId,
      path: path,
      updatedAtMs: updatedAtMs,
    );
    if (index >= 0) {
      catalog[index] = entry;
    } else {
      catalog.add(entry);
    }
    await _writeCatalog(catalog);
  }
}
