import 'package:flutter/widgets.dart';

import 'theme.dart';

/// Caps the Home grid at `sizes.contentMax`, left-aligned beyond it.
class ContentCap extends StatelessWidget {
  const ContentCap({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: ConstrainedBox(
      key: const Key('content-cap'),
      constraints: BoxConstraints(maxWidth: tokensOf(context).sizes.contentMax),
      child: child,
    ),
  );
}
