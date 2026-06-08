import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/ai_feature_setting.dart';
import '../../models/app_provider_config.dart';
import '../../repositories/app_provider_repository.dart';
import '../../utils/logger.dart';
import '../cli/cli_tool_locator.dart';
import '../cli/registry/capabilities/cli_effort_capability.dart';
import '../cli/registry/capabilities/headless_provision_capability.dart';
import '../cli/registry/capabilities/headless_run_capability.dart';
import '../cli/registry/cli_tool_registry.dart';

/// Thrown when a headless AI call cannot run or fails.
class HeadlessAiException implements Exception {
  HeadlessAiException(this.message);
  final String message;
  @override
  String toString() => 'HeadlessAiException: $message';
}

class HeadlessAiResult {
  const HeadlessAiResult({
    required this.text,
    required this.rawStdout,
    required this.exitCode,
  });
  final String text;
  final String rawStdout;
  final int exitCode;
}

typedef HeadlessProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
      String? workingDirectory,
      Duration? timeout,
    });

typedef HeadlessProviderResolver =
    Future<AppProviderConfig?> Function(CliTool cli, String id);

typedef HeadlessExecutableResolver = Future<String?> Function(String name);

/// Runs the CLI via [Process.start] so a [timeout] can actually **kill** the
/// child process (a bare `Process.run().timeout()` only abandons the future and
/// leaves an orphaned, credential-bearing process running). Throws
/// [TimeoutException] after killing the child when [timeout] elapses.
Future<ProcessResult> headlessDefaultProcessRun(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
  String? workingDirectory,
  Duration? timeout,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    environment: environment,
    includeParentEnvironment: true,
    workingDirectory: workingDirectory,
  );
  final stdoutFuture = process.stdout.transform(systemEncoding.decoder).join();
  final stderrFuture = process.stderr.transform(systemEncoding.decoder).join();

  var timedOut = false;
  Timer? killTimer;
  if (timeout != null) {
    killTimer = Timer(timeout, () {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
    });
  }

  final exitCode = await process.exitCode;
  killTimer?.cancel();
  final out = await stdoutFuture;
  final err = await stderrFuture;

  if (timedOut) {
    throw TimeoutException('Headless CLI process timed out', timeout);
  }
  return ProcessResult(process.pid, exitCode, out, err);
}

/// Runs a single one-shot CLI call for AI features. Reuses the CLI registry's
/// [HeadlessRunCapability] per tool; all IO is injectable for tests.
class HeadlessAiService {
  HeadlessAiService({
    CliToolRegistry? registry,
    HeadlessProcessRunner run = headlessDefaultProcessRun,
    HeadlessProviderResolver? resolveProvider,
    HeadlessExecutableResolver? resolveExecutable,
    HeadlessProvisionCapability? Function(CliTool)? resolveProvisionCapability,
    Future<Directory> Function()? tempDirFactory,
  }) : _registry = registry ?? CliToolRegistry.builtIn(),
       _run = run,
       _resolveProvider = resolveProvider ?? AppProviderRepository().findById,
       _resolveExecutable =
           resolveExecutable ?? ((name) => CliToolLocator(name).locate()),
       _resolveProvisionCapability = resolveProvisionCapability,
       _tempDirFactory =
           tempDirFactory ??
           (() => Directory.systemTemp.createTemp('tp_headless_'));

  final CliToolRegistry _registry;
  final HeadlessProcessRunner _run;
  final HeadlessProviderResolver _resolveProvider;
  final HeadlessExecutableResolver _resolveExecutable;

  /// Test seam to override (or disable, by returning null) per-CLI provisioning.
  /// Defaults to the registry's [HeadlessProvisionCapability] for the CLI.
  final HeadlessProvisionCapability? Function(CliTool)? _resolveProvisionCapability;
  final Future<Directory> Function() _tempDirFactory;

  Future<HeadlessAiResult> run({
    required AiFeatureSetting setting,
    required String prompt,
    bool expectJson = false,
    String? workingDirectory,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final cli = setting.cli;
    final cap = _registry.capability<HeadlessRunCapability>(cli);
    if (cap == null || !cap.isSupported) {
      throw HeadlessAiException(
        'Headless mode is not supported for ${cli.value}.',
      );
    }

    final provider = await _resolveProvider(cli, setting.providerId);
    final model = setting.model.trim().isNotEmpty
        ? setting.model.trim()
        : (provider?.defaultModel.trim() ?? '');
    final effort = _resolveEffort(cli, model, provider, setting.effort);

    final dir = await _tempDirFactory();
    try {
      final ctx = HeadlessRunContext(
        prompt: prompt,
        model: model,
        effort: effort,
        configDir: dir.path,
        workingDirectory: workingDirectory,
        expectJson: expectJson,
      );

      final provisionCap = _resolveProvisionCapability != null
          ? _resolveProvisionCapability(cli)
          : _registry.capability<HeadlessProvisionCapability>(cli);
      final provision = provisionCap == null
          ? const HeadlessProvisionResult()
          : await provisionCap.provision(
              HeadlessProvisionContext(
                provider: provider,
                providerId: setting.providerId,
                model: model,
                effort: effort,
                configDir: dir.path,
                workingDirectory: workingDirectory,
              ),
            );
      if (!provision.credentialsReady) {
        throw HeadlessAiException(_credentialsMessage(cli, provision.warnings));
      }

      for (final file in cap.configFiles(ctx)) {
        final out = File(p.join(dir.path, file.relativePath));
        await out.parent.create(recursive: true);
        await out.writeAsString(file.contents);
      }

      final inv = cap.buildInvocation(ctx);
      final environment = <String, String>{
        ...inv.environment,
        ...provision.extraEnvironment,
      };
      // Log only env keys — values carry secrets (e.g. OPENCODE_AUTH_CONTENT).
      appLogger.d(
        '--------------------------------\n'
        'Starting headless run:\n'
        '--------------------------------\n'
        'Executable: ${inv.executable},\n'
        'Arguments: ${inv.arguments.join(' ')},\n'
        'WorkingDirectory: ${ctx.workingDirectory},\n'
        'Environment keys: ${environment.keys.join(', ')}\n'
        '--------------------------------\n',
      );
      final exe = await _resolveExecutable(inv.executable);
      if (exe == null) {
        throw HeadlessAiException('${inv.executable} not found on PATH.');
      }

      final ProcessResult result;
      try {
        result = await _run(
          exe,
          inv.arguments,
          environment: environment.isEmpty ? null : environment,
          workingDirectory: ctx.workingDirectory,
          timeout: timeout,
        );
      } on TimeoutException {
        throw HeadlessAiException(
          'AI call timed out after ${timeout.inSeconds}s.',
        );
      }

      if (result.exitCode != 0) {
        final err = (result.stderr as String? ?? '').trim();
        final out = (result.stdout as String? ?? '').trim();
        final detail = err.isNotEmpty ? err : out;
        appLogger.d('[Headless] ${cli.value} exit ${result.exitCode}: $detail');
        throw HeadlessAiException(
          detail.isEmpty ? 'AI call failed (${cli.value}).' : detail,
        );
      }

      return HeadlessAiResult(
        text: cap.extractText(result),
        rawStdout: (result.stdout as String? ?? ''),
        exitCode: result.exitCode,
      );
    } finally {
      if (await dir.exists()) {
        try {
          await dir.delete(recursive: true);
        } on FileSystemException {
          // Best-effort cleanup; ignore.
        }
      }
    }
  }

  String _credentialsMessage(CliTool cli, List<String> warnings) {
    if (warnings.contains('claude_credentials_missing') ||
        warnings.contains('codex_credentials_missing') ||
        warnings.contains('opencode_credentials_missing')) {
      return 'Provider credentials are not linked for ${cli.value}. '
          'Open Providers and link or import credentials for this provider.';
    }
    if (warnings.contains('claude_provider_missing') ||
        warnings.contains('codex_provider_missing') ||
        warnings.contains('opencode_provider_missing')) {
      return 'Provider configuration is missing for ${cli.value}.';
    }
    return 'Provider is not ready for headless ${cli.value}.';
  }

  String _resolveEffort(
    CliTool cli,
    String model,
    AppProviderConfig? provider,
    String requested,
  ) {
    final cap = _registry.capability<CliEffortCapability>(cli);
    if (cap == null || !cap.isApplicable(model: model)) return '';
    final r = requested.trim();
    if (r.isNotEmpty) return r;
    return cap.defaultEffort(model: model, provider: provider);
  }
}
