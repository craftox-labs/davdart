import 'package:flutter/widgets.dart';

import 'theme.dart';

/// Letter drawn in the placeholder logo.
const logoLetter = 'd';

/// The logo slot at the top of the rail: a neutral rounded square with a
/// letter. A placeholder; swap this one widget for the real logo asset later.
/// Not tappable.
class LogoSlot extends StatelessWidget {
  const LogoSlot({super.key});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Container(
      key: const Key('logo-slot'),
      width: t.sizes.railItem,
      height: t.sizes.railItem,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.activeItem,
        borderRadius: BorderRadius.circular(t.radii.control),
      ),
      child: Text(
        logoLetter,
        style: t.type.headingStyle.copyWith(color: t.onActiveItem),
      ),
    );
  }
}
