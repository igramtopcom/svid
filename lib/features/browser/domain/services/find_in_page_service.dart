import '../../../../core/config/brand_config.dart';

/// Service that generates JavaScript for find-in-page functionality.
///
/// Uses DOM TreeWalker to find text matches, wraps them in `<mark>` elements,
/// and provides navigation between matches with scroll-into-view.
class FindInPageService {
  /// CSS class used for highlighting matches (brand-prefixed to avoid collisions).
  static String get _markClass => '${BrandConfig.current.brand.name}-find-highlight';

  /// CSS class for the currently-active (focused) match.
  static String get _activeClass => '${BrandConfig.current.brand.name}-find-active';

  /// Escapes a string for safe injection into a JavaScript string literal.
  static String escapeJs(String input) {
    return input
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r')
        .replaceAll('\t', r'\t');
  }

  /// Generate JavaScript that:
  /// 1. Clears previous highlights.
  /// 2. Walks all text nodes, wraps matches in `<mark>`.
  /// 3. Scrolls to the first match.
  /// 4. Returns the total match count as a string.
  String generateFindScript(String query, {bool caseSensitive = false}) {
    if (query.isEmpty) return generateClearScript();

    final escaped = escapeJs(query);
    final flags = caseSensitive ? '' : 'gi';
    // JS regex special chars escape pattern — use \$ for literal $ in Dart
    const regexEscape =
        r"query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')";

    return '(function() {\n'
        "  var oldMarks = document.querySelectorAll('mark.$_markClass');\n"
        '  for (var i = 0; i < oldMarks.length; i++) {\n'
        '    var parent = oldMarks[i].parentNode;\n'
        '    parent.replaceChild(document.createTextNode(oldMarks[i].textContent), oldMarks[i]);\n'
        '    parent.normalize();\n'
        '  }\n'
        "  var query = '$escaped';\n"
        "  if (!query) return '0';\n"
        '  var regex = new RegExp($regexEscape, \'$flags\');\n'
        '  var walker = document.createTreeWalker(\n'
        '    document.body, NodeFilter.SHOW_TEXT, null, false\n'
        '  );\n'
        '  var textNodes = [];\n'
        '  while (walker.nextNode()) {\n'
        '    var node = walker.currentNode;\n'
        '    if (node.nodeValue && node.nodeValue.trim().length > 0) {\n'
        '      var parentTag = node.parentElement ? node.parentElement.tagName : \'\';\n'
        '      if (parentTag !== \'SCRIPT\' && parentTag !== \'STYLE\' && parentTag !== \'NOSCRIPT\') {\n'
        '        textNodes.push(node);\n'
        '      }\n'
        '    }\n'
        '  }\n'
        '  var totalMatches = 0;\n'
        '  for (var i = 0; i < textNodes.length; i++) {\n'
        '    var node = textNodes[i];\n'
        '    var text = node.nodeValue;\n'
        '    var match = regex.exec(text);\n'
        '    if (!match) continue;\n'
        '    regex.lastIndex = 0;\n'
        '    var fragment = document.createDocumentFragment();\n'
        '    var lastIndex = 0;\n'
        '    while ((match = regex.exec(text)) !== null) {\n'
        '      if (match.index > lastIndex) {\n'
        '        fragment.appendChild(document.createTextNode(text.substring(lastIndex, match.index)));\n'
        '      }\n'
        '      var mark = document.createElement(\'mark\');\n'
        '      mark.className = \'$_markClass\';\n'
        "      mark.style.backgroundColor = '#FFEB3B';\n"
        "      mark.style.color = '#000';\n"
        "      mark.style.padding = '0';\n"
        "      mark.style.borderRadius = '2px';\n"
        '      mark.textContent = match[0];\n'
        '      mark.setAttribute(\'data-find-index\', totalMatches.toString());\n'
        '      fragment.appendChild(mark);\n'
        '      totalMatches++;\n'
        '      lastIndex = regex.lastIndex;\n'
        '      if (match[0].length === 0) { regex.lastIndex++; break; }\n'
        '    }\n'
        '    if (lastIndex < text.length) {\n'
        '      fragment.appendChild(document.createTextNode(text.substring(lastIndex)));\n'
        '    }\n'
        '    node.parentNode.replaceChild(fragment, node);\n'
        '  }\n'
        "  var firstMark = document.querySelector('mark.$_markClass');\n"
        '  if (firstMark) {\n'
        '    firstMark.classList.add(\'$_activeClass\');\n'
        "    firstMark.style.backgroundColor = '#FF9800';\n"
        "    firstMark.style.outline = '2px solid #E65100';\n"
        "    firstMark.scrollIntoView({behavior: 'smooth', block: 'center'});\n"
        '  }\n'
        '  return totalMatches.toString();\n'
        '})()';
  }

  /// Generate JavaScript to navigate to the next or previous match.
  /// [currentIndex] is the 0-based index of the currently active match.
  /// [totalMatches] is the total number of matches.
  /// Returns JS that highlights the target match and returns its index as string.
  String generateNavigateScript({
    required int currentIndex,
    required int totalMatches,
    required bool forward,
  }) {
    if (totalMatches <= 0) return "'0'";

    final targetIndex = forward
        ? (currentIndex + 1) % totalMatches
        : (currentIndex - 1 + totalMatches) % totalMatches;

    return '(function() {\n'
        "  var marks = document.querySelectorAll('mark.$_markClass');\n"
        "  if (marks.length === 0) return '-1';\n"
        '  for (var i = 0; i < marks.length; i++) {\n'
        '    marks[i].classList.remove(\'$_activeClass\');\n'
        "    marks[i].style.backgroundColor = '#FFEB3B';\n"
        "    marks[i].style.outline = 'none';\n"
        '  }\n'
        '  var target = $targetIndex;\n'
        '  if (target >= 0 && target < marks.length) {\n'
        '    marks[target].classList.add(\'$_activeClass\');\n'
        "    marks[target].style.backgroundColor = '#FF9800';\n"
        "    marks[target].style.outline = '2px solid #E65100';\n"
        "    marks[target].scrollIntoView({behavior: 'smooth', block: 'center'});\n"
        '  }\n'
        '  return target.toString();\n'
        '})()';
  }

  /// Generate JavaScript to clear all find-in-page highlights.
  String generateClearScript() {
    return '(function() {\n'
        "  var marks = document.querySelectorAll('mark.$_markClass');\n"
        '  for (var i = 0; i < marks.length; i++) {\n'
        '    var parent = marks[i].parentNode;\n'
        '    parent.replaceChild(document.createTextNode(marks[i].textContent), marks[i]);\n'
        '    parent.normalize();\n'
        '  }\n'
        "  return '0';\n"
        '})()';
  }
}
