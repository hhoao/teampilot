import 'package:meta/meta.dart';

import '../../../models/install_job/install_job_cancelled_exception.dart';
import '../../../models/install_job/install_job_context.dart';
import '../../../models/install_job/install_job_key.dart';
import '../../../models/install_job/install_job_spec.dart';
import '../install_job_runner.dart';

typedef PackAcquireStepReporter = void Function({
  String? subtitle,
  int? completedSteps,
  int? totalSteps,
});

typedef PackAcquireInvoker<T> =
    Future<T> Function(
      String packId,
      PackAcquireStepReporter onStep,
      bool Function() isCancelled,
    );

enum PackAcquireTargetKind { skill, plugin, extension }

({PackAcquireTargetKind kind, String id}) parsePackAcquireTarget(
  String target,
) {
  const prefixes = {
    'skill:': PackAcquireTargetKind.skill,
    'plugin:': PackAcquireTargetKind.plugin,
    'extension:': PackAcquireTargetKind.extension,
  };
  for (final entry in prefixes.entries) {
    if (target.startsWith(entry.key)) {
      final id = target.substring(entry.key.length).trim();
      if (id.isEmpty) {
        throw StateError('Pack acquire target id is empty: $target');
      }
      return (kind: entry.value, id: id);
    }
  }
  throw StateError('Unknown pack acquire target prefix: $target');
}

PackAcquireStepReporter packAcquireStepReporter(InstallJobContext ctx) {
  return ({String? subtitle, int? completedSteps, int? totalSteps}) {
    if (subtitle != null) {
      ctx.reportPhase(subtitle);
    }
    final hasTotal = totalSteps != null && totalSteps > 0;
    if (hasTotal && completedSteps != null) {
      ctx.reportItems(completed: completedSteps, total: totalSteps);
    }
  };
}

final class PackAcquireInstallJobRunner implements InstallJobRunner {
  PackAcquireInstallJobRunner({
    PackAcquireInvoker? installSkill,
    PackAcquireInvoker? installPlugin,
    PackAcquireInvoker? installExtension,
    @visibleForTesting PackAcquireInvoker? runOverride,
  }) : _installSkill = installSkill,
       _installPlugin = installPlugin,
       _installExtension = installExtension,
       _runOverride = runOverride;

  final PackAcquireInvoker? _installSkill;
  final PackAcquireInvoker? _installPlugin;
  final PackAcquireInvoker? _installExtension;
  final PackAcquireInvoker? _runOverride;

  @override
  InstallJobKind get kind => InstallJobKind.packAcquire;

  @override
  bool supports(InstallJobKey key) {
    if (key.kind != kind) return false;
    try {
      parsePackAcquireTarget(key.target);
      return true;
    } on StateError {
      return false;
    }
  }

  @override
  Future<T> run<T>(InstallJobSpec<T> spec, InstallJobContext ctx) async {
    if (!supports(spec.key)) {
      throw StateError('Unsupported pack acquire target: ${spec.key.target}');
    }
    if (ctx.isCancelled) {
      throw InstallJobCancelledException(spec.key);
    }

    final parsed = parsePackAcquireTarget(spec.key.target);
    final override = _runOverride;
    if (override != null) {
      final result = await override(
        parsed.id,
        packAcquireStepReporter(ctx),
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
        parsed.id,
        packAcquireStepReporter(ctx),
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

  PackAcquireInvoker? _invokerFor(PackAcquireTargetKind kind) =>
      switch (kind) {
        PackAcquireTargetKind.skill => _installSkill,
        PackAcquireTargetKind.plugin => _installPlugin,
        PackAcquireTargetKind.extension => _installExtension,
      };
}
