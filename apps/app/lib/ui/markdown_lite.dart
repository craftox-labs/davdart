import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';

/// Small renderer for the note text the planning notes use: `#` headings,
/// `-` lists, numbered lists, `**bold**`, `` `code` `` and paragraphs.
class MarkdownLite extends StatelessWidget {
  const MarkdownLite(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<TokensTheme>()!.tokens;
    final base = Theme.of(context).textTheme.bodyMedium!.copyWith(color: t.fg);
    final out = <Widget>[];
    final para = <String>[];

    void flush() {
      if (para.isEmpty) return;
      out.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
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
        final size = [20.0, 17.0, 15.0, 14.0][h.group(1)!.length - 1];
        out.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Text.rich(
              _inline(
                h.group(2)!,
                base.copyWith(fontSize: size, fontWeight: FontWeight.w600),
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
            padding: const EdgeInsets.only(left: 6, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 22, child: Text(marker, style: base)),
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
        spans.add(
          TextSpan(
            text: m.group(1),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: m.group(2),
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: (base.fontSize ?? 14) - 1,
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

/// Carries [Tokens] through the widget tree.
class TokensTheme extends ThemeExtension<TokensTheme> {
  const TokensTheme(this.tokens);
  final Tokens tokens;

  @override
  TokensTheme copyWith({Tokens? tokens}) => TokensTheme(tokens ?? this.tokens);

  @override
  TokensTheme lerp(ThemeExtension<TokensTheme>? other, double t) =>
      other is TokensTheme && t >= 0.5 ? other : this;
}
