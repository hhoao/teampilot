import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/run/launch_config_document.dart';
import 'package:teampilot/models/run/launch_configuration.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/run/launch_config_store.dart';
import 'package:teampilot/services/run/run_default_selection.dart';

const _folder = WorkspaceFolder(path: '/proj');

OwnedLaunchConfiguration _config(String id) => OwnedLaunchConfiguration(
  owner: _folder,
  configuration: LaunchConfiguration(id: id, name: id, type: 'shellScript'),
);

OwnedLaunchCompound _compound(String id) => OwnedLaunchCompound(
  owner: _folder,
  compound: LaunchCompound(id: id, name: id, configurationIds: const []),
);

void main() {
  test('restores persisted key when it matches a config', () {
    final a = _config('a');
    final b = _config('b');
    expect(
      resolveRunDefaultSelection(
        persistedKey: b.selectionKey,
        configurations: [a, b],
        compounds: const [],
      ),
      b.selectionKey,
    );
  });

  test('restores persisted key when it matches a compound', () {
    final c = _compound('c');
    expect(
      resolveRunDefaultSelection(
        persistedKey: c.selectionKey,
        configurations: const [],
        compounds: [c],
      ),
      c.selectionKey,
    );
  });

  test('stale persisted key falls back to first config', () {
    final a = _config('a');
    expect(
      resolveRunDefaultSelection(
        persistedKey: 'missing',
        configurations: [a],
        compounds: const [],
      ),
      a.selectionKey,
    );
  });

  test('no configs uses first compound', () {
    final c = _compound('c');
    expect(
      resolveRunDefaultSelection(
        persistedKey: null,
        configurations: const [],
        compounds: [c],
      ),
      c.selectionKey,
    );
  });

  test('empty lists yield null', () {
    expect(
      resolveRunDefaultSelection(
        persistedKey: 'x',
        configurations: const [],
        compounds: const [],
      ),
      isNull,
    );
  });

  test('recommendations are ignored (not passed in)', () {
    // Document: helper has no recommendations parameter.
    final a = _config('a');
    expect(
      resolveRunDefaultSelection(
        persistedKey: null,
        configurations: [a],
        compounds: const [],
      ),
      a.selectionKey,
    );
  });
}
