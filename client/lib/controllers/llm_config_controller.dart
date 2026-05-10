import 'package:flutter/foundation.dart';

import '../models/llm_config.dart';
import '../repositories/llm_config_repository.dart';

class LlmConfigController extends ChangeNotifier {
  LlmConfigController({
    LlmConfigRepository? repository,
    LlmConfig initialConfig = const LlmConfig(),
  }) : _repository = repository,
       _config = initialConfig,
       _savedConfig = initialConfig,
       _isLoading = false;

  final LlmConfigRepository? _repository;

  late LlmConfig _config;
  late LlmConfig _savedConfig;
  late bool _isLoading;
  String _statusMessage = '';
  String? _selectedProviderName;

  LlmConfig get config => _config;
  bool get isLoading => _isLoading;
  String get statusMessage => _statusMessage;
  String get filePath =>
      _repository?.file.path ?? 'flashshkyai/llm/llm_config.json';
  String? get selectedProviderName {
    if (_selectedProviderName != null &&
        _config.providers.containsKey(_selectedProviderName)) {
      return _selectedProviderName;
    }
    return _config.providers.keys.firstOrNull;
  }

  void selectProvider(String name) {
    if (_selectedProviderName == name) return;
    _selectedProviderName = name;
    notifyListeners();
  }

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    _config = await _repository?.load() ?? const LlmConfig();
    _savedConfig = _config;
    _statusMessage = 'Loaded LLM config.';
    _isLoading = false;
    notifyListeners();
  }

  Future<void> save() async {
    await _repository?.save(_config, previous: _savedConfig);
    _savedConfig = _config;
    _statusMessage = 'Saved LLM config.';
    notifyListeners();
  }

  void addProvider(LlmProviderConfig provider) {
    _config = _config.copyWith(
      providers: {..._config.providers, provider.name: provider},
    );
    _statusMessage = 'Added provider ${provider.name}.';
    notifyListeners();
  }

  void updateProvider(String name, LlmProviderConfig provider) {
    final updated = Map<String, LlmProviderConfig>.from(_config.providers);
    updated[name] = provider;
    _config = _config.copyWith(providers: updated);
    _statusMessage = 'Updated provider $name.';
    notifyListeners();
  }

  void deleteProvider(String name) {
    final updated = Map<String, LlmProviderConfig>.from(_config.providers);
    updated.remove(name);
    _config = _config.copyWith(providers: updated);
    if (_selectedProviderName == name) {
      _selectedProviderName = updated.keys.firstOrNull;
    }
    _statusMessage = 'Deleted provider $name.';
    notifyListeners();
  }

  void addModel(LlmModelConfig model) {
    _config = _config.copyWith(
      models: {..._config.models, model.id: model},
    );
    _statusMessage = 'Added model ${model.name}.';
    notifyListeners();
  }

  void updateModel(String id, LlmModelConfig model) {
    final updated = Map<String, LlmModelConfig>.from(_config.models);
    updated[id] = model;
    _config = _config.copyWith(models: updated);
    _statusMessage = 'Updated model ${model.name}.';
    notifyListeners();
  }

  void deleteModel(String id) {
    final updated = Map<String, LlmModelConfig>.from(_config.models);
    updated.remove(id);
    _config = _config.copyWith(models: updated);
    _statusMessage = 'Deleted model $id.';
    notifyListeners();
  }

  String revealApiKey(String providerName) {
    return _savedConfig.providers[providerName]?.apiKey ?? '';
  }
}
