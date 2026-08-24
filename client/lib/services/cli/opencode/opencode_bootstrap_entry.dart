import '../registry/cli_bootstrap.dart';
import 'provider/opencode_models_service.dart';

final class OpencodeBootstrapEntry implements CliBootstrapEntry {
  const OpencodeBootstrapEntry({this.modelsService});

  final OpencodeModelsService? modelsService;
}
