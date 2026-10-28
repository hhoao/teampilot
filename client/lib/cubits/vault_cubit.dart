import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/team_config.dart';
import '../models/vault_entry.dart';
import '../models/vault_reference.dart';
import '../repositories/app_provider_repository.dart';
import '../repositories/ssh_profile_repository.dart';
import '../services/vault/vault_errors.dart';
import '../services/vault/vault_service.dart';

enum VaultStatus { loading, ready, locked, error }

class VaultState extends Equatable {
  const VaultState({
    this.status = VaultStatus.loading,
    this.entries = const [],
    this.tags = const [],
    this.query = '',
    this.typeFilter,
    this.tagFilter = const {},
    this.selectedId,
    this.busy = false,
    this.errorMessage,
    this.encrypted = false,
    this.unlocked = true,
  });

  final VaultStatus status;
  final List<VaultEntry> entries;
  final List<String> tags;
  final String query;
  final VaultEntryType? typeFilter;
  final Set<String> tagFilter;
  final String? selectedId;
  final bool busy;
  final String? errorMessage;

  /// 当前后端是否为加密文件。
  final bool encrypted;

  /// 加密后端是否已解锁；钥匙串后端恒为 true。
  final bool unlocked;

  VaultEntry? get selected {
    final id = selectedId;
    if (id == null) return null;
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  VaultState copyWith({
    VaultStatus? status,
    List<VaultEntry>? entries,
    List<String>? tags,
    String? query,
    VaultEntryType? typeFilter,
    bool clearTypeFilter = false,
    Set<String>? tagFilter,
    String? selectedId,
    bool clearSelected = false,
    bool? busy,
    String? errorMessage,
    bool clearError = false,
    bool? encrypted,
    bool? unlocked,
  }) {
    return VaultState(
      status: status ?? this.status,
      entries: entries ?? this.entries,
      tags: tags ?? this.tags,
      query: query ?? this.query,
      typeFilter: clearTypeFilter ? null : (typeFilter ?? this.typeFilter),
      tagFilter: tagFilter ?? this.tagFilter,
      selectedId: clearSelected ? null : (selectedId ?? this.selectedId),
      busy: busy ?? this.busy,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      encrypted: encrypted ?? this.encrypted,
      unlocked: unlocked ?? this.unlocked,
    );
  }

  @override
  List<Object?> get props => [
    status,
    entries,
    tags,
    query,
    typeFilter,
    tagFilter,
    selectedId,
    busy,
    errorMessage,
    encrypted,
    unlocked,
  ];
}

class VaultCubit extends Cubit<VaultState> {
  VaultCubit({
    required VaultService service,
    required SshProfileRepository sshProfiles,
    required AppProviderRepository appProviders,
  }) : _service = service,
       _sshProfiles = sshProfiles,
       _appProviders = appProviders,
       super(const VaultState());

  final VaultService _service;
  final SshProfileRepository _sshProfiles;
  final AppProviderRepository _appProviders;

  Future<void> load() async {
    emit(state.copyWith(status: VaultStatus.loading, clearError: true));
    try {
      await _service.initialize();
      if (_service.isLocked) {
        emit(
          state.copyWith(
            status: VaultStatus.locked,
            entries: const [],
            encrypted: true,
            unlocked: false,
          ),
        );
        return;
      }
      await _refresh();
      emit(
        state.copyWith(
          status: VaultStatus.ready,
          encrypted: _service.isEncrypted,
          unlocked: true,
        ),
      );
    } on VaultException catch (error) {
      emit(
        state.copyWith(
          status: VaultStatus.error,
          errorMessage: error.code,
          encrypted: _service.isEncrypted,
        ),
      );
    }
  }

  Future<void> unlock(String passphrase) async {
    emit(state.copyWith(busy: true, clearError: true));
    try {
      await _service.unlock(passphrase);
      await _refresh();
      emit(
        state.copyWith(
          status: VaultStatus.ready,
          busy: false,
          encrypted: true,
          unlocked: true,
        ),
      );
    } on VaultException catch (error) {
      emit(state.copyWith(busy: false, errorMessage: error.code));
    }
  }

  void lock() {
    _service.lock();
    emit(
      state.copyWith(
        status: VaultStatus.locked,
        entries: const [],
        clearSelected: true,
        encrypted: true,
        unlocked: false,
      ),
    );
  }

  Future<void> setQuery(String query) async {
    emit(state.copyWith(query: query));
    await _refreshEntries();
  }

  Future<void> setTypeFilter(VaultEntryType? type) async {
    emit(
      state.copyWith(
        typeFilter: type,
        clearTypeFilter: type == null,
      ),
    );
    await _refreshEntries();
  }

  Future<void> toggleTag(String tag) async {
    final tags = {...state.tagFilter};
    if (!tags.remove(tag)) tags.add(tag);
    emit(state.copyWith(tagFilter: tags));
    await _refreshEntries();
  }

  void select(String? id) {
    emit(
      id == null
          ? state.copyWith(clearSelected: true)
          : state.copyWith(selectedId: id),
    );
  }

  Future<void> save(VaultEntry entry) async {
    emit(state.copyWith(busy: true, clearError: true));
    try {
      await _service.upsert(entry);
      await _refresh();
      emit(state.copyWith(busy: false, selectedId: entry.id));
    } on VaultException catch (error) {
      emit(state.copyWith(busy: false, errorMessage: error.code));
    }
  }

  Future<void> remove(String id) async {
    await _service.delete(id);
    await _refresh();
    emit(state.copyWith(clearSelected: state.selectedId == id));
  }

  Future<void> enableEncryption(String passphrase) async {
    await _service.enableEncryptedBackend(passphrase);
    emit(
      state.copyWith(
        status: VaultStatus.ready,
        encrypted: true,
        unlocked: true,
      ),
    );
  }

  Future<void> disableEncryption() async {
    await _service.disableEncryptedBackend();
    emit(
      state.copyWith(
        status: VaultStatus.ready,
        encrypted: false,
        unlocked: true,
      ),
    );
  }

  Future<List<VaultReference>> referencesFor(String entryId) async {
    final profiles = await _sshProfiles.loadAll();
    final references = <VaultReference>[
      for (final profile in profiles)
        if (profile.vaultEntryId == entryId)
          VaultReference(
            kind: VaultReferenceKind.sshProfile,
            id: profile.id,
            label: profile.name,
          ),
    ];
    for (final cli in CliTool.values) {
      final providers = await _appProviders.loadProviders(cli);
      for (final provider in providers) {
        if (provider.credentialLink.trim() == 'vault:$entryId') {
          references.add(
            VaultReference(
              kind: VaultReferenceKind.appProvider,
              id: provider.id,
              label: provider.name,
            ),
          );
        }
      }
    }
    return references;
  }

  Future<void> _refresh() async {
    final all = await _service.list();
    emit(state.copyWith(tags: _collectTags(all)));
    await _refreshEntries();
  }

  Future<void> _refreshEntries() async {
    final entries = await _service.list(
      query: state.query,
      type: state.typeFilter,
      tags: state.tagFilter,
    );
    emit(state.copyWith(entries: entries));
  }

  List<String> _collectTags(List<VaultEntry> entries) {
    final tags = <String>{};
    for (final entry in entries) {
      tags.addAll(entry.tags);
    }
    final sorted = tags.toList()..sort();
    return List.unmodifiable(sorted);
  }
}
