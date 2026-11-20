import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/event_rules.dart';
import '../state/key_nav.dart';
import '../state/note_drag.dart';
import 'collapsible_section.dart';
import 'drag_drop.dart';
import 'key_nav_ui.dart';
import 'event_menu.dart';
import 'panel_tags_drawer.dart';
import 'parts.dart';
import 'side_panel.dart';
import 'theme.dart';
import 'overflow_tip.dart';

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
        state.nav.publish('events', [
          for (final s in sections)
            for (final o in s.$3)
              NavEntry(
                eventRowId(o),
                uid: o.event.uid,
                hidden: () =>
                    state.prefs?.read('davdart.events.${s.$1}.collapsed.v1') ==
                    'true',
                open: (mode) async {
                  await state.openNote(o.event.uid, mode: mode);
                  onPick?.call();
                },
              ),
        ]);
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
          body: PanelTagsDrawer(
            keyPrefix: 'events-tags',
            tags: state.eventTags,
            selected: state.eventTagFilter,
            onSelect: state.setEventTagFilter,
            expanded: state.eventTagsExpanded,
            onExpandedChange: state.setEventTagsOpen,
            body: ListView(
              key: const Key('events-view'),
              scrollCacheExtent: navCacheExtent,
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
                              NavRow(
                                key: ValueKey('nav-${eventRowId(o)}'),
                                nav: state.nav,
                                list: 'events',
                                id: eventRowId(o),
                                child: EventRow(
                                  key: eventRowKey(o),
                                  state: state,
                                  occurrence: o,
                                  showDay: s.$1 == 'upcoming' || s.$1 == 'past',
                                  onOpen: onPick,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The key of an agenda row: `event-row-<uid>`, with `@<yyyymmddThhmm>` of
/// the start added for a repeating event (each of its occurrences has a row;
/// an override moved onto another instance's day still differs by time). An
/// occurrence replaced by an override and the one it was moved onto cannot
/// share a start, but an exact tie gets the original instance id added.
Key eventRowKey(EventOccurrence o) => Key(eventRowId(o));

/// The string inside [eventRowKey].
String eventRowId(EventOccurrence o) {
  if (!o.event.isRecurring) return 'event-row-${o.event.uid}';
  final s = o.start;
  String t(int n) => n.toString().padLeft(2, '0');
  final at = '${s.year}${t(s.month)}${t(s.day)}T${t(s.hour)}${t(s.minute)}';
  final id = o.isOverride ? '#${o.recurrenceId?.value ?? ''}' : '';
  return 'event-row-${o.event.uid}@$at$id';
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
                        OverflowTip(
                          dayLabel(o.start).split(' ').take(2).join(' '),
                          textKey: Key('event-day-$uid'),
                          style: muted,
                        ),
                      OverflowTip(
                        o.allDay ? 'All day' : timeLabel(o.start),
                        textKey: Key('event-time-$uid'),
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
                      OverflowTip(
                        o.summary.isEmpty ? '(no title)' : o.summary,
                        style: cancelled
                            ? TextStyle(
                                color: t.muted,
                                decoration: TextDecoration.lineThrough,
                              )
                            : null,
                      ),
                      if (o.location.isNotEmpty)
                        OverflowTip(
                          o.location,
                          textKey: Key('event-location-$uid'),
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
