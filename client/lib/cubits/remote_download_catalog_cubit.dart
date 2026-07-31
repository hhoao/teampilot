import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/remote_download/remote_download_catalog.dart';
import '../services/remote_download/remote_download_settings_store.dart';

@immutable
class RemoteDownloadCatalogState extends Equatable {
  const RemoteDownloadCatalogState({
    required this.catalog,
    this.mirrorBaseUrl,
    this.loaded = false,
  });

  final RemoteDownloadCatalog catalog;
  final String? mirrorBaseUrl;
  final bool loaded;

  RemoteDownloadCatalogState copyWith({
    RemoteDownloadCatalog? catalog,
    String? mirrorBaseUrl,
    bool? loaded,
    bool clearMirrorBaseUrl = false,
  }) {
    return RemoteDownloadCatalogState(
      catalog: catalog ?? this.catalog,
      mirrorBaseUrl:
          clearMirrorBaseUrl ? null : (mirrorBaseUrl ?? this.mirrorBaseUrl),
      loaded: loaded ?? this.loaded,
    );
  }

  @override
  List<Object?> get props => [catalog, mirrorBaseUrl, loaded];
}

class RemoteDownloadCatalogCubit extends Cubit<RemoteDownloadCatalogState> {
  RemoteDownloadCatalogCubit({required RemoteDownloadSettingsStore store})
      : _store = store,
        super(
          RemoteDownloadCatalogState(
            catalog: RemoteDownloadCatalog.defaults(),
          ),
        );

  final RemoteDownloadSettingsStore _store;

  RemoteDownloadCatalog get catalog => state.catalog;

  Future<void> load() async {
    final settings = await _store.load();
    final catalog = await _store.loadEffectiveCatalog();
    emit(
      state.copyWith(
        catalog: catalog,
        mirrorBaseUrl: settings?.mirrorBaseUrl,
        loaded: true,
        clearMirrorBaseUrl: settings?.mirrorBaseUrl == null,
      ),
    );
  }

  Future<void> setMirrorBaseUrl(String? mirrorBaseUrl) async {
    final current = await _store.load() ?? const RemoteDownloadSettings();
    final next = RemoteDownloadSettings(
      sources: current.sources,
      mirrorBaseUrl: mirrorBaseUrl,
    );
    await _store.save(next);
    final catalog = await _store.loadEffectiveCatalog();
    emit(
      state.copyWith(
        catalog: catalog,
        mirrorBaseUrl: mirrorBaseUrl,
        loaded: true,
        clearMirrorBaseUrl: mirrorBaseUrl == null,
      ),
    );
  }

  Future<void> restoreDefaults() async {
    await _store.clear();
    emit(
      RemoteDownloadCatalogState(
        catalog: RemoteDownloadCatalog.defaults(),
        loaded: true,
      ),
    );
  }
}
