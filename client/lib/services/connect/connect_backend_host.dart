import 'connect_settings_store.dart';
import 'connect_ssh_backend.dart';

/// Owns the embedded vs system SSH backends and starts only the effective one.
class ConnectBackendHost {
  ConnectBackendHost({
    required ConnectSshBackend embedded,
    ConnectSshBackend? system,
    required ConnectSettingsStore settings,
    required this.systemSshdSelectable,
  }) : _embedded = embedded,
       _system = system,
       _settings = settings,
       _current = embedded,
       _kind = ConnectSshBackendKind.embedded;

  final ConnectSshBackend _embedded;
  final ConnectSshBackend? _system;
  final ConnectSettingsStore _settings;
  final bool systemSshdSelectable;

  ConnectSshBackend _current;
  ConnectSshBackendKind _kind;

  ConnectSshBackend get current => _current;
  ConnectSshBackendKind get kind => _kind;

  Future<void> startSelected() => _applyEffective();

  Future<void> select(ConnectSshBackendKind requested) async {
    await _settings.saveSshBackend(requested);
    await _applyEffective();
  }

  Future<ConnectSshBackendKind> _effectiveKind() async {
    if (_system == null) return ConnectSshBackendKind.embedded;
    final stored = (await _settings.load()).sshBackend;
    return effectiveConnectSshBackend(
      stored: stored,
      systemSshdSelectable: systemSshdSelectable,
    );
  }

  Future<void> _applyEffective() async {
    final nextKind = await _effectiveKind();
    final next = nextKind == ConnectSshBackendKind.system
        ? _system!
        : _embedded;
    await _current.stop();
    _current = next;
    _kind = nextKind;
    await _current.start();
  }
}
