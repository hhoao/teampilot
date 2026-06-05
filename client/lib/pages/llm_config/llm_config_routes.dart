import '../../models/app_provider_config.dart';


// LLM 配置页统一留白（8dp 网格）。

String llmCliRoute(CliTool cli) => '/providers/${cli.value}';

String llmProviderAddRoute(CliTool cli) =>
    '${llmCliRoute(cli)}/provider/add';

String llmProviderConfigRoute(CliTool cli, String providerName) =>
    '${llmCliRoute(cli)}/provider/${Uri.encodeComponent(providerName)}';

String llmProviderEditRoute(CliTool cli, String providerName) =>
    '${llmProviderConfigRoute(cli, providerName)}/edit';

String llmProviderModelsRoute(CliTool cli, String providerName) =>
    '${llmProviderConfigRoute(cli, providerName)}/models';

const double kLlmInsetH = 16;
const double kLlmInsetHSm = 12;
const double kLlmSectionGap = 12;
const double kLlmFieldGap = 8;
