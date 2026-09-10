import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../models/app_provider_config.dart';
import '../../../../models/credential_link_result.dart';
import '../../../../models/team_config.dart';
import '../../../storage/app_storage.dart';
import '../../registry/capabilities/headless_capability.dart';
import '../../registry/headless/headless_provision_support.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_headless_launch_context.dart';
import '../../registry/launch/headless_launch_context_adapter.dart';
import '../../registry/launch/user_extra_args_provider.dart';
import '../provider/cursor_auth_artifacts.dart';
import '../provider/cursor_home_layout.dart';
import '../provider/cursor_launch_environment.dart';
import '../provider/cursor_provider_credentials_service.dart';
import '../provider/cursor_provider_settings_resolver.dart';
import 'model_launch.dart';
import 'permission_launch.dart';
import 'session_selection_launch.dart';
import 'workspace_access_launch.dart';

/// Cursor one-shot via `cursor-agent -p`.
///
/// `CURSOR_CONFIG_DIR` only relocates `cli-config.json`/`chats` — auth stays
/// anchored at HOME/APPDATA/XDG (see [CursorHomePlatform]). The temp config dir
/// therefore doubles as an isolated fake `$HOME`: [buildEnvironment] pins every
/// credential anchor inside it via [CursorLaunchEnvironment.forStandalone],
/// and [provision] materializes the selected provider's credentials into it,
/// falling back to the machine's global login exactly like interactive
/// sessions (`_syncGlobalAuthToMember`).
final class CursorHeadlessCapability
    with HeadlessProvisionSupport
    implements HeadlessCapability {
  const CursorHeadlessCapability();

  @override
  bool get isSupported => true;

  @override
  bool get supportsStreaming => false;

  @override
  bool get supportsPromptStdin => true;

  @override
  String get executable => 'cursor-agent';

  /// Isolated `$HOME/.cursor` inside the one-shot temp config dir.
  static String cursorConfigDirFor(String configDir) =>
      p.join(configDir, CursorHomeLayout.cursorDirName);

  @override
  Map<String, String> buildEnvironment(HeadlessLaunchContext context) =>
      CursorLaunchEnvironment.forStandalone(
        homeRoot: context.configDir,
        cursorConfigDir: cursorConfigDirFor(context.configDir),
      );

  @override
  List<HeadlessConfigFile> configFiles(HeadlessRunContext ctx) => const [];

  @override
  Iterable<CliLaunchArgContribution> buildHeadlessLaunchArgs(
    CliHeadlessLaunchContext ctx,
  ) sync* {
    final interactive = interactiveContextForHeadless(ctx, CliTool.cursor);
    yield CliLaunchArgContribution(
      key: 'cursor-headless-command',
      phase: LaunchArgPhase.command,
      args: ['-p'],
    );
    yield* const CursorSessionSelectionLaunch().buildLaunchArgs(interactive);
    yield* const CursorWorkspaceAccessLaunch().buildLaunchArgs(interactive);
    yield* const CursorModelLaunch().buildLaunchArgs(interactive);
    yield* const CursorPermissionLaunch().buildLaunchArgs(interactive);
    // In stdin mode the piped content is the prompt; no positional prompt.
    if (!ctx.promptViaStdin) {
      yield CliLaunchArgContribution(
        key: 'cursor-headless-prompt',
        phase: LaunchArgPhase.prompt,
        args: [ctx.prompt],
      );
    }
    yield* const UserExtraArgsProvider().buildLaunchArgs(interactive);
  }

  @override
  String extractText(ProcessResult result) =>
      (result.stdout as String? ?? '').trim();

  @override
  String? streamResultText(String line) => null;

  @override
  Future<HeadlessProvisionResult> provision(
    HeadlessProvisionContext ctx,
  ) async {
    final fs = this.fs;
    final layout = CursorHomeLayout(pathContext: fs.pathContext);
    final home = ctx.configDir;
    await fs.ensureDir(layout.cursorDir(home));
    await fs.ensureDir(layout.authDir(home));

    final provider = await _resolveProvider(ctx);
    if (provider != null) {
      if (!provider.isOfficial) return const HeadlessProvisionResult();
      final credentials = CursorProviderCredentialsService(
        fs: fs,
        basePath: basePath,
      );
      final link = await credentials.syncAuthToMemberHome(provider.id, home);
      if (link == CredentialLinkResult.missing) {
        return const HeadlessProvisionResult(
          warnings: ['cursor_credentials_missing'],
          credentialsReady: false,
        );
      }
      return const HeadlessProvisionResult();
    }

    // No configured provider: reuse the machine's global login, mirroring the
    // interactive session auth fallback.
    final globalAuth = await _readGlobalAuth(layout);
    if (globalAuth == null) {
      return const HeadlessProvisionResult(
        warnings: ['cursor_credentials_missing'],
        credentialsReady: false,
      );
    }
    await fs.atomicWrite(layout.authJson(home), globalAuth);
    return const HeadlessProvisionResult();
  }

  Future<AppProviderConfig?> _resolveProvider(
    HeadlessProvisionContext ctx,
  ) async {
    final direct = ctx.provider;
    if (direct != null) return direct;

    final resolver = CursorProviderSettingsResolver(
      basePath: basePath,
      repository: repository,
    );
    final byId = await resolver.findById(ctx.providerId);
    if (byId != null) return byId;

    final providers = await repository.loadProviders(CliTool.cursor);
    if (providers.length == 1) return providers.first;
    return null;
  }

  Future<String?> _readGlobalAuth(CursorHomeLayout layout) async {
    final home = AppStorage.home;
    // Scoped to the storage home so the fallback stays deterministic (an
    // env-APPDATA candidate outside the home is a different machine's login).
    final pathContext = fs.pathContext;
    for (final candidate in layout.globalAuthJsonCandidates(home)) {
      if (!pathContext.isWithin(home, candidate)) continue;
      final content = await fs.readString(candidate);
      if (content != null &&
          CursorAuthArtifacts.authJsonIndicatesLoggedIn(content)) {
        return content;
      }
    }
    return null;
  }
}
