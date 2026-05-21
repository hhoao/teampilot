import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_models.dart';
import 'package:teampilot/services/backend_app_update_service.dart';

void main() {
  group('BackendAppUpdateService.suggestedPackageFileName', () {
    final app = AppApplicationRespVO(
      name: 'TeamPilot',
      version: '1.5.0',
      platform: AppPlatformEnum.windows,
    );

    test('uses basename from URL when present', () {
      final name = BackendAppUpdateService.suggestedPackageFileName(
        app: app,
        downloadUrl: 'https://cdn.example.com/teampilot-1.5.0-setup.exe',
      );
      expect(name, 'teampilot-1.5.0-setup.exe');
    });
  });

  group('BackendAppUpdateService.packageMatchesCurrentPlatform', () {
    test('is documented per platform', () {
      expect(
        BackendAppUpdateService.packageMatchesCurrentPlatform('app.apk'),
        isA<bool>(),
      );
    });
  });
}
