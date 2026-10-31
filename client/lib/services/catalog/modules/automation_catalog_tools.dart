import '../catalog_kind.dart';

const automationCatalogTools = <CatalogToolSpec>[
  CatalogToolSpec(
    name: 'read_automation',
    description:
        "List this workspace's automations, or read one automation and its "
        'recent runs when `id` is given',
    inputSchema: {
      'type': 'object',
      'properties': {
        'id': {'type': 'string'},
      },
    },
    mutating: false,
  ),
  CatalogToolSpec(
    name: 'create_automation',
    description:
        'Create an automation. Always created disabled; enable it in the '
        'Automations page or with update_automation.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'name': {'type': 'string'},
        'message': {'type': 'string'},
        'action': {
          'type': 'string',
          'enum': ['scheduledMessage', 'launchPrompt'],
        },
        'session_id': {'type': 'string'},
        'schedule': {
          'type': 'object',
          'properties': {
            'type': {
              'type': 'string',
              'enum': [
                'hourly',
                'daily',
                'weekdays',
                'weekly',
                'custom',
                'once',
              ],
            },
            'time': {'type': 'string'},
            'minute': {'type': 'integer'},
            'day_of_week': {'type': 'integer'},
            'cron': {'type': 'string'},
            'at': {
              'type': ['string', 'integer'],
            },
            'timezone': {'type': 'string'},
            'dtstart_ms': {'type': 'integer'},
          },
          'required': ['type'],
        },
        'max_run_count': {'type': 'integer'},
        'missed_run_grace_minutes': {'type': 'integer'},
        'reuse_session': {'type': 'boolean'},
        'team_id': {'type': 'string'},
        'target_member_id': {'type': 'string'},
        'preset_id': {'type': 'string'},
      },
      'required': ['name', 'message', 'schedule'],
    },
    mutating: true,
  ),
  CatalogToolSpec(
    name: 'update_automation',
    description:
        'Patch an automation. Only the provided fields change; `enabled` '
        'toggles scheduling on or off.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'id': {'type': 'string'},
        'name': {'type': 'string'},
        'message': {'type': 'string'},
        'schedule': {
          'type': 'object',
          'properties': {
            'type': {
              'type': 'string',
              'enum': [
                'hourly',
                'daily',
                'weekdays',
                'weekly',
                'custom',
                'once',
              ],
            },
            'time': {'type': 'string'},
            'minute': {'type': 'integer'},
            'day_of_week': {'type': 'integer'},
            'cron': {'type': 'string'},
            'at': {
              'type': ['string', 'integer'],
            },
            'timezone': {'type': 'string'},
            'dtstart_ms': {'type': 'integer'},
          },
          'required': ['type'],
        },
        'enabled': {'type': 'boolean'},
        'max_run_count': {'type': 'integer'},
        'missed_run_grace_minutes': {'type': 'integer'},
        'reuse_session': {'type': 'boolean'},
        'target_member_id': {'type': 'string'},
      },
      'required': ['id'],
    },
    mutating: true,
  ),
  CatalogToolSpec(
    name: 'delete_automation',
    description: 'Delete an automation and its run history',
    inputSchema: {
      'type': 'object',
      'properties': {
        'id': {'type': 'string'},
      },
      'required': ['id'],
    },
    mutating: true,
  ),
  CatalogToolSpec(
    name: 'run_automation',
    description:
        'Dispatch an automation immediately, even when it is disabled. '
        'Does not enable the automation.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'id': {'type': 'string'},
      },
      'required': ['id'],
    },
    mutating: true,
  ),
];
