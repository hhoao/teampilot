import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/services/floating_workspace/surfaces/html_preview_floating_surface.dart';

void main() {
  test('createTab builds stable tab for html path', () {
    final floating = FloatingWorkspaceCubit();
    final surface = HtmlPreviewFloatingSurface(floating: floating);
    final tab = surface.createTab(workspaceId: 'ws1', payload: '/repo/a.html');
    expect(tab.surfaceId, 'htmlPreview');
    expect(tab.id, 'htmlPreview:/repo/a.html');
    expect(tab.title, 'a.html');
    expect(tab.payload, '/repo/a.html');
    floating.close();
  });
}
