import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/session_preferences.dart';
import '../repositories/session_preferences_repository.dart';

class SessionPreferencesState extends Equatable {
  const SessionPreferencesState({
    this.preferences = const SessionPreferences(),
    this.isLoading = true,
  });

  final SessionPreferences preferences;
  final bool isLoading;

  SessionPreferencesState copyWith({
    SessionPreferences? preferences,
    bool? isLoading,
  }) {
    return SessionPreferencesState(
      preferences: preferences ?? this.preferences,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  List<Object?> get props => [preferences, isLoading];
}

class SessionPreferencesCubit extends Cubit<SessionPreferencesState> {
  SessionPreferencesCubit({
    required SessionPreferencesRepository repository,
    String? locatedExecutable,
  })  : _repository = repository,
        _locatedExecutable = locatedExecutable,
        super(const SessionPreferencesState());

  final SessionPreferencesRepository _repository;
  final String? _locatedExecutable;

  Future<void> load() async {
    emit(state.copyWith(isLoading: true));
    final prefs = await _repository.load();
    emit(state.copyWith(preferences: prefs, isLoading: false));
  }

  Future<void> _save(SessionPreferences preferences) async {
    emit(state.copyWith(preferences: preferences));
    await _repository.save(preferences);
  }

  Future<void> setCliExecutablePath(String value) {
    return _save(state.preferences.copyWith(cliExecutablePath: value.trim()));
  }

  Future<void> setAutoLaunchAllMembersOnConnect(bool value) {
    return _save(
      state.preferences.copyWith(autoLaunchAllMembersOnConnect: value),
    );
  }

  /// Returns the actual executable string to invoke:
  ///   1. user-configured path (if non-empty after trim)
  ///   2. path discovered at startup (if non-null and non-empty)
  ///   3. literal `'flashskyai'` (OS resolves via PATH)
  String resolveExecutable() {
    final user = state.preferences.cliExecutablePath.trim();
    if (user.isNotEmpty) return user;
    final located = _locatedExecutable;
    if (located != null && located.isNotEmpty) return located;
    return 'flashskyai';
  }
}
