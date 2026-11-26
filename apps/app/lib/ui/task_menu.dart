import 'package:davdart/davdart.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/tab_state.dart';
import 'note_menu.dart';
import 'parts.dart';
import 'task_detail.dart' show priorityBucket, priorityOfBucket;
import 'task_parts.dart';
import 'theme.dart';

/// Right-click (or long-press) menu for a task: open in peek or main,
/// complete or reopen, set the due date, move to a Space, delete (confirmed).
/// [surface] adds the tab entries when the menu sits on a main tab.
class TaskContextMenu extends StatelessWidget {
  const TaskContextMenu({
    super.key,
    required this.state,
    required this.uid,
    required this.child,
    this.surface = NoteSurface.entry,
    this.onOpen,
    this.touchMenu = true,
  });
  final bool touchMenu;
  final AppState state;
  final String uid;
  final Widget child;
  final NoteSurface surface;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => ExclusiveContextMenu(
    touchMenu: touchMenu,
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
    final task = state.taskById(uid);
    if (task == null) return const [];
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

    final edit = state.tasksEditable;
    final blocked =
        !task.isClosed && state.taskCompletionBlockerFor(uid) != null;
    void due(DateTime? day) => state.updateTask(
      uid,
      setDue: true,
      due: day == null ? null : dueOfDay(day, task.due),
    );
    final manage = <NoteMenuItem>[
      if (edit && !blocked)
        NoteMenuItem(
          task.isClosed ? 'Reopen' : 'Complete',
          task.isClosed ? FLucideIcons.circle : FLucideIcons.circleCheck,
          () => state.toggleTask(uid),
          key: const Key('menu-task-toggle'),
        ),
      if (edit)
        NoteMenuItem(
          'Set status',
          FLucideIcons.circleDot,
          () {},
          key: const Key('menu-task-status'),
          children: [
            for (final s in const [
              'backlog',
              'todo',
              'doing',
              'blocked',
              'review',
              'done',
              'canceled',
            ])
              NoteMenuItem(
                s,
                FLucideIcons.circleDot,
                () => state.setTaskStatus(uid, s),
                key: Key('menu-task-status-$s'),
                selected: task.boardStatus == s,
              ),
          ],
        ),
      if (edit)
        NoteMenuItem(
          'Set due',
          FLucideIcons.calendar,
          () {},
          key: const Key('menu-task-due'),
          children: [
            NoteMenuItem(
              'Today',
              FLucideIcons.calendarCheck,
              () => due(dayFromToday(0)),
              key: const Key('menu-task-due-today'),
            ),
            NoteMenuItem(
              'Tomorrow',
              FLucideIcons.calendarPlus,
              () => due(dayFromToday(1)),
              key: const Key('menu-task-due-tomorrow'),
            ),
            NoteMenuItem(
              'Next week',
              FLucideIcons.calendarRange,
              () => due(dayFromToday(7)),
              key: const Key('menu-task-due-week'),
            ),
            NoteMenuItem('Pick a date…', FLucideIcons.calendar, () async {
              final d = await showTaskDateDialog(
                context,
                initial: dueDate(task),
              );
              if (d != null) due(d);
            }, key: const Key('menu-task-due-pick')),
            if (task.due != null)
              NoteMenuItem(
                'Clear due date',
                FLucideIcons.calendarX,
                () => due(null),
                key: const Key('menu-task-due-clear'),
              ),
          ],
        ),
      if (edit)
        NoteMenuItem(
          'Set priority',
          FLucideIcons.flag,
          () {},
          key: const Key('menu-priority'),
          children: [
            for (final b in const ['none', 'high', 'medium', 'low'])
              NoteMenuItem(
                b == 'none'
                    ? 'No priority'
                    : b[0].toUpperCase() + b.substring(1),
                b == 'none' ? FLucideIcons.circle : FLucideIcons.flag,
                () => state.setTaskPriority(uid, priorityOfBucket(b)),
                key: Key('menu-priority-$b'),
                selected: priorityBucket(task.priority) == b,
              ),
          ],
        ),
      if (edit && state.spaces.length > 1)
        NoteMenuItem(
          'Move to space…',
          FLucideIcons.arrowRightToLine,
          () => showMoveTaskDialog(context, state, task),
          key: const Key('menu-move-space'),
        ),
      NoteMenuItem(
        'Copy id',
        FLucideIcons.copy,
        () => Clipboard.setData(ClipboardData(text: task.uid)),
        key: const Key('menu-copy-id'),
      ),
    ];
    final tab = DocTab.task(uid);
    return [
      if (!page)
        FItemGroup(
          children: [
            if (!state.narrow)
              row(
                'Open in peek',
                FLucideIcons.panelRight,
                () => state.openTask(uid, mode: OpenMode.peek),
                key: const Key('menu-open-peek'),
                afterOpen: true,
              ),
            row(
              'Open in main',
              FLucideIcons.squareArrowOutUpRight,
              () => state.openTask(uid, mode: OpenMode.main),
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
              () => confirmDeleteTask(context, state, task),
              key: const Key('menu-delete'),
            ),
        ],
      ),
    ];
  }
}

/// Asks before deleting a task; its sub-tasks and sub-notes move up.
Future<void> confirmDeleteTask(
  BuildContext context,
  AppState state,
  Task task,
) {
  return showAppDialog(
    context,
    title: 'Delete task?',
    content: Text(
      '"${task.summary}" will be deleted. Tasks and notes under it move up.',
    ),
    actions: [
      const CancelButton(),
      ActionButton(
        'Delete',
        key: const Key('delete-confirm'),
        onPress: (ctx) {
          Navigator.of(ctx).pop();
          state.deleteTask(task.uid);
        },
      ),
    ],
  );
}

/// A small calendar dialog; resolves to the picked day (UTC midnight) or null.
Future<DateTime?> showTaskDateDialog(
  BuildContext context, {
  DateTime? initial,
}) {
  return showAppDialog<DateTime>(
    context,
    title: 'Due date',
    width: tokensOf(context).sizes.dialogLg,
    content: Builder(
      builder: (ctx) => FittedBox(
        // The calendar needs its own width; narrow dialogs scale it down.
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: tokensOf(ctx).sizes.dialogMd,
          child: FCalendar.grid(
            key: const Key('task-date-calendar'),
            selectionControl: FDateSelectionControl.managedSingle(
              initial: initial,
              onChange: (d) {
                if (d != null) {
                  Navigator.of(ctx).pop(DateTime.utc(d.year, d.month, d.day));
                }
              },
            ),
          ),
        ),
      ),
    ),
    actions: [const CancelButton()],
  );
}

/// Moves a task (and the tasks under it) to another Space.
Future<void> showMoveTaskDialog(
  BuildContext context,
  AppState state,
  Task task,
) {
  final others = [
    for (final s in state.spaces)
      if (s.id != state.currentSpaceId) s,
  ];
  return showAppDialog(
    context,
    title: 'Move "${task.summary}" to…',
    width: tokensOf(context).sizes.dialogSm,
    content: Builder(
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The task and the tasks under it go to the top level of the '
            'space you pick. Moved tasks get new ids.',
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
                state.moveToSpace(task.uid, s.id);
              },
            ),
        ],
      ),
    ),
    actions: [const CancelButton()],
  );
}

/// Asks for a title and adds a task under [parentUid] (a note or task).
Future<void> showNewTaskDialog(
  BuildContext context,
  AppState state, {
  String? parentUid,
  ICalDate? due,
  bool personal = false,
}) {
  final title = TextEditingController();
  void submit(BuildContext ctx) {
    final text = title.text;
    if (text.trim().isEmpty) return;
    Navigator.of(ctx).pop();
    state.addTask(text, parentUid: parentUid, due: due, personal: personal);
  }

  return showAppDialog(
    context,
    title: 'New task',
    width: tokensOf(context).sizes.dialog,
    content: Builder(
      builder: (ctx) => field(
        key: const Key('new-task-title'),
        controller: title,
        autofocus: true,
        hint: 'Title',
        onSubmit: (_) => submit(ctx),
      ),
    ),
    actions: [
      const CancelButton(),
      ActionButton('Add', key: const Key('new-task-add'), onPress: submit),
    ],
  );
}
