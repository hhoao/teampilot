import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/services/provider_usage/adapters/http_json_mapping_adapter.dart';

ManagedProviderUsageWindow usageWindow({
  String label = 'Usage',
  String? remaining,
  String? total,
  String? used,
  String? unit,
  String? resetsAt,
  String? kind,
}) =>
    ManagedProviderUsageWindow(
      label: label,
      remaining: remaining,
      total: total,
      used: used,
      unit: unit,
      resetsAt: resetsAt,
      kind: kind,
    );

HttpJsonMappingConfig mappingConfig({
  String method = 'GET',
  required String url,
  String? responsePath,
  List<ManagedProviderUsageWindow>? windows,
  HttpJsonCredentialConfig? credential,
  String credentialSource = 'secret',
  Map<String, String> headers = const {},
  Map<String, Object?> body = const {},
}) =>
    HttpJsonMappingConfig(
      method: method,
      url: url,
      responsePath: responsePath,
      windows: windows ?? [usageWindow(remaining: r'$.remaining')],
      credential: credential,
      credentialSource: credentialSource,
      headers: headers,
      body: body,
    );
