import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Verifies both ARB locale maps carry the complete bilingual
/// team-generation contract (plan Task 16 step 1 audit table).
void main() {
  const requiredKeys = <String>{
    'teamGenerateLaunch',
    'teamGenerateSettingsTitle',
    'teamGenerateGeneratorModel',
    'teamGenerateTeamMode',
    'teamGenerateNative',
    'teamGenerateMixed',
    'teamGenerateNativeCli',
    'teamGenerateModelPool',
    'teamGenerateAddModel',
    'teamGenerateHiddenPresets',
    'teamGenerateMissingPreset',
    'teamGenerateDescription',
    'teamGenerateTags',
    'teamGenerateMoveUp',
    'teamGenerateMoveDown',
    'teamGenerateRemove',
    'teamGenerateCapabilityNote',
    'teamGenerateBuilderTitle',
    'teamGenerateCancel',
    'teamGenerateRetry',
    'teamGenerateContinueSetup',
    'teamGenerateCancelTitle',
    'teamGenerateCancelBody',
    'teamGenerateErrorDescriptionRequired',
    'teamGenerateErrorAiNotConfigured',
    'teamGenerateErrorPoolEmpty',
    'teamGenerateErrorGeneratorUnsupported',
    'teamGenerateErrorNativeUnsupported',
    'teamGenerateErrorTargetUnavailable',
    'teamGenerateErrorStagingUnsupported',
    'teamGenerateErrorUserActionRequired',
    'teamGenerateErrorPromptDeliveryUnknown',
    'teamGenerateErrorRecoveryIntegrity',
    'teamGenerateOpenSettings',
    'teamGenerateOpenLeadSession',
    'teamGenerateDeliveryArrived',
    'teamGenerateDeliverySendAgain',
    'teamGenerateDeliveryRetryTitle',
    'teamGenerateDeliveryRetryBody',
  };

  final en = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
      as Map<String, dynamic>;
  final zh = jsonDecode(File('lib/l10n/app_zh.arb').readAsStringSync())
      as Map<String, dynamic>;

  test('every team-generation key exists in both ARBs and is non-blank', () {
    for (final key in requiredKeys) {
      final enValue = en[key] as String?;
      final zhValue = zh[key] as String?;
      expect(enValue, isNotNull, reason: 'missing $key in app_en.arb');
      expect(zhValue, isNotNull, reason: 'missing $key in app_zh.arb');
      expect(enValue!.trim(), isNotEmpty, reason: 'blank $key in app_en.arb');
      expect(zhValue!.trim(), isNotEmpty, reason: 'blank $key in app_zh.arb');
    }
  });

  test('placeholder-bearing entries declare matching metadata', () {
    for (final key in const {
      'teamGenerateHiddenPresets',
      'teamGenerateMissingPreset',
    }) {
      final enMeta = en['@$key'] as Map<String, dynamic>?;
      expect(enMeta, isNotNull, reason: 'missing @$key metadata in en');
      expect(enMeta!['placeholders'], isNotNull);
      final zhMeta = zh['@$key'] as Map<String, dynamic>?;
      // zh metadata is optional (en carries the canonical declaration);
      // when present it must also declare placeholders.
      if (zhMeta != null) {
        expect(zhMeta['placeholders'], isNotNull);
      }
    }
  });

}
