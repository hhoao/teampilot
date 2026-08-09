import 'dart:convert';

import '../models/automation.dart';
import '../services/automation/automation_launch_session_binding.dart';
import '../services/io/filesystem.dart';
import '../services/storage/workspace_layout.dart';
import 'package:logger/logger.dart';
import '../utils/logging/logger.dart';

class _WorkspaceAutomationStore {
  const _WorkspaceAutomationStore({required this.automations, required this.runs});

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
  }) : _fs = fs,
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
        .where(
          (a) =>
              a.sessionId == trimmedSession ||
              (a.isLaunchPrompt && a.reuseSession && a.sessionId == trimmedSession),
        )
        .toList(growable: false);
  }

  Future<List<Automation>> listAll() async {
    final workspacesDir = _layout.workspacesDir;
    try {
      final stat = await _fs.stat(workspacesDir);
      if (!stat.isDirectory) return const [];
    } on Object {
      return const [];
    }

    final entries = await _fs.listDir(workspacesDir);
    final all = <Automation>[];
    for (final entry in entries) {
      if (!entry.isDirectory) continue;
      final workspaceId = entry.name;
      if (workspaceId.trim().isEmpty) continue;
      all.addAll(await listForWorkspace(workspaceId));
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
    final workspaceId = automation.workspaceId;
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
  }

  Future<void> appendRun(String workspaceId, AutomationRun run) async {
    await upsertRun(workspaceId, run);
  }

  Future<void> disableForSession(
    String workspaceId,
    String sessionId,
  ) async {
    final trimmedSession = sessionId.trim();
    final store = await _readStore(workspaceId);
    var changed = false;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final automations = store.automations
        .map((a) {
          if (a.sessionId != trimmedSession) return a;
          final next = AutomationLaunchSessionBinding.onBoundSessionRemoved(a);
          if (next == a) return a;
          changed = true;
          return next.copyWith(updatedAtMs: nowMs);
        })
        .toList(growable: false);
    if (!changed) return;
    await _writeStore(workspaceId, store.copyWith(automations: automations));
  }

  Future<void> removeWorkspace(String workspaceId) async {
    final trimmed = workspaceId.trim();
    if (trimmed.isEmpty) return;
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
    await _fs.ensureDir(_layout.workspaceAutomationsDir(workspaceId));
    final encoded = jsonEncode(store.toJson());
    await _fs.atomicWrite(path, encoded);
  }
}
