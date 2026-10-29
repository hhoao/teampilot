import '../../storage/home_storage.dart';
import '../registry/cli_bootstrap.dart';
import 'capabilities/acp_adapter_installer.dart';

final class AntigravityBootstrapEntry implements CliBootstrapEntry {
  const AntigravityBootstrapEntry({
    required this.storage,
    required this.acpInstaller,
  });

  final HomeStorage storage;
  final AntigravityAcpAdapterInstaller acpInstaller;
}
