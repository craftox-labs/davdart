import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import 'parts.dart';
import 'side_panel.dart';
import 'theme.dart';

/// The Events side panel section. A placeholder for now: header with a
/// disabled "New event" action and an empty state.
///
/// SEAM for the events work: replace the empty-state body below with an
/// agenda list (Today, Tomorrow, Upcoming, Past) once the VEVENT core and
/// app state exist, and enable the header action. The panel takes no data
/// yet on purpose; add the AppState (or event list) parameter then.
class EventsPanel extends StatelessWidget {
  const EventsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return SidePanelFrame(
      key: const Key('events-panel'),
      title: const SidePanelTitle('Events'),
      actions: const IconAction(
        compact: true,
        key: Key('new-event'),
        tooltip: 'New event',
        icon: FLucideIcons.plus,
        onPress: null,
      ),
      // Seam: the agenda list goes here.
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: t.space.lg),
        child: Padding(
          padding: EdgeInsets.all(t.space.md),
          child: Text(
            'No events yet',
            key: const Key('events-empty'),
            style: t.type.captionStyle.copyWith(color: t.muted),
          ),
        ),
      ),
    );
  }
}
