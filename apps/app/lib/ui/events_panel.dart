import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/event_rules.dart';
import '../state/task_rules.dart';
import '../state/key_nav.dart';
import '../state/note_drag.dart';
import 'collapsible_section.dart';
import 'drag_drop.dart';
import 'key_nav_ui.dart';
import 'event_menu.dart';
import 'panel_tags_drawer.dart';
import 'parts.dart';
import 'side_panel.dart';
import 'empty_state.dart';
import 'section_label.dart';
import 'surface.dart';
import 'task_menu.dart';
import 'task_parts.dart';
import 'theme.dart';
import 'overflow_tip.dart';

/// The Calendar side panel section (events data; the name says Calendar): an agenda of the Space's events. Today and
/// Tomorrow, Upcoming (the rest of the next 30 days, recurring events
/// expanded) and a collapsible Past (the last 30 days). A row opens the event
/// like a note (peek or main, per the open setting). [onPick] runs after an
/// open, to close the narrow sheet.
class EventsPanel extends StatelessWidget {
  const EventsPanel({
    super.key,
    required this.state,
    this.onPick,
    this.now,
    this.scoped = false,
  });
  final AppState state;
  final VoidCallback? onPick;

  /// A project tab's Calendar shows the open scope's events; the Personal
  /// section (the default) shows the individual's own.
  final bool scoped;

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
        final groups = scoped
            ? state.upcomingOccurrences(clock, upcomingDays)
            : state.upcomingPersonalOccurrences(clock, upcomingDays);
        List<EventOccurrence> of(Set<String> ids) => [
          for (final g in groups)
            if (ids.contains(g.id)) ...g.items,
        ];
        final sections = <(String, String, List<EventOccurrence>)>[
          ('today', 'Today', of({'today'})),
          ('tomorrow', 'Tomorrow', of({'tomorrow'})),
          ('upcoming', 'Upcoming', of({'week', 'later'})),
          (
            'past',
            'Past',
            scoped
                ? state.pastOccurrences(clock, pastDays)
                : state.pastPersonalOccurrences(clock, pastDays),
          ),
        ];
        // Dated tasks ride along in the agenda as markers (the Calendar is
        // events first; a full grid comes later).
        final today0 = wallDay(wallNow(clock));
        final tasks = <String, List<Task>>{
          'today': [],
          'tomorrow': [],
          'upcoming': [],
          'past': [],
        };
        // The Tasks panel's tag filter and the scope apply here too (the
        // Calendar's own tag filter is for events).
        final taskSource = scoped
            ? state.filteredTasks
            : state.filteredPersonalTasks;
        for (final k in taskSource) {
          if (k.isClosed) continue;
          final day = taskDueDay(k);
          if (day == null) continue;
          final days = day.difference(today0).inDays;
          if (days.abs() > upcomingDays) continue;
          final group = days < 0
              ? 'past'
              : days == 0
              ? 'today'
              : days == 1
              ? 'tomorrow'
              : 'upcoming';
          tasks[group]!.add(k);
        }
        final shown = sections.any(
          (s) => s.$3.isNotEmpty || tasks[s.$1]!.isNotEmpty,
        );
        // Home's picked day (the day the grid beside this panel circles) is
        // pinned above the agenda: its loose events and dated tasks, and its
        // own add buttons. The rows are a quick look and stay out of the
        // panel's keyboard list, which the agenda below already fills.
        final homeDay = scoped ? null : state.homeDay;
        final pinned = homeDay == null
            ? null
            : bucketByDay(
                // The individual's own loose items, the seam Home's grid
                // draws from (see AppState.isMine).
                events: [
                  for (final e in state.filteredPersonalEvents)
                    if (state.isMine(e)) e,
                ],
                tasks: [
                  for (final k in state.filteredPersonalTasks)
                    if (state.isMine(k)) k,
                ],
                from: homeDay,
                to: homeDay.add(const Duration(days: 1)),
              )[homeDay];
        final pinnedAdds = <Widget>[
          if (homeDay != null && state.eventsEditable)
            IconAction(
              compact: true,
              key: const Key('calendar-day-add-event'),
              tooltip: 'New event',
              icon: FLucideIcons.calendarPlus,
              onPress: () async {
                final uid = await showNewEventDialog(
                  context,
                  state,
                  day: homeDay,
                  personal: true,
                );
                if (uid == null) return;
                await state.clickEvent(uid);
                onPick?.call();
              },
            ),
          if (homeDay != null && state.tasksEditable)
            IconAction(
              compact: true,
              key: const Key('calendar-day-add-task'),
              tooltip: 'New task',
              icon: FLucideIcons.listPlus,
              onPress: () => showNewTaskDialog(
                context,
                state,
                due: dueOfDay(homeDay),
                personal: true,
              ),
            ),
        ];
        final dayBlock = homeDay == null
            ? null
            : Padding(
                padding: EdgeInsets.only(top: t.space.md),
                child: Column(
                  key: const Key('calendar-day-pin'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionLabel(
                      dayLabel(homeDay, clock),
                      upper: false,
                      action: pinnedAdds.isEmpty
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: pinnedAdds,
                            ),
                    ),
                    SizedBox(height: t.space.xs),
                    if (pinned == null || pinned.isEmpty)
                      EmptyState(
                        'Nothing on this day',
                        key: const Key('calendar-day-pin-empty'),
                        padding: EdgeInsets.all(t.space.md),
                      )
                    else ...[
                      for (final o in pinned.events)
                        EventRow(
                          key: Key('calendar-pin-${eventRowId(o)}'),
                          state: state,
                          occurrence: o,
                          onOpen: onPick,
                        ),
                      for (final k in pinned.tasks)
                        TaskDueRow(
                          key: Key('calendar-pin-task-${k.task.uid}'),
                          state: state,
                          task: k.task,
                          onOpen: onPick,
                        ),
                    ],
                  ],
                ),
              );
        state.nav.publish('events', [
          for (final s in sections) ...[
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
            for (final k in tasks[s.$1]!)
              NavEntry(
                'task-row-${k.uid}',
                uid: k.uid,
                hidden: () =>
                    state.prefs?.read('davdart.events.${s.$1}.collapsed.v1') ==
                    'true',
                open: (mode) async {
                  await state.openTask(k.uid, mode: mode);
                  onPick?.call();
                },
              ),
          ],
        ]);
        return SidePanelFrame(
          key: const Key('events-panel'),
          title: const SidePanelTitle('Calendar'),
          actions: state.eventsEditable
              ? IconAction(
                  compact: true,
                  key: const Key('new-event'),
                  tooltip: 'New event',
                  icon: FLucideIcons.plus,
                  onPress: () async {
                    final uid = await showNewEventDialog(
                      context,
                      state,
                      personal: !scoped,
                    );
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
                ?dayBlock,
                // Nothing to list at all: no events and no dated tasks
                // (either would be shown below).
                if ((scoped
                            ? state.filteredEvents
                            : state.filteredPersonalEvents)
                        .isEmpty &&
                    tasks.values.every((l) => l.isEmpty))
                  EmptyState(
                    'No events yet',
                    key: const Key('events-empty'),
                    padding: EdgeInsets.all(t.space.md),
                  )
                else if (!shown)
                  EmptyState(
                    'Nothing in sight',
                    key: const Key('events-none'),
                    padding: EdgeInsets.all(t.space.md),
                  ),
                for (final s in sections)
                  if (s.$3.isNotEmpty || tasks[s.$1]!.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: t.space.md),
                      child: CollapsibleSection(
                        id: 'events-${s.$1}',
                        title: s.$2,
                        upper: false,
                        count: s.$3.length + tasks[s.$1]!.length,
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
                            for (final k in tasks[s.$1]!)
                              NavRow(
                                key: ValueKey('nav-task-row-${k.uid}'),
                                nav: state.nav,
                                list: 'events',
                                id: 'task-row-${k.uid}',
                                child: TaskDueRow(
                                  key: Key('task-row-${k.uid}'),
                                  state: state,
                                  task: k,
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
          child: Surface(
            selected: selected,
            square: true,
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
                            ? t.type.strikethrough.copyWith(color: t.muted)
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

/// A task with a due date, in the Calendar agenda: the same shape as an event
/// row, marked as a task. Tapping opens the task.
class TaskDueRow extends StatelessWidget {
  const TaskDueRow({
    super.key,
    required this.state,
    required this.task,
    this.showDay = false,
    this.onOpen,
  });
  final AppState state;
  final Task task;
  final bool showDay;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final muted = t.type.captionStyle.copyWith(color: t.muted);
    final day = taskDueDay(task);
    final selected =
        state.peekUid == task.uid || state.selectedTaskUid == task.uid;
    final overdue = isTaskOverdue(task, DateTime.now());
    return FTappable(
      onPress: () {
        state.clickTask(task.uid);
        onOpen?.call();
      },
      child: Surface(
        selected: selected,
        square: true,
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
                  if (showDay && day != null)
                    OverflowTip(
                      dayLabel(day).split(' ').take(2).join(' '),
                      textKey: Key('task-day-${task.uid}'),
                      style: muted,
                    ),
                  // The due time when the task has one, else the word.
                  OverflowTip(
                    task.due != null && !task.due!.allDay
                        ? timeLabel(task.due!.localDay ?? day ?? DateTime.now())
                        : 'Due',
                    textKey: Key('task-time-${task.uid}'),
                    style: overdue
                        ? muted.copyWith(color: t.statusBlocked)
                        : muted,
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
                    task.summary.isEmpty ? '(no title)' : task.summary,
                    style: t.type.bodyStyle,
                  ),
                  Row(
                    children: [
                      Icon(
                        FLucideIcons.listChecks,
                        size: t.icons.sm,
                        color: t.muted,
                      ),
                      SizedBox(width: t.space.xxs),
                      Text('Task', style: muted),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
