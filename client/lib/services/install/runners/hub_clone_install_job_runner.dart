import 'package:meta/meta.dart';

import '../../../models/install_job/install_job_cancelled_exception.dart';
import '../../../models/install_job/install_job_context.dart';
import '../../../models/install_job/install_job_key.dart';
import '../../../models/install_job/install_job_spec.dart';
import '../../team/team_clone_service.dart';
import '../install_job_runner.dart';

typedef HubCloneInvoker<T> =
    Future<T> Function(
      String hubKey,
      void Function(CloneProgress progress) onProgress,
      bool Function() isCancelled,
    );

enum HubCloneTargetKind { team, expert }

({HubCloneTargetKind kind, String hubKey}) parseHubCloneTarget(String target) {
  const prefixes = {
    'team:': HubCloneTargetKind.team,
    'expert:': HubCloneTargetKind.expert,
  };
  for (final entry in prefixes.entries) {
    if (target.startsWith(entry.key)) {
      final hubKey = target.substring(entry.key.length).trim();
      if (hubKey.isEmpty) {
        throw StateError('Hub clone target key is empty: $target');
      }
      return (kind: entry.value, hubKey: hubKey);
    }
  }
  throw StateError('Unknown hub clone target prefix: $target');
}

void reportHubCloneProgress(InstallJobContext ctx, CloneProgress progress) {
  if (progress.message.isNotEmpty) {
    ctx.reportPhase(progress.message);
  }
  if (progress.total > 0) {
    ctx.reportItems(completed: progress.done, total: progress.total);
  }
}

final class HubCloneInstallJobRunner implements InstallJobRunner {
  HubCloneInstallJobRunner({
    HubCloneInvoker? cloneTeam,
    HubCloneInvoker? cloneExpert,
    @visibleForTesting HubCloneInvoker? runOverride,
  }) : _cloneTeam = cloneTeam,
       _cloneExpert = cloneExpert,
       _runOverride = runOverride;

  final HubCloneInvoker? _cloneTeam;
  final HubCloneInvoker? _cloneExpert;
  final HubCloneInvoker? _runOverride;

  @override
  InstallJobKind get kind => InstallJobKind.hubClone;

  @override
  bool supports(InstallJobKey key) {
    if (key.kind != kind) return false;
    try {
      parseHubCloneTarget(key.target);
      return true;
    } on StateError {
      return false;
    }
  }

  @override
  Future<T> run<T>(InstallJobSpec<T> spec, InstallJobContext ctx) async {
    if (!supports(spec.key)) {
      throw StateError('Unsupported hub clone target: ${spec.key.target}');
    }
    if (ctx.isCancelled) {
      throw InstallJobCancelledException(spec.key);
    }

    final parsed = parseHubCloneTarget(spec.key.target);
    void onProgress(CloneProgress progress) =>
        reportHubCloneProgress(ctx, progress);

    final override = _runOverride;
    if (override != null) {
      final result = await override(
        parsed.hubKey,
        onProgress,
        () => ctx.isCancelled,
      );
      if (ctx.isCancelled) {
        throw InstallJobCancelledException(spec.key);
      }
      return result as T;
    }

    final invoker = _invokerFor(parsed.kind);
    if (invoker != null) {
      final result = await invoker(
        parsed.hubKey,
        onProgress,
        () => ctx.isCancelled,
      );
      if (ctx.isCancelled) {
        throw InstallJobCancelledException(spec.key);
      }
      return result as T;
    }

    final result = await spec.run(ctx);
    if (ctx.isCancelled) {
      throw InstallJobCancelledException(spec.key);
    }
    return result;
  }

  HubCloneInvoker? _invokerFor(HubCloneTargetKind kind) => switch (kind) {
    HubCloneTargetKind.team => _cloneTeam,
    HubCloneTargetKind.expert => _cloneExpert,
  };
}
