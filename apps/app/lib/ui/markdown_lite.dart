import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../theme/tokens.dart';
import 'theme.dart';

/// Small renderer for the note text the planning notes use: `#` headings,
/// `-` lists, numbered lists, `**bold**`, `` `code` `` and paragraphs.
class MarkdownLite extends StatelessWidget {
  const MarkdownLite(this.text, {super.key});
  final String text;

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

    for (final raw in text.split('\n')) {
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

  static TextSpan _inline(String s, TextStyle base, Tokens t) {
    final spans = <InlineSpan>[];
    final re = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`');
    var pos = 0;
    for (final m in re.allMatches(s)) {
      if (m.start > pos) spans.add(TextSpan(text: s.substring(pos, m.start)));
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
    if (pos < s.length) spans.add(TextSpan(text: s.substring(pos)));
    return TextSpan(style: base, children: spans);
  }
}
