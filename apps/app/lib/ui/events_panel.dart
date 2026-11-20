import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/event_rules.dart';
import '../state/note_drag.dart';
import 'collapsible_section.dart';
import 'drag_drop.dart';
import 'event_menu.dart';
import 'parts.dart';
import 'side_panel.dart';
import 'theme.dart';

/// The Events side panel section: an agenda of the Space's events. Today and
/// Tomorrow, Upcoming (the rest of the next 30 days, recurring events
/// expanded) and a collapsible Past (the last 30 days). A row opens the event
/// like a note (peek or main, per the open setting). [onPick] runs after an
/// open, to close the narrow sheet.
class EventsPanel extends StatelessWidget {
  const EventsPanel({super.key, required this.state, this.onPick, this.now});
  final AppState state;
  final VoidCallback? onPick;

  /// Clock override for tests.
  final DateTime? now;

  static const upcomingDays = 30;
  static const pastDays = 30;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final clock = now ?? DateTime.now();
        final groups = state.upcomingOccurrences(clock, upcomingDays);
        List<EventOccurrence> of(Set<String> ids) => [
          for (final g in groups)
            if (ids.contains(g.id)) ...g.items,
        ];
        final sections = <(String, String, List<EventOccurrence>)>[
          ('today', 'Today', of({'today'})),
          ('tomorrow', 'Tomorrow', of({'tomorrow'})),
          ('upcoming', 'Upcoming', of({'week', 'later'})),
          ('past', 'Past', state.pastOccurrences(clock, pastDays)),
        ];
        final shown = sections.any((s) => s.$3.isNotEmpty);
        return SidePanelFrame(
          key: const Key('events-panel'),
          title: const SidePanelTitle('Events'),
          actions: state.eventsEditable
              ? IconAction(
                  compact: true,
                  key: const Key('new-event'),
                  tooltip: 'New event',
                  icon: FLucideIcons.plus,
                  onPress: () async {
                    final uid = await showNewEventDialog(context, state);
                    if (uid == null) return;
                    await state.clickEvent(uid);
                    onPick?.call();
                  },
                )
              : null,
          body: ListView(
            key: const Key('events-view'),
            padding: EdgeInsets.fromLTRB(
              t.space.lg,
              t.space.md,
              t.space.lg,
              t.space.huge,
            ),
            children: [
              if (state.events.isEmpty)
                _Note('No events yet', key: const Key('events-empty'))
              else if (!shown)
                _Note('Nothing in sight', key: const Key('events-none')),
              for (final s in sections)
                if (s.$3.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: t.space.md),
                    child: CollapsibleSection(
                      id: 'events-${s.$1}',
                      title: s.$2,
                      upper: false,
                      count: s.$3.length,
                      prefs: state.prefs,
                      prefKey: 'davdart.events.${s.$1}.collapsed.v1',
                      headerPadding: EdgeInsets.all(t.space.xs),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final o in s.$3)
                            EventRow(
                              key: eventRowKey(o),
                              state: state,
                              occurrence: o,
                              showDay: s.$1 == 'upcoming' || s.$1 == 'past',
                              onOpen: onPick,
                            ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

/// The key of an agenda row: `event-row-<uid>`, with `@<yyyymmdd>` added for
/// a repeating event (each of its occurrences has a row).
Key eventRowKey(EventOccurrence o) {
  final s = o.start;
  final day =
      '${s.year}${s.month.toString().padLeft(2, '0')}'
      '${s.day.toString().padLeft(2, '0')}';
  return Key(
    o.event.isRecurring
        ? 'event-row-${o.event.uid}@$day'
        : 'event-row-${o.event.uid}',
  );
}

/// One occurrence as a row: time (or "All day", with the day above it in the
/// Upcoming and Past lists), title and location, a repeat marker. A cancelled
/// event is struck through. Click opens it per the "open in" setting, right
/// click opens the event menu, and it drags onto a Space.
class EventRow extends StatelessWidget {
  const EventRow({
    super.key,
    required this.state,
    required this.occurrence,
    this.showDay = false,
    this.onOpen,
  });
  final AppState state;
  final EventOccurrence occurrence;
  final bool showDay;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final o = occurrence;
    final uid = o.event.uid;
    final selected = state.peekUid == uid || state.mainEventUid == uid;
    final muted = t.type.captionStyle.copyWith(color: t.muted);
    final cancelled = o.isCancelled;
    return EventContextMenu(
      state: state,
      uid: uid,
      onOpen: onOpen,
      child: NoteDraggable(
        uid: uid,
        source: NoteDragSource.list,
        label: o.summary,
        child: FTappable(
          onPress: () {
            state.clickEvent(uid);
            onOpen?.call();
          },
          child: Container(
            color: selected ? t.selected : null,
            padding: EdgeInsets.symmetric(
              horizontal: t.space.xs,
              vertical: t.space.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: t.sizes.eventTime,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showDay)
                        Text(
                          dayLabel(o.start).split(' ').take(2).join(' '),
                          key: Key('event-day-$uid'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: muted,
                        ),
                      Text(
                        o.allDay ? 'All day' : timeLabel(o.start),
                        key: Key('event-time-$uid'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: t.space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        o.summary.isEmpty ? '(no title)' : o.summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: cancelled
                            ? TextStyle(
                                color: t.muted,
                                decoration: TextDecoration.lineThrough,
                              )
                            : null,
                      ),
                      if (o.location.isNotEmpty)
                        Text(
                          o.location,
                          key: Key('event-location-$uid'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: muted,
                        ),
                    ],
                  ),
                ),
                if (o.event.isRecurring) ...[
                  SizedBox(width: t.space.sm),
                  Padding(
                    padding: EdgeInsets.only(top: t.space.xxs),
                    child: Icon(
                      FLucideIcons.repeat,
                      key: Key('event-repeat-$uid'),
                      size: t.icons.sm,
                      color: t.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Padding(
      padding: EdgeInsets.all(t.space.md),
      child: Text(text, style: t.type.captionStyle.copyWith(color: t.muted)),
    );
  }
}
