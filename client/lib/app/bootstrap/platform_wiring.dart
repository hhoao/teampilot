import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../config/github_oauth_config.dart';
import '../../cubits/github_account_cubit.dart';
import '../../cubits/remote_download_catalog_cubit.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../services/app/app_update_service.dart';
import '../../services/file_tree_import/workspace_import_service.dart';
import '../../services/github/github_credentials_store.dart';
import '../../services/github/github_device_flow_auth.dart';
import '../../services/hub_publish/http_github_api_client.dart';
import '../../services/remote_download/remote_download_http.dart';
import '../../services/remote_download/remote_download_resolver.dart';
import '../../services/remote_download/remote_downloader.dart';
import '../../services/storage/device_local_control_plane.dart';
import '../../services/storage/targets_repository.dart';
import '../../services/termux/termux_config.dart';
import '../../services/termux/termux_config_store.dart';
import '../../services/vault/credential_capture.dart';
import '../../services/vault/vault_service.dart';
import '../../services/vault/vault_unlock_gate.dart';

/// The device-local platform services the shell holds for the app's lifetime:
/// GitHub credentials + account, the target and termux config stores, the
/// remote-download catalog/update stack, and the workspace import service.
typedef PlatformWiring = ({
  GithubCredentialsStore githubCredentials,
  GithubAccountCubit githubAccountCubit,
  TargetsRepository targetsRepo,
  TermuxConfigStore termuxConfigStore,
  RemoteDownloadCatalogCubit remoteDownloadCatalogCubit,
  RemoteDownloader remoteDownloader,
  AppUpdateService appUpdateService,
  WorkspaceImportService workspaceImportService,
  TermuxConfig? termuxConfigCache,
});

/// Builds the platform services that do not depend on the home plane.
///
/// The download catalog loads fire-and-forget at its original position, so
/// startup never waits on it. [termuxConfigCache] is only the initial load:
/// the shell owns the mutable cache and remains its sole writer.
Future<PlatformWiring> wirePlatformServices({
  required String nativeAppDataPath,
  required VaultService vaultService,
  required VaultCredentialCapture vaultCredentialCapture,
  required VaultUnlockGate vaultUnlockGate,
}) async {
  final githubCredentialsStore = GithubCredentialsStore(
    kv: const FlutterSecureKeyValueStore(),
    vault: vaultService,
    vaultCapture: vaultCredentialCapture,
    ensureVaultUnlocked: vaultUnlockGate.ensureUnlocked,
  );
  final githubDeviceFlow = githubDeviceFlowAvailable
      ? GithubDeviceFlowAuth(clientId: githubOauthClientId)
      : null;
  final githubAccountCubit = GithubAccountCubit(
    store: githubCredentialsStore,
    deviceFlow: githubDeviceFlow,
    openUrl: (uri) async {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw StateError('Could not launch $uri');
    },
    fetchLogin: (token) async {
      final user = await HttpGithubApiClient().getAuthenticatedUser(
        token: token,
      );
      return user.login;
    },
    deviceFlowAvailable: githubDeviceFlowAvailable,
  );

  // P1: targets.json is a pure target catalog (no default/migrate); the home
  // target authority is the device-local homeTargetStore read above. The
  // registry is used by the picker UI to list selectable targets.
  final targetsRepo = deviceLocalTargetsRepository(nativeAppDataPath);
  final termuxConfigStore = deviceLocalTermuxConfigStore(nativeAppDataPath);
  final remoteDownloadSettingsStore = deviceLocalRemoteDownloadSettingsStore(
    nativeAppDataPath,
  );
  final remoteDownloadCatalogCubit = RemoteDownloadCatalogCubit(
    store: remoteDownloadSettingsStore,
  );
  unawaited(remoteDownloadCatalogCubit.load());
  final appUpdateResolver = RemoteDownloadResolver.withProvider(
    () => remoteDownloadCatalogCubit.state.catalog,
  );
  final appUpdateHttpClient = http.Client();
  final remoteDownloader = RemoteDownloader(
    client: appUpdateHttpClient,
    resolver: appUpdateResolver,
  );
  final appUpdateService = AppUpdateService(
    httpClient: appUpdateHttpClient,
    resolver: appUpdateResolver,
    downloadHttp: RemoteDownloadHttp(
      client: appUpdateHttpClient,
      resolver: appUpdateResolver,
    ),
    downloader: remoteDownloader,
  );
  final workspaceImportService = WorkspaceImportService();
  final termuxConfigCache = await termuxConfigStore.load();

  return (
    githubCredentials: githubCredentialsStore,
    githubAccountCubit: githubAccountCubit,
    targetsRepo: targetsRepo,
    termuxConfigStore: termuxConfigStore,
    remoteDownloadCatalogCubit: remoteDownloadCatalogCubit,
    remoteDownloader: remoteDownloader,
    appUpdateService: appUpdateService,
    workspaceImportService: workspaceImportService,
    termuxConfigCache: termuxConfigCache,
  );
}
