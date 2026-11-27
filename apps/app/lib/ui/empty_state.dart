import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'theme.dart';

/// The one empty (and error) message of a list, board or card: [text] in the
/// muted body colour, centred when it stands in for a whole pane ([centered])
/// and inline-sized when it sits in a card row. [error] colours it with
/// [Tokens.error] for a load failure.
class EmptyState extends StatelessWidget {
  const EmptyState(
    this.text, {
    super.key,
    this.centered = false,
    this.error = false,
    this.padding,
  });

  final String text;
  final bool centered;
  final bool error;

  /// Defaults to [SpaceTokens.lg] around a centred state and
  /// [SpaceTokens.xs] above and below an inline one.
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final body = Text(
      text,
      textAlign: centered ? TextAlign.center : null,
      style: (centered ? t.type.bodyStyle : t.type.captionStyle).copyWith(
        color: error ? t.error : t.muted,
      ),
    );
    final padded = Padding(
      padding:
          padding ??
          (centered
              ? EdgeInsets.all(t.space.lg)
              : EdgeInsets.symmetric(vertical: t.space.xs)),
      child: body,
    );
    return centered ? Center(child: padded) : padded;
  }
}
