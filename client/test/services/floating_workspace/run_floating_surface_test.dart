import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/services/floating_workspace/surfaces/run_floating_surface.dart';

void main() {
  test('createTab builds run: id and payload', () {
    final surface = RunFloatingSurface(
      floating: FloatingWorkspaceCubit(),
      resolveTitle: (id) => id == 'r1' ? 'Script' : null,
      onDismiss: (_) async {},
    );
    final tab = surface.createTab(workspaceId: 'w1', payload: 'r1');
    expect(tab.id, 'run:r1');
    expect(tab.surfaceId, 'run');
    expect(tab.title, 'Script');
    expect(tab.payload, 'r1');
  });
}
