import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/hook_definition.dart';
import '../services/hook/hook_repository.dart';

class HookLibraryState extends Equatable {
  const HookLibraryState({
    this.loading = false,
    this.definitions = const [],
    this.errorMessage,
  });

  final bool loading;
  final List<HookDefinition> definitions;
  final String? errorMessage;

  @override
  List<Object?> get props => [loading, definitions, errorMessage];
}

class HookCubit extends Cubit<HookLibraryState> {
  HookCubit({required HookRepository repository})
    : _repository = repository,
      super(const HookLibraryState());

  final HookRepository _repository;

  Future<void> load() async {
    emit(const HookLibraryState(loading: true));
    try {
      final definitions = await _repository.loadAll();
      emit(HookLibraryState(definitions: definitions));
    } on Object catch (e) {
      emit(HookLibraryState(errorMessage: e.toString()));
    }
  }

  Future<bool> upsert(
    HookDefinition definition, {
    Map<String, String> scripts = const {},
  }) async {
    try {
      await _repository.save(definition);
      for (final entry in scripts.entries) {
        await _repository.writeScript(definition.id, entry.key, entry.value);
      }
      await load();
      return true;
    } on Object catch (e) {
      emit(HookLibraryState(errorMessage: e.toString()));
      return false;
    }
  }

  Future<bool> remove(String id) async {
    try {
      await _repository.delete(id);
      await load();
      return true;
    } on Object catch (e) {
      emit(HookLibraryState(errorMessage: e.toString()));
      return false;
    }
  }
}
