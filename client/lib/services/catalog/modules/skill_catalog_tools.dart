import '../catalog_kind.dart';

const skillCatalogTools = <CatalogToolSpec>[
  CatalogToolSpec(
    name: 'search_skills',
    description: 'Search the TeamPilot skill catalog',
    inputSchema: {
      'type': 'object',
      'properties': {
        'query': {'type': 'string'},
      },
    },
    mutating: false,
  ),
  CatalogToolSpec(
    name: 'read_skill',
    description: 'Read an installed skill SKILL.md and relative files',
    inputSchema: {
      'type': 'object',
      'properties': {
        'id': {'type': 'string'},
      },
      'required': ['id'],
    },
    mutating: false,
  ),
  CatalogToolSpec(
    name: 'install_skill',
    description: 'Install a skill from git, marketplace, or script_url',
    inputSchema: {
      'type': 'object',
      'properties': {
        'id': {'type': 'string'},
        'repo': {'type': 'string'},
        'directory': {'type': 'string'},
        'branch': {'type': 'string'},
        'script_url': {'type': 'string'},
      },
    },
    mutating: true,
  ),
  CatalogToolSpec(
    name: 'import_skill',
    description: 'Import a skill directory from the session workspace',
    inputSchema: {
      'type': 'object',
      'properties': {
        'path': {'type': 'string'},
      },
      'required': ['path'],
    },
    mutating: true,
  ),
  CatalogToolSpec(
    name: 'create_skill',
    description: 'Create a local skill from name and body',
    inputSchema: {
      'type': 'object',
      'properties': {
        'name': {'type': 'string'},
        'directory': {'type': 'string'},
        'body': {'type': 'string'},
        'description': {'type': 'string'},
      },
      'required': ['name', 'body'],
    },
    mutating: true,
  ),
  CatalogToolSpec(
    name: 'update_skill',
    description: 'Overwrite files for an installed skill',
    inputSchema: {
      'type': 'object',
      'properties': {
        'id': {'type': 'string'},
        'body': {'type': 'string'},
      },
      'required': ['id'],
    },
    mutating: true,
  ),
  CatalogToolSpec(
    name: 'unbind_skill',
    description: 'Unbind a skill from this workspace without uninstalling',
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
    name: 'delete_skill',
    description: 'Uninstall a skill and unbind it from this workspace',
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
