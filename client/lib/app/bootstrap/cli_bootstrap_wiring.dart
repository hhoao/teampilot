import '../../cubits/app_provider_cubit.dart';
import '../../cubits/session_preferences_cubit.dart';
import '../../models/app_provider_config.dart';
import '../../services/cli/antigravity/antigravity_bootstrap_entry.dart';
import '../../services/cli/antigravity/capabilities/acp_adapter_installer.dart';
import '../../services/cli/claude/claude_bootstrap_entry.dart';
import '../../services/cli/claude/provider/claude_provider_credentials_service.dart';
import '../../services/cli/codex/codex_bootstrap_entry.dart';
import '../../services/cli/codex/provider/codex_provider_credentials_service.dart';
import '../../services/cli/cursor/cursor_bootstrap_entry.dart';
import '../../services/cli/cursor/provider/cursor_agent_models_service.dart';
import '../../services/cli/cursor/provider/cursor_provider_credentials_service.dart';
import '../../services/cli/gemini/gemini_bootstrap_entry.dart';
import '../../services/cli/grok/grok_bootstrap_entry.dart';
import '../../services/cli/opencode/opencode_bootstrap_entry.dart';
import '../../services/cli/opencode/provider/opencode_models_service.dart';
import '../../services/cli/registry/cli_bootstrap.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/cli/registry/installer/binary_archive_installer.dart';
import '../../services/host/host_one_shot_runner_for_context.dart';
import '../../services/host/host_process_starter_for_context.dart';
import '../../services/provider/api_model_catalog_service.dart';
import '../../services/provider/provider_credential_host_runner.dart';
import '../../services/remote_download/remote_downloader.dart';
import '../../services/storage/home_storage.dart';

/// Registers every CLI's bootstrap entry (credentials services, ACP auth
/// sources, model catalogs, installers) on [cliToolRegistry] against the live
/// [homeStorage] plane, and keeps the cached ACP credential sources current by
/// refreshing them whenever [appProviderCubit] publishes.
void wireCliBootstrap({
  required CliToolRegistry cliToolRegistry,
  required HomeStorage homeStorage,
  required AppProviderCubit appProviderCubit,
  required SessionPreferencesCubit sessionPreferencesCubit,
  required RemoteDownloader remoteDownloader,
  required Future<void> Function(Uri uri) openCredentialLoginUrl,
}) {
  void onCredentialLoginHint(CredentialLoginProgress progress) {
    appProviderCubit.reportCredentialLoginProgress(progress);
  }

  final credentialHostRunner = ProviderCredentialHostRunner(
    oneShot: () => hostOneShotRunnerForContext(homeStorage.context),
    streaming: () => hostProcessStarterForContext(homeStorage.context),
    openUrl: openCredentialLoginUrl,
    onLoginHint: onCredentialLoginHint,
  );

  final claudeCredentialsService = ClaudeProviderCredentialsService(
    storage: homeStorage,
    fs: homeStorage.fs,
    basePath: homeStorage.paths.basePath,
    resolveClaudeExecutable: () =>
        sessionPreferencesCubit.resolveExecutable(CliTool.claude),
    resolveHomeDirectory: () => homeStorage.home,
    hostRunner: credentialHostRunner,
  );
  final cursorCredentialsService = CursorProviderCredentialsService(
    storage: homeStorage,
    fs: homeStorage.fs,
    basePath: homeStorage.paths.basePath,
    resolveCursorExecutable: () =>
        sessionPreferencesCubit.resolveExecutable(CliTool.cursor),
    hostRunner: credentialHostRunner,
  );
  final codexCredentialsService = CodexProviderCredentialsService(
    storage: homeStorage,
    fs: homeStorage.fs,
    basePath: homeStorage.paths.basePath,
    resolveCodexExecutable: () =>
        sessionPreferencesCubit.resolveExecutable(CliTool.codex),
    hostRunner: credentialHostRunner,
  );
  final opencodeModelsService = OpencodeModelsService(storage: homeStorage);

  // Cached Gemini API key for the ACP agent env (refreshed from provider
  // rows; the ACP credential source is a sync closure).
  String? cachedGeminiApiKey;
  // Cached xAI API key for the ACP/headless env; provider-bound keys are
  // injected per seat, so this is only the app-wide fallback.
  String? cachedGrokApiKey;
  // Cached Claude provider row matching the CLI's selected official-vs-key
  // id for the sync ACP auth source; refreshed alongside the Gemini key.
  AppProviderConfig? cachedClaudeProvider;
  // Cached Codex provider row matching the CLI's selected official-vs-key
  // id for the sync ACP auth source; refreshed alongside Claude / Gemini.
  AppProviderConfig? cachedCodexProvider;

  cliToolRegistry.configure(
    CliBootstrap({
      CliTool.claude: ClaudeBootstrapEntry(
        credentialsService: claudeCredentialsService,
        acpAuthSource: () => claudeAcpAuthForProvider(
          cachedClaudeProvider,
          claudeCredentialsService,
        ),
        modelsService: ApiModelCatalogService(
          storage: homeStorage,
          protocol: ApiModelCatalogProtocol.anthropic,
          cacheDirectory: 'claude_models',
        ),
      ),
      CliTool.cursor: CursorBootstrapEntry(
        credentialsService: cursorCredentialsService,
        agentModelsService: CursorAgentModelsService(storage: homeStorage),
      ),
      CliTool.codex: CodexBootstrapEntry(
        credentialsService: codexCredentialsService,
        acpAuthSource: () => codexAcpAuthForProvider(cachedCodexProvider),
        codexPathSource: () =>
            sessionPreferencesCubit.resolveExecutable(CliTool.codex),
        modelsService: ApiModelCatalogService(
          storage: homeStorage,
          protocol: ApiModelCatalogProtocol.openAi,
          cacheDirectory: 'codex_models',
        ),
      ),
      CliTool.opencode: OpencodeBootstrapEntry(
        modelsService: opencodeModelsService,
      ),
      CliTool.gemini: GeminiBootstrapEntry(
        credentialSource: () => cachedGeminiApiKey,
      ),
      CliTool.grok: GrokBootstrapEntry(
        credentialSource: () => cachedGrokApiKey,
      ),
      CliTool.antigravity: AntigravityBootstrapEntry(
        storage: homeStorage,
        acpInstaller: AntigravityAcpAdapterInstaller(
          storage: homeStorage,
          binary: BinaryArchiveInstaller(
            fs: homeStorage.fs,
            fetch: (uri, {expectedSha256, onProgress, isCancelled}) =>
                remoteDownloader.fetch(
                  uri,
                  destFileName: 'antigravity-acp.zip',
                  expectedSha256: expectedSha256,
                  onProgress: onProgress,
                  isCancelled: isCancelled,
                ),
          ),
        ),
      ),
    }, storage: homeStorage),
  );
  // Keep the cached Gemini API key current: the credential source must be
  // sync (AcpCredentialSource), but provider rows load asynchronously.
  var geminiCredentialRefreshInFlight = false;
  void refreshGeminiCredential() {
    if (geminiCredentialRefreshInFlight) return;
    geminiCredentialRefreshInFlight = true;
    appProviderCubit
        .loadProvidersFor(CliTool.gemini)
        .then((providers) {
          final key = providers
              .where((p) => p.id == 'google')
              .map((p) => p.apiKey.trim())
              .firstWhere((k) => k.isNotEmpty, orElse: () => '')
              .trim();
          cachedGeminiApiKey = key.isEmpty ? null : key;
        })
        .catchError((Object _) {})
        .whenComplete(() => geminiCredentialRefreshInFlight = false);
  }

  var grokCredentialRefreshInFlight = false;
  void refreshGrokCredential() {
    if (grokCredentialRefreshInFlight) return;
    grokCredentialRefreshInFlight = true;
    appProviderCubit
        .loadProvidersFor(CliTool.grok)
        .then((providers) {
          final key = providers
              .map((p) => p.apiKey.trim())
              .firstWhere((k) => k.isNotEmpty, orElse: () => '')
              .trim();
          cachedGrokApiKey = key.isEmpty ? null : key;
        })
        .catchError((Object _) {})
        .whenComplete(() => grokCredentialRefreshInFlight = false);
  }

  var claudeProviderRefreshInFlight = false;
  void refreshClaudeProvider() {
    if (claudeProviderRefreshInFlight) return;
    claudeProviderRefreshInFlight = true;
    appProviderCubit
        .loadProvidersFor(CliTool.claude)
        .then((providers) {
          cachedClaudeProvider = pickClaudeAcpProvider(
            providers: providers,
            selectedId: appProviderCubit
                .state
                .selectedProviderIdByCli[CliTool.claude],
          );
        })
        .catchError((Object _) {})
        .whenComplete(() => claudeProviderRefreshInFlight = false);
  }

  var codexProviderRefreshInFlight = false;
  void refreshCodexProvider() {
    if (codexProviderRefreshInFlight) return;
    codexProviderRefreshInFlight = true;
    appProviderCubit
        .loadProvidersFor(CliTool.codex)
        .then((providers) {
          cachedCodexProvider = pickCodexAcpProvider(
            providers: providers,
            selectedId:
                appProviderCubit.state.selectedProviderIdByCli[CliTool.codex],
          );
        })
        .catchError((Object _) {})
        .whenComplete(() => codexProviderRefreshInFlight = false);
  }

  refreshClaudeProvider();
  refreshCodexProvider();
  refreshGeminiCredential();
  refreshGrokCredential();
  // Self-managing: when appProviderCubit closes (shell teardown), the
  // broadcast stream's onDone fires and nothing further is refreshed.
  appProviderCubit.stream.listen((_) {
    refreshClaudeProvider();
    refreshCodexProvider();
    refreshGeminiCredential();
    refreshGrokCredential();
  }, onDone: () {});
}
