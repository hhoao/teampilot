import '../catalog_kind.dart';

const pluginCatalogTools = <CatalogToolSpec>[
  CatalogToolSpec(
    name: 'search_plugins',
    description: 'Search the TeamPilot plugin catalog',
    inputSchema: {
      'type': 'object',
      'properties': {
        'query': {'type': 'string'},
      },
    },
    mutating: false,
  ),
  CatalogToolSpec(
    name: 'read_plugin',
    description: 'Read an installed plugin manifest and relative files',
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
    name: 'install_plugin',
    description: 'Install a plugin from a marketplace or bind an installed id',
    inputSchema: {
      'type': 'object',
      'properties': {
        'id': {'type': 'string'},
        'key': {'type': 'string'},
      },
    },
    mutating: true,
  ),
  CatalogToolSpec(
    name: 'import_plugin',
    description: 'Import a plugin directory from the session workspace',
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
    name: 'update_plugin',
    description:
        'Update an installed plugin from marketplace or a new source path',
    inputSchema: {
      'type': 'object',
      'properties': {
        'id': {'type': 'string'},
        'path': {'type': 'string'},
      },
      'required': ['id'],
    },
    mutating: true,
  ),
  CatalogToolSpec(
    name: 'unbind_plugin',
    description: 'Unbind a plugin from this workspace without uninstalling',
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
    name: 'delete_plugin',
    description: 'Uninstall a plugin and unbind it from this workspace',
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
