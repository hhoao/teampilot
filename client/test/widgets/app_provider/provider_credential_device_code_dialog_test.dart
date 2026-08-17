import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/provider/credential_login_progress.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/widgets/app_provider/provider_credential_device_code_dialog.dart';

void main() {
  late Directory temp;
  late AppProviderCubit cubit;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('device_code_dialog_');
    cubit = AppProviderCubit(
      repository: AppProviderRepository(basePath: temp.path),
      basePath: temp.path,
    );
    cubit.beginCredentialLogin('openai-official');
    cubit.reportCredentialLoginProgress(
      CredentialLoginProgress(
        deviceCode: 'WO3M-X8OIF',
        verificationUri: Uri.parse('https://auth.openai.com/codex/device'),
      ),
    );
  });

  tearDown(() async {
    await cubit.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  testWidgets('dialog shows selectable device code and verification uri', (
    tester,
  ) async {
    final theme = ThemeData(useMaterial3: true);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: theme,
        home: TpTheme(
          data: TpThemeData.fromColorScheme(
            theme.colorScheme,
            scale: 1.0,
            controlScale: AppTypographyScale.standard.multiplier,
          ),
          child: BlocProvider<AppProviderCubit>.value(
            value: cubit,
            child: const Scaffold(body: ProviderCredentialDeviceCodeDialog()),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TpDialog), findsOneWidget);
    expect(find.text('Device code'), findsOneWidget);
    expect(find.byKey(const Key('provider-device-code')), findsOneWidget);
    expect(find.text('WO3M-X8OIF'), findsOneWidget);
    expect(
      find.byKey(const Key('provider-device-verification-uri')),
      findsOneWidget,
    );
    expect(find.text('https://auth.openai.com/codex/device'), findsOneWidget);
    expect(find.text('Reopen browser'), findsOneWidget);
  });
}
