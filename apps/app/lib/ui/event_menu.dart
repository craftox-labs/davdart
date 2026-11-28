import 'package:davdart/davdart.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/event_rules.dart';
import '../state/tab_state.dart';
import 'event_when.dart';
import 'note_menu.dart';
import 'parts.dart';
import 'property/draft_property_row.dart';
import 'property/option_picker.dart';
import 'property/parent_property_picker.dart'
    show ParentPropertyPicker, projectValueFor;
import 'property/property_defs.dart';
import 'property/property_row.dart' show PropertySection;
import 'property/tag_property_picker.dart';
import 'property/property_dialog.dart';
import 'theme.dart';

/// Right-click (or long-press) menu for an event: open in peek or main, move
/// to a Space, copy the id, delete (confirmed). [surface] adds the tab
/// entries when the menu sits on a tab.
class EventContextMenu extends StatelessWidget {
  const EventContextMenu({
    super.key,
    required this.state,
    required this.uid,
    required this.child,
    this.surface = NoteSurface.entry,
    this.onOpen,
  });
  final AppState state;
  final String uid;
  final Widget child;
  final NoteSurface surface;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => ExclusiveContextMenu(
    menuBuilder: (ctx, controller, _) => _groups(context, ctx, controller),
    child: child,
  );

  /// The actions of the open item's own page (the narrow header's ⋯
  /// sheet): everything but the open and close rows.
  List<FItemGroup> pageGroups(
    BuildContext context,
    BuildContext menuContext,
    FPopoverController c,
  ) => _groups(context, menuContext, c, page: true);

  List<FItemGroup> _groups(
    BuildContext context,
    BuildContext menuContext,
    FPopoverController c, {
    bool page = false,
  }) {
    final event = state.eventById(uid);
    if (event == null) return const [];
    final t = tokensOf(menuContext);
    FItem row(
      String label,
      IconData icon,
      VoidCallback act, {
      Key? key,
      bool afterOpen = false,
    }) => FItem(
      key: key,
      prefix: Icon(icon, size: t.icons.md, color: t.muted),
      title: Text(label),
      onPress: () {
        c.hide();
        act();
        if (afterOpen) onOpen?.call();
      },
    );

    final edit = state.eventsEditable;
    final manage = <NoteMenuItem>[
      if (edit)
        NoteMenuItem(
          Props.moveLabel,
          Props.moveIcon,
          () => showMoveToParentDialog(context, state, uid),
          key: const Key('menu-move-folder'),
        ),
      if (edit && state.spaces.length > 1)
        NoteMenuItem(
          'Move to Space…',
          FLucideIcons.arrowRightToLine,
          () => showMoveEventDialog(context, state, event),
          key: const Key('menu-move-space'),
        ),
      NoteMenuItem(
        'Copy id',
        FLucideIcons.copy,
        () => Clipboard.setData(ClipboardData(text: event.uid)),
        key: const Key('menu-copy-id'),
      ),
    ];
    final tab = DocTab.event(uid);
    return [
      if (!page)
        FItemGroup(
          children: [
            if (!state.narrow)
              row(
                'Open in peek',
                FLucideIcons.panelRight,
                () => state.openEvent(uid, mode: OpenMode.peek),
                key: const Key('menu-open-peek'),
                afterOpen: true,
              ),
            row(
              'Open in main',
              FLucideIcons.squareArrowOutUpRight,
              () => state.openEvent(uid, mode: OpenMode.main),
              key: const Key('menu-open-main'),
              afterOpen: true,
            ),
          ],
        ),
      FItemGroup(children: menuRows(menuContext, c, manage)),
      FItemGroup(
        children: [
          if (surface == NoteSurface.peekTab)
            row(
              'Close peek',
              FLucideIcons.x,
              () => state.guarded(() => state.select(null)),
              key: const Key('menu-close'),
            ),
          if (surface == NoteSurface.mainTab) ...[
            row(
              'Close tab',
              FLucideIcons.x,
              () => state.closeTab(tab),
              key: const Key('menu-close'),
            ),
            if (state.tabs.length > 1)
              row(
                'Close other tabs',
                FLucideIcons.x,
                () => state.closeOtherTabs(tab),
                key: const Key('menu-close-others'),
              ),
            if (state.tabs.isNotEmpty && state.tabs.last != tab)
              row(
                'Close tabs to the right',
                FLucideIcons.x,
                () => state.closeTabsToRight(tab),
                key: const Key('menu-close-right'),
              ),
          ],
          if (edit)
            row(
              'Delete…',
              FLucideIcons.trash2,
              () => confirmDeleteEvent(context, state, event),
              key: const Key('menu-delete'),
            ),
        ],
      ),
    ];
  }
}

/// Asks before deleting an event (a repeating one goes as a whole series).
Future<void> confirmDeleteEvent(
  BuildContext context,
  AppState state,
  Event event,
) {
  return showAppDialog(
    context,
    title: 'Delete event?',
    content: Text(
      event.isRecurring
          ? '"${event.summary}" and all its repeats will be deleted.'
          : '"${event.summary}" will be deleted.',
    ),
    actions: [
      const CancelButton(),
      ActionButton(
        'Delete',
        key: const Key('delete-confirm'),
        onPress: (ctx) {
          Navigator.of(ctx).pop();
          state.deleteEvent(event.uid);
        },
      ),
    ],
  );
}

/// Moves an event to another Space.
Future<void> showMoveEventDialog(
  BuildContext context,
  AppState state,
  Event event,
) {
  final others = [
    for (final s in state.spaces)
      if (s.id != state.currentSpaceId) s,
  ];
  return showAppDialog(
    context,
    title: 'Move "${event.summary}" to…',
    width: tokensOf(context).sizes.dialogSm,
    content: Builder(
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The event goes to the Space you pick. A moved event gets a '
            'new id.',
            style: tokensOf(ctx).type.captionStyle,
          ),
          SizedBox(height: tokensOf(ctx).space.md),
          for (final s in others)
            FItem(
              key: Key('move-to-${s.id}'),
              prefix: Icon(
                s.onServer ? FLucideIcons.cloud : FLucideIcons.folder,
                size: tokensOf(ctx).icons.lg,
              ),
              title: Text(s.name),
              onPress: () {
                Navigator.of(ctx).pop();
                state.moveToSpace(event.uid, s.id);
              },
            ),
        ],
      ),
    ),
    actions: [const CancelButton()],
  );
}

/// The values of the new event dialog (wall-clock fields; all day: the end is
/// the last day).
class _NewEventForm extends ChangeNotifier {
  _NewEventForm(DateTime first)
    : start = first.add(const Duration(hours: 9)),
      end = first.add(const Duration(hours: 10));
  final title = TextEditingController();
  final location = TextEditingController();
  bool allDay = false;
  DateTime start, end;
  String status = '';
  List<String> tags = [];
  String? parent;

  DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  bool get bad => end.isBefore(start);

  void pick({String? status, List<String>? tags, (String?,)? parent}) {
    if (status != null) this.status = status;
    if (tags != null) this.tags = tags;
    if (parent != null) this.parent = parent.$1;
    notifyListeners();
  }

  void setAllDay(bool v) {
    if (v == allDay) return;
    allDay = v;
    if (v) {
      start = _day(start);
      end = _day(end);
      if (end.isBefore(start)) end = start;
    } else {
      start = _day(start).add(const Duration(hours: 9));
      end = start.add(const Duration(hours: 1));
    }
    notifyListeners();
  }

  void setStart(DateTime? date, int? minutes) {
    final len = end.difference(start);
    final mins = allDay ? 0 : minutes ?? start.hour * 60 + start.minute;
    start = (date == null ? _day(start) : _day(date)).add(
      Duration(minutes: mins),
    );
    end = start.add(len);
    notifyListeners();
  }

  void setEnd(DateTime? date, int? minutes) {
    final mins = allDay ? 0 : minutes ?? end.hour * 60 + end.minute;
    end = (date == null ? _day(end) : _day(date)).add(Duration(minutes: mins));
    notifyListeners();
  }

  @override
  void dispose() {
    title.dispose();
    location.dispose();
    super.dispose();
  }
}

/// A small dialog for a new event: title, when (date, all day or start and
/// end time) and location. Resolves to the new event's uid, or null when
/// cancelled. [day] is the date it starts on (default: today); [until] makes
/// it an all-day event to that last day (a range dragged on the calendar).
/// [startMinute] and [endMinute] (wall minutes from midnight of [day]) open it
/// as a timed event on that slot; the end defaults to an hour after the start.
Future<String?> showNewEventDialog(
  BuildContext context,
  AppState state, {
  DateTime? day,
  DateTime? until,
  int? startMinute,
  int? endMinute,
  bool personal = false,
}) {
  final first = wallDay(day ?? wallNow(DateTime.now()));
  final form = _NewEventForm(first);
  if (startMinute != null) {
    // A slot picked on the time grid: wall minutes from the day's midnight.
    form.setStart(first, startMinute);
    form.setEnd(first, endMinute ?? startMinute + 60);
  }
  if (until != null) {
    // The form's all-day end is the last day, so a range needs no arithmetic.
    form.setAllDay(true);
    form.setStart(first, null);
    form.setEnd(wallDay(until), null);
  }
  Future<void> submit(BuildContext ctx) async {
    if (form.title.text.trim().isEmpty || form.bad) return;
    final nav = Navigator.of(ctx);
    final uid = await state.addEvent(
      form.title.text,
      start: form.start,
      end: form.end,
      allDay: form.allDay,
      location: form.location.text,
      parentUid: form.parent,
      tags: form.tags,
      personal: personal,
    );
    if (uid != null && form.status.isNotEmpty) {
      await state.setEventStatus(uid, form.status);
    }
    if (uid != null) nav.pop(uid);
  }

  return showAppDialog<String>(
    context,
    title: 'New event',
    width: tokensOf(context).sizes.dialog,
    content: Builder(
      builder: (ctx) {
        final t = tokensOf(ctx);
        return ListenableBuilder(
          listenable: form,
          builder: (ctx, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: t.space.lg,
            children: [
              field(
                key: const Key('new-event-title'),
                controller: form.title,
                autofocus: true,
                label: 'Title',
                onSubmit: (_) => submit(ctx),
              ),
              EventWhenFields(
                keys: 'new-event',
                allDay: form.allDay,
                start: form.start,
                end: form.end,
                error: form.bad ? 'The end is before the start' : null,
                onAllDay: form.setAllDay,
                onStart: form.setStart,
                onEnd: form.setEnd,
              ),
              field(
                key: const Key('new-event-location'),
                controller: form.location,
                label: 'Location',
                onSubmit: (_) => submit(ctx),
              ),
              PropertySection(
                rows: [
                  DraftPropertyRow(
                    def: Props.status,
                    text: form.status.isEmpty
                        ? null
                        : eventStatusName(form.status),
                    picker: (_, control) => OptionPicker<String>(
                      id: 'new-event-status',
                      value: form.status,
                      options: eventStatusOptions(),
                      onPick: (v) {
                        control.hide();
                        if (v != null) form.pick(status: v);
                      },
                    ),
                  ),
                  DraftPropertyRow(
                    def: Props.labels,
                    text: form.tags.isEmpty ? null : form.tags.join(', '),
                    picker: (_, control) => TagPropertyPicker(
                      id: 'new-event-tags',
                      value: form.tags,
                      suggestions: state.eventTags,
                      onPick: (v) async {
                        form.pick(tags: v);
                        return true;
                      },
                    ),
                  ),
                  DraftPropertyRow(
                    def: Props.parent,
                    text: personal && form.parent == null
                        ? 'Personal'
                        : projectValueFor(
                            state,
                            state.parentOrScope(form.parent),
                          ),
                    picker: (_, control) => ParentPropertyPicker(
                      id: 'new-event-parent',
                      state: state,
                      uid: '',
                      currentParent: (state.parentOrScope(form.parent),),
                      onPick: (v) async {
                        control.hide();
                        form.pick(parent: (v,));
                        return true;
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
    actions: [
      const CancelButton(),
      ActionButton('Add', key: const Key('new-event-add'), onPress: submit),
    ],
  );
}
