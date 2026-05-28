import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/mcp_server.dart';
import '../repositories/mcp_repository.dart';
import '../services/mcp/mcp_import_service.dart';

enum McpLoadStatus { idle, loading, ready, error }

class McpState extends Equatable {
  const McpState({
    this.servers = const [],
    this.status = McpLoadStatus.idle,
    this.errorMessage,
    this.busyIds = const {},
  });

  final List<McpServer> servers;
  final McpLoadStatus status;
  final String? errorMessage;
  final Set<String> busyIds;

  McpState copyWith({
    List<McpServer>? servers,
    McpLoadStatus? status,
    String? errorMessage,
    bool clearError = false,
    Set<String>? busyIds,
  }) => McpState(
    servers: servers ?? this.servers,
    status: status ?? this.status,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    busyIds: busyIds ?? this.busyIds,
  );

  @override
  List<Object?> get props => [servers, status, errorMessage, busyIds];
}

class McpCubit extends Cubit<McpState> {
  McpCubit(
    this._repository, {
    Future<void> Function(String mcpId)? onMcpDeleted,
    McpImportService? importService,
  }) : _onMcpDeleted = onMcpDeleted,
       _importService = importService ?? McpImportService(),
       super(const McpState());

  final McpRepository _repository;
  final Future<void> Function(String mcpId)? _onMcpDeleted;
  final McpImportService _importService;

  Future<void> loadAll() async {
    emit(state.copyWith(status: McpLoadStatus.loading, clearError: true));
    try {
      final servers = await _repository.loadAll();
      emit(
        state.copyWith(
          servers: servers,
          status: McpLoadStatus.ready,
          clearError: true,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: McpLoadStatus.error,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  Future<void> toggleEnabled(McpServer server, bool enabled) async {
    await upsert(server.copyWith(enabled: enabled));
  }

  Future<bool> upsert(McpServer server) async {
    final busy = {...state.busyIds, server.id};
    emit(state.copyWith(busyIds: busy));
    try {
      final saved = await _repository.upsert(server);
      final list = [...state.servers.where((s) => s.id != saved.id), saved];
      emit(state.copyWith(servers: list, clearError: true));
      return true;
    } on McpValidationException catch (e) {
      emit(state.copyWith(errorMessage: e.errors.join('\n')));
      return false;
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
      return false;
    } finally {
      final nextBusy = {...state.busyIds}..remove(server.id);
      emit(state.copyWith(busyIds: nextBusy));
    }
  }

  Future<void> delete(String id) async {
    final busy = {...state.busyIds, id};
    emit(state.copyWith(busyIds: busy));
    try {
      await _repository.deleteById(id);
      emit(
        state.copyWith(
          servers: state.servers.where((s) => s.id != id).toList(),
          clearError: true,
        ),
      );
      await _onMcpDeleted?.call(id);
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
    } finally {
      final nextBusy = {...state.busyIds}..remove(id);
      emit(state.copyWith(busyIds: nextBusy));
    }
  }

  Future<McpImportPreview> previewImport() =>
      _importService.previewAgainst(state.servers);

  Future<bool> applyImport(
    McpImportPreview preview, {
    bool overwriteConflicts = false,
  }) async {
    try {
      final catalog = await _repository.catalogService();
      await _importService.applyPreview(
        preview,
        overwriteConflicts: overwriteConflicts,
        catalog: catalog,
      );
      await loadAll();
      return true;
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
      return false;
    }
  }

  void clearError() => emit(state.copyWith(clearError: true));
}
