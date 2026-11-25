import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../theme/tokens.dart';
import 'open_link.dart';
import 'theme.dart';

/// A link the read view makes tappable: http and https only.
final RegExp _urlPattern = RegExp(
  r'''https?://[^\s<>"'`]+''',
  caseSensitive: false,
);

/// The links in [s], in order, without trailing punctuation or a closing
/// bracket the link does not open itself ("see http://x.test/a." and
/// "(http://x.test/a)" give `http://x.test/a`).
@visibleForTesting
List<String> urlsIn(String s) => [
  for (final m in _urlPattern.allMatches(s)) ?_trimUrl(m.group(0)!),
];

String? _trimUrl(String raw) {
  var u = raw;
  const punct = ".,;:!?'\"`";
  while (u.isNotEmpty && punct.contains(u[u.length - 1])) {
    u = u.substring(0, u.length - 1);
  }
  const pairs = {')': '(', ']': '[', '}': '{'};
  while (u.isNotEmpty && pairs.containsKey(u[u.length - 1])) {
    final close = u[u.length - 1];
    final opens = u.split(pairs[close]!).length - 1;
    final closes = u.split(close).length - 1;
    if (closes <= opens) break;
    u = u.substring(0, u.length - 1);
  }
  // A scheme alone ("http://" then a period) is not a link.
  final scheme = u.indexOf('://');
  return scheme < 0 || u.length == scheme + 3 ? null : u;
}

/// Small renderer for the note text the planning notes use: `#` headings,
/// `-` lists, numbered lists, `**bold**`, `` `code` `` and paragraphs. An
/// http/https link in the text is tappable and opens outside the app.
class MarkdownLite extends StatefulWidget {
  const MarkdownLite(this.text, {super.key, this.onOpenUrl = openExternalUrl});
  final String text;

  /// Opens a link the text holds (a new browser tab by default).
  final ValueChanged<String> onOpenUrl;

  @override
  State<MarkdownLite> createState() => _MarkdownLiteState();
}

class _MarkdownLiteState extends State<MarkdownLite> {
  /// One recognizer per link, for the life of the widget: a span's recognizer
  /// must not be disposed while a render object still points at it.
  final Map<String, TapGestureRecognizer> _links = {};

  @override
  void dispose() {
    for (final r in _links.values) {
      r.dispose();
    }
    super.dispose();
  }

  TapGestureRecognizer _recognizer(String url) => _links.putIfAbsent(
    url,
    () => TapGestureRecognizer()..onTap = () => widget.onOpenUrl(url),
  );

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final base = context.theme.typography.body.sm.copyWith(color: t.fg);
    final out = <Widget>[];
    final para = <String>[];

    void flush() {
      if (para.isEmpty) return;
      out.add(
        Padding(
          padding: EdgeInsets.only(bottom: t.space.lg - t.space.xxs),
          child: Text.rich(_inline(para.join(' '), base, t)),
        ),
      );
      para.clear();
    }

    for (final raw in widget.text.split('\n')) {
      final line = raw.trimRight();
      final h = RegExp(r'^(#{1,4})\s+(.*)$').firstMatch(line);
      final li = RegExp(r'^\s*([-*]|\d+\.)\s+(.*)$').firstMatch(line);
      if (line.trim().isEmpty) {
        flush();
      } else if (h != null) {
        flush();
        final size = t.type.markdownHeadings[h.group(1)!.length - 1];
        out.add(
          Padding(
            padding: EdgeInsets.only(top: t.space.md, bottom: t.space.sm),
            child: Text.rich(
              _inline(
                h.group(2)!,
                base.copyWith(fontSize: size, fontWeight: t.type.semibold),
                t,
              ),
            ),
          ),
        );
      } else if (li != null) {
        flush();
        final marker = li.group(1)!.endsWith('.') ? li.group(1)! : '•';
        out.add(
          Padding(
            padding: EdgeInsets.only(left: t.space.sm, bottom: t.space.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: t.sizes.listMarker,
                  child: Text(marker, style: base),
                ),
                Expanded(child: Text.rich(_inline(li.group(2)!, base, t))),
              ],
            ),
          ),
        );
      } else {
        para.add(line.trim());
      }
    }
    flush();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: out);
  }

  TextSpan _inline(String s, TextStyle base, Tokens t) {
    final spans = <InlineSpan>[];
    final re = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`');
    var pos = 0;
    void plain(String text) {
      // Links only in plain text, never inside **bold** or `code`.
      var at = 0;
      for (final m in _urlPattern.allMatches(text)) {
        final url = _trimUrl(m.group(0)!);
        if (url == null) continue;
        if (m.start > at) {
          spans.add(TextSpan(text: text.substring(at, m.start)));
        }
        spans.add(
          TextSpan(
            text: url,
            style: base.copyWith(
              color: t.accent,
              decoration: TextDecoration.underline,
              decorationColor: t.accent,
            ),
            recognizer: _recognizer(url),
            mouseCursor: SystemMouseCursors.click,
          ),
        );
        at = m.start + url.length;
      }
      if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    }

    for (final m in re.allMatches(s)) {
      if (m.start > pos) plain(s.substring(pos, m.start));
      if (m.group(1) != null) {
        spans.add(TextSpan(text: m.group(1), style: t.type.boldStyle));
      } else {
        spans.add(
          TextSpan(
            text: m.group(2),
            style: t.type.monoStyle.copyWith(
              fontSize: (base.fontSize ?? t.type.body) - 1,
              color: t.accent,
            ),
          ),
        );
      }
      pos = m.end;
    }
    if (pos < s.length) plain(s.substring(pos));
    return TextSpan(style: base, children: spans);
  }
}
