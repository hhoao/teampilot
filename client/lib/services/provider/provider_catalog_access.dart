import '../../repositories/app_provider_repository.dart';
import '../cli/registry/config_profile/config_profile_context.dart';

AppProviderRepository providerCatalogRepository(ConfigProfilePaths catalog) {
  return AppProviderRepository(basePath: catalog.basePath, fs: catalog.fs);
}

bool configProfileCrossMachine(
  ConfigProfilePaths catalog,
  ConfigProfilePaths work,
) =>
    catalog.basePath != work.basePath;
