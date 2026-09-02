import '../../models/generated_team_plan.dart';

/// Shared JSON Schema fragments for Team Composer tool ads.
abstract final class TeamComposerToolSchemas {
  /// Nested plan object accepted by validate/finalize. Mirrors
  /// [GeneratedTeamPlan.wireSchema]; unknown keys are rejected server-side.
  static Map<String, Object?> get planProperty => {
    'type': 'object',
    'description':
        'Complete team plan matching planSchema from get_generation_context. '
        'Draft the full object before calling validate_team_plan; do not probe '
        'with partial plans. Lead member name must be exactly "team-lead". '
        'team.mode must equal requestedMode.',
    'additionalProperties': false,
    'required': ['team', 'members'],
    'properties': {
      'schemaVersion': {
        'type': 'integer',
        'const': GeneratedTeamPlan.schemaVersion,
        'description': 'Plan schema version; omit or set to 1.',
      },
      'team': {
        'type': 'object',
        'additionalProperties': false,
        'required': ['name', 'description', 'mode'],
        'properties': {
          'name': {
            'type': 'string',
            'minLength': 1,
            'description': 'Display name for the generated team.',
          },
          'description': {
            'type': 'string',
            'minLength': 1,
            'description': 'One-sentence purpose of the team.',
          },
          'mode': {
            'type': 'string',
            'enum': ['mixed', 'native'],
            'description':
                'Must equal requestedMode from get_generation_context.',
          },
        },
      },
      'members': {
        'type': 'array',
        'minItems': 2,
        'maxItems': 5,
        'description':
            'Roster of 2–5 members. Exactly one member must have '
            'name "team-lead" with replicas=1.',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': [
            'name',
            'role',
            'responsibilities',
            'workingMethod',
            'replicas',
            'placement',
          ],
          'properties': {
            'name': {
              'type': 'string',
              'minLength': 1,
              'description':
                  'Member id. Lead must be exactly "team-lead"; others are '
                  'unique slug-friendly names.',
            },
            'role': {
              'type': 'string',
              'minLength': 1,
              'description': 'Distinct role label; must not overlap other roles.',
            },
            'responsibilities': {
              'type': 'string',
              'minLength': 1,
              'description': 'Non-overlapping responsibilities for this role.',
            },
            'workingMethod': {
              'type': 'string',
              'minLength': 1,
              'description': 'How this role collaborates and delivers work.',
            },
            'presetId': {
              'type': 'string',
              'description':
                  'Frozen modelPool presetId. Empty string inherits the '
                  'default; never invent IDs.',
            },
            'replicas': {
              'type': 'integer',
              'minimum': 1,
              'maximum': 8,
              'description': 'Replica count; lead must be 1.',
            },
            'placement': {
              'type': 'object',
              'description':
                  'Map of probed targetId → replica count. Probe before '
                  'assigning. Example: {"local": 1}.',
              'additionalProperties': {
                'type': 'integer',
                'minimum': 0,
              },
            },
          },
        },
      },
      'resources': {
        'type': 'object',
        'additionalProperties': false,
        'description':
            'Optional Catalog resource IDs already staged or installed for '
            'this workflow.',
        'properties': {
          'skillIds': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'pluginIds': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'mcpServerIds': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
      },
    },
  };

  static const Map<String, Object?> issueItem = {
    'type': 'object',
    'additionalProperties': false,
    'required': ['code'],
    'properties': {
      'code': {'type': 'string'},
      'detail': {'type': 'string'},
    },
  };

  static Map<String, Object?> get contextOutput => {
    'type': 'object',
    'required': [
      'workflowId',
      'originalPrompt',
      'requestedMode',
      'planSchema',
      'modelPool',
      'launch',
    ],
    'properties': {
      'workflowId': {'type': 'string'},
      'originalPrompt': {'type': 'string'},
      'settingsRevision': {'type': 'string'},
      'requestedMode': {'type': 'string', 'enum': ['mixed', 'native']},
      'teamMode': {'type': 'string', 'enum': ['mixed', 'native']},
      'nativeCli': {'type': 'string'},
      'planSchema': {'type': 'object'},
      'constraints': {'type': 'object'},
      'modelPool': {'type': 'array'},
      'launch': {'type': 'object'},
    },
  };

  static Map<String, Object?> get probeOutput => {
    'type': 'object',
    'required': ['status', 'phase'],
    'properties': {
      'status': {'type': 'string', 'const': 'probed'},
      'phase': {'type': 'string'},
    },
  };

  static Map<String, Object?> get validateOutput => {
    'type': 'object',
    'required': ['valid', 'issues', 'revision'],
    'properties': {
      'valid': {'type': 'boolean'},
      'issues': {
        'type': 'array',
        'items': issueItem,
      },
      'revision': {
        'type': 'string',
        'description':
            'Plan revision receipt. On valid=true, pass this as '
            'validationRevision to finalize_team_generation.',
      },
    },
  };

  static Map<String, Object?> get finalizeOutput => {
    'type': 'object',
    'required': ['accepted', 'workflowId', 'phase'],
    'properties': {
      'accepted': {'type': 'boolean'},
      'workflowId': {'type': 'string'},
      'phase': {'type': 'string'},
    },
  };

  static const Map<String, Object?> readOnlyAnnotations = {
    'readOnlyHint': true,
    'destructiveHint': false,
    'idempotentHint': true,
    'openWorldHint': false,
  };

  static const Map<String, Object?> mutatingProbeAnnotations = {
    'readOnlyHint': false,
    'destructiveHint': false,
    'idempotentHint': false,
    'openWorldHint': false,
  };

  static const Map<String, Object?> validateAnnotations = {
    'readOnlyHint': false,
    'destructiveHint': false,
    'idempotentHint': true,
    'openWorldHint': false,
  };

  static const Map<String, Object?> finalizeAnnotations = {
    'readOnlyHint': false,
    'destructiveHint': true,
    'idempotentHint': true,
    'openWorldHint': false,
  };
}
