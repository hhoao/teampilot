import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Verifies both locale maps carry the complete bilingual team-generation
/// contract (plan Task 16 step 1 audit table), now as the slang `team`
/// namespace (flat key `teamGenerateXxx` -> `generateXxx`).
void main() {
  // Flat ARB-era key suffix within the `team` namespace.
  const requiredKeys = <String>{
    'generateLaunch',
    'generateSettingsTitle',
    'generateGeneratorModel',
    'generateTeamMode',
    'generateNative',
    'generateMixed',
    'generateNativeCli',
    'generateModelPool',
    'generateAddModel',
    'generateHiddenPresets',
    'generateMissingPreset',
    'generateDescription',
    'generateTags',
    'generateMoveUp',
    'generateMoveDown',
    'generateRemove',
    'generateCapabilityNote',
    'generateBuilderTitle',
    'generateCancel',
    'generateRetry',
    'generateContinueSetup',
    'generateCancelTitle',
    'generateCancelBody',
    'generateErrorDescriptionRequired',
    'generateErrorAiNotConfigured',
    'generateErrorPoolEmpty',
    'generateErrorGeneratorUnsupported',
    'generateErrorNativeUnsupported',
    'generateErrorTargetUnavailable',
    'generateErrorStagingUnsupported',
    'generateErrorUserActionRequired',
    'generateErrorPromptDeliveryUnknown',
    'generateErrorRecoveryIntegrity',
    'generateOpenSettings',
    'generateOpenLeadSession',
    'generateDeliveryArrived',
    'generateDeliverySendAgain',
    'generateDeliveryRetryTitle',
    'generateDeliveryRetryBody',
  };

  final en =
      jsonDecode(File('lib/i18n/team_en.i18n.json').readAsStringSync())
          as Map<String, dynamic>;
  final zh =
      jsonDecode(File('lib/i18n/team_zh.i18n.json').readAsStringSync())
          as Map<String, dynamic>;

  test('every team-generation key exists in both locales and is non-blank', () {
    for (final key in requiredKeys) {
      final enValue = en[key] as String?;
      final zhValue = zh[key] as String?;
      expect(enValue, isNotNull, reason: 'missing $key in team_en.i18n.json');
      expect(zhValue, isNotNull, reason: 'missing $key in team_zh.i18n.json');
      expect(enValue!.trim(), isNotEmpty, reason: 'blank $key in en');
      expect(zhValue!.trim(), isNotEmpty, reason: 'blank $key in zh');
    }
  });

  test('placeholder-bearing entries keep typed placeholders', () {
    // ARB `@key.placeholders` metadata became slang typed placeholders in the
    // value itself (`{p: int}` / `{p: String}`).
    expect(
      en['generateHiddenPresets'],
      contains('{count: int}'),
      reason: 'generateHiddenPresets must declare an int placeholder',
    );
    expect(
      en['generateMissingPreset'],
      contains('{presetId: String}'),
      reason: 'generateMissingPreset must declare a String placeholder',
    );
  });
}
