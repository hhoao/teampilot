import 'dart:convert';

import '../models/automation.dart';
import '../services/io/filesystem.dart';
import '../services/storage/workspace_layout.dart';
import '../utils/logger.dart';

class AutomationCatalogEntry {
  const AutomationCatalogEntry({
    required this.workspaceId,
    required this.path,
    required this.updatedAtMs,
  });

  factory AutomationCatalogEntry.fromJson(Map<String, Object?> json) {
    return AutomationCatalogEntry(
      workspaceId: json['workspaceId'] as String? ?? '',
      path: json['path'] as String? ?? '',
      updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  final String workspaceId;
  final String path;
  final int updatedAtMs;

  Map<String, Object?> toJson() => {
        'workspaceId': workspaceId,
        'path': path,
        'updatedAtMs': updatedAtMs,
      };
}

class _WorkspaceAutomationStore {
  const _WorkspaceAutomationStore({
    required this.automations,
    required this.runs,
  });

  final List<Automation> automations;
  final List<AutomationRun> runs;

  Map<String, Object?> toJson() => {
        'automations': automations.map((a) => a.toJson()).toList(),
        'runs': runs.map((r) => r.toJson()).toList(),
      };

  factory _WorkspaceAutomationStore.fromJson(Map<String, Object?> json) {
    final automationsRaw = json['automations'];
    final runsRaw = json['runs'];
    return _WorkspaceAutomationStore(
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

  _WorkspaceAutomationStore copyWith({
    List<Automation>? automations,
    List<AutomationRun>? runs,
  }) {
    return _WorkspaceAutomationStore(
      automations: automations ?? this.automations,
      runs: runs ?? this.runs,
    );
  }
}

class AutomationRepository {
  AutomationRepository({
    required Filesystem fs,
    required WorkspaceLayout layout,
    this.maxRunsPerWorkspace = 100,
  })  : _fs = fs,
        _layout = layout;

  final Filesystem _fs;
  final WorkspaceLayout _layout;
  final int maxRunsPerWorkspace;

  Future<List<Automation>> listForWorkspace(String workspaceId) async {
    final store = await _readStore(workspaceId);
    return store.automations;
  }

  Future<List<Automation>> listForSession(
    String workspaceId,
    String sessionId,
  ) async {
    final trimmedSession = sessionId.trim();
    final automations = await listForWorkspace(workspaceId);
    return automations
        .where((a) => a.sessionId == trimmedSession)
        .toList(growable: false);
  }

  Future<List<Automation>> listAll() async {
    final catalog = await _readCatalog();
    final all = <Automation>[];
    for (final entry in catalog) {
      all.addAll(await listForWorkspace(entry.workspaceId));
    }
    return all;
  }

  Future<List<AutomationRun>> runsForWorkspace(String workspaceId) async {
    final store = await _readStore(workspaceId);
    return store.runs;
  }

  Future<List<AutomationRun>> runsFor(
    String workspaceId, {
    String? automationId,
  }) async {
    final store = await _readStore(workspaceId);
    final trimmedId = automationId?.trim();
    if (trimmedId == null || trimmedId.isEmpty) {
      return store.runs;
    }
    return store.runs
        .where((r) => r.automationId == trimmedId)
        .toList(growable: false);
  }

  Future<void> upsertRun(String workspaceId, AutomationRun run) async {
    final store = await _readStore(workspaceId);
    final runs = List<AutomationRun>.from(store.runs);
    final index = runs.indexWhere((r) => r.id == run.id);
    if (index >= 0) {
      runs[index] = run;
    } else {
      runs.add(run);
    }
    final trimmed = runs.length > maxRunsPerWorkspace
        ? runs.sublist(runs.length - maxRunsPerWorkspace)
        : runs;
    await _writeStore(workspaceId, store.copyWith(runs: trimmed));
  }

  Future<Automation> upsert(Automation automation) async {
    automation.validate();
    final workspaceId = automation.workspaceId.trim();
    final store = await _readStore(workspaceId);
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
    await _writeStore(workspaceId, store.copyWith(automations: automations));
    await _upsertCatalogEntry(workspaceId, nowMs);
    return next;
  }

  Future<void> delete(String workspaceId, String automationId) async {
    final store = await _readStore(workspaceId);
    final automations = store.automations
        .where((a) => a.id != automationId)
        .toList(growable: false);
    final runs = store.runs
        .where((r) => r.automationId != automationId)
        .toList(growable: false);
    await _writeStore(
      workspaceId,
      store.copyWith(automations: automations, runs: runs),
    );
    await _upsertCatalogEntry(workspaceId, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> appendRun(String workspaceId, AutomationRun run) async {
    await upsertRun(workspaceId, run);
  }

  Future<void> disableForSession(String workspaceId, String sessionId) async {
    final trimmedSession = sessionId.trim();
    final store = await _readStore(workspaceId);
    var changed = false;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final automations = store.automations.map((a) {
      if (a.sessionId != trimmedSession || !a.enabled) return a;
      changed = true;
      return a.copyWith(
        enabled: false,
        clearNextRunAtMs: true,
        updatedAtMs: nowMs,
      );
    }).toList(growable: false);
    if (!changed) return;
    await _writeStore(workspaceId, store.copyWith(automations: automations));
    await _upsertCatalogEntry(workspaceId, nowMs);
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
    final path = _layout.workspaceAutomationsFile(trimmed);
    try {
      final fileStat = await _fs.stat(path);
      if (fileStat.isFile) {
        await _fs.removeRecursive(path);
      }
    } on Object catch (e) {
      appLogger.w('[automations] remove workspace file failed ($trimmed): $e');
    }
  }

  Future<_WorkspaceAutomationStore> _readStore(String workspaceId) async {
    final path = _layout.workspaceAutomationsFile(workspaceId);
    try {
      final raw = await _fs.readString(path);
      if (raw == null || raw.trim().isEmpty) {
        return const _WorkspaceAutomationStore(automations: [], runs: []);
      }
      final decoded = json.decode(raw);
      if (decoded is! Map<String, Object?>) {
        return const _WorkspaceAutomationStore(automations: [], runs: []);
      }
      return _WorkspaceAutomationStore.fromJson(decoded);
    } on Object catch (e) {
      appLogger.w('[automations] read store failed ($workspaceId): $e');
      return const _WorkspaceAutomationStore(automations: [], runs: []);
    }
  }

  Future<void> _writeStore(
    String workspaceId,
    _WorkspaceAutomationStore store,
  ) async {
    final path = _layout.workspaceAutomationsFile(workspaceId);
    await _fs.ensureDir(_layout.workspaceDir(workspaceId));
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
          .where((e) => e.workspaceId.isNotEmpty)
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

  Future<void> _upsertCatalogEntry(String workspaceId, int updatedAtMs) async {
    final path = _layout.workspaceAutomationsFile(workspaceId);
    final catalog = List<AutomationCatalogEntry>.from(await _readCatalog());
    final index = catalog.indexWhere((e) => e.workspaceId == workspaceId);
    final entry = AutomationCatalogEntry(
      workspaceId: workspaceId,
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
