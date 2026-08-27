import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Elements removed outright before rendering untrusted HTML.
const Set<String> _removedElements = {'script', 'iframe', 'object', 'embed'};

/// URL schemes never allowed to reach a renderer.
const Set<String> _dangerousSchemes = {'javascript:', 'vbscript:'};

/// Parses [rawHtml] and strips dangerous markup before rendering:
/// script/iframe/object/embed elements, `on*` event handler attributes,
/// `srcdoc`, and javascript/vbscript URLs.
///
/// Defense in depth: flutter_html executes no script, but sanitized input
/// keeps hostile markup out of the widget tree entirely. Returns the parsed
/// DOM document (the parser wraps input in html/body).
dom.Document sanitizeHtmlDocument(String rawHtml) {
  final document = html_parser.parse(rawHtml);
  final root = document.documentElement;
  if (root != null) _scrub(root);
  return document;
}

/// Plain text of [rawHtml] (search indexing; sanitization not required here).
String htmlPlainText(String rawHtml) =>
    html_parser.parse(rawHtml).documentElement?.text ?? '';

void _scrub(dom.Element element) {
  // Keys are String or AttributeName (LinkedHashMap<Object, String>).
  element.attributes.removeWhere(
    (name, _) => name.toString().toLowerCase().startsWith('on'),
  );
  element.attributes.remove('srcdoc');

  for (final attrName in const ['href', 'src', 'action', 'data']) {
    final value = element.attributes[attrName];
    if (value != null && _isDangerousUrl(value)) {
      element.attributes.remove(attrName);
    }
  }

  final doomed = element.nodes
      .whereType<dom.Element>()
      .where(
        (child) => _removedElements.contains(
          child.localName?.toLowerCase(),
        ),
      )
      .toList();
  for (final child in doomed) {
    child.remove();
  }

  final survivors = element.nodes.whereType<dom.Element>().toList();
  for (final child in survivors) {
    _scrub(child);
  }
}

bool _isDangerousUrl(String url) {
  // Collapse whitespace/control chars that browsers ignore in schemes.
  final normalized = url.trim().toLowerCase().replaceAll(
        RegExp(r'[\s\x00-\x1f]'),
        '',
      );
  return _dangerousSchemes.any(normalized.startsWith);
}
