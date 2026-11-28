import 'package:davdart/davdart.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/tab_state.dart';
import 'note_menu.dart';
import 'parts.dart';
import 'chips.dart' show StatusDot;
import '../state/event_rules.dart' show dayLabel;
import 'property/date_property_picker.dart';
import 'property/draft_property_row.dart';
import 'property/option_picker.dart';
import 'property/parent_property_picker.dart'
    show ParentPropertyPicker, projectValueFor;
import 'property/property_defs.dart';
import 'property/property_row.dart' show PropertySection;
import 'property/tag_property_picker.dart';
import 'property/property_dialog.dart';
import 'property/property_menu.dart';
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
    final manage = <NoteMenuItem>[
      if (edit && !blocked)
        NoteMenuItem(
          task.isClosed ? 'Reopen' : 'Complete',
          task.isClosed ? FLucideIcons.circle : FLucideIcons.circleCheck,
          () => state.toggleTask(uid),
          key: const Key('menu-task-toggle'),
        ),
      if (edit)
        optionMenuItem<String>(
          Props.status,
          key: const Key('menu-task-status'),
          optionPrefix: 'menu-task-status',
          options: taskStatusOptions(blocked: blocked),
          value: task.boardStatus,
          onPick: (v) => state.setTaskStatus(uid, v!),
        ),
      if (edit)
        dialogMenuItem(
          Props.due,
          key: const Key('menu-task-due'),
          onPress: () => showTaskDueDialog(context, state, task),
        ),
      if (edit)
        optionMenuItem<String>(
          Props.priority,
          key: const Key('menu-priority'),
          optionPrefix: 'menu-priority',
          options: priorityOptions<String>((b) => b),
          value: priorityBucket(task.priority) == 'none'
              ? null
              : priorityBucket(task.priority),
          noneLabel: Props.noPriority,
          onPick: (v) => state.setTaskPriority(uid, priorityOfBucket(v)),
        ),
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

/// The due date in the shared date picker's dialog.
Future<void> showTaskDueDialog(
  BuildContext context,
  AppState state,
  Task task,
) => showDateDialog(
  context,
  def: Props.due,
  value: task.due == null ? null : dueDate(task),
  onPick: (d) =>
      state.setTaskDue(task.uid, d == null ? null : dueOfDay(d, task.due)),
);

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
            'Space you pick. Moved tasks get new ids.',
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

/// Asks for a title and adds a task under [parentUid] (a note or task). The
/// properties are the shared rows and pickers of the task page (status,
/// priority, due, start, labels, belongs to), applied once the task exists.
Future<void> showNewTaskDialog(
  BuildContext context,
  AppState state, {
  String? parentUid,
  ICalDate? due,
  bool personal = false,
}) {
  final title = TextEditingController();
  var status = 'todo';
  int? priority;
  var dueDay = due?.localDay;
  DateTime? startDay;
  var tags = <String>[];
  var parent = parentUid;
  Future<void> submit(BuildContext ctx) async {
    final text = title.text;
    if (text.trim().isEmpty) return;
    Navigator.of(ctx).pop();
    final uid = await state.addTask(
      text,
      parentUid: parent,
      due: dueDay == null ? null : dueOfDay(dueDay!, due),
      priority: priority,
      tags: tags,
      personal: personal,
    );
    if (uid == null) return;
    if (status != 'todo') {
      await state.setTaskStatus(uid, status, undoable: false);
    }
    if (startDay != null) await state.setTaskStart(uid, dueOfDay(startDay!));
  }

  return showAppDialog(
    context,
    title: 'New task',
    width: tokensOf(context).sizes.dialog,
    content: Builder(
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final t = tokensOf(ctx);
          final now = DateTime.now();
          Widget pickDate(
            PropertyDef def,
            DateTime? day,
            void Function(DateTime?) put,
          ) => DraftPropertyRow(
            def: def,
            text: day == null ? null : dayLabel(day, now),
            picker: (_, control) => DatePropertyPicker(
              id: 'new-${def.id}',
              value: day,
              onPick: (d) {
                control.hide();
                set(() => put(d));
              },
            ),
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: t.space.lg,
            children: [
              field(
                key: const Key('new-task-title'),
                controller: title,
                autofocus: true,
                hint: 'Title',
                onSubmit: (_) => submit(ctx),
              ),
              PropertySection(
                rows: [
                  DraftPropertyRow(
                    def: Props.status,
                    value: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: t.space.sm,
                      children: [
                        StatusDot(status),
                        Flexible(
                          child: Text(
                            statusWordOf(status),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.type.bodyStyle,
                          ),
                        ),
                      ],
                    ),
                    picker: (_, control) => OptionPicker<String>(
                      id: 'new-status',
                      value: status,
                      options: taskStatusOptions(),
                      onPick: (v) {
                        control.hide();
                        if (v != null) set(() => status = v);
                      },
                    ),
                  ),
                  DraftPropertyRow(
                    def: Props.priority,
                    text: priorityBucket(priority) == 'none'
                        ? null
                        : priorityText(priorityBucket(priority)),
                    picker: (_, control) => OptionPicker<int>(
                      id: 'new-priority',
                      value: priority,
                      clearable: true,
                      clearLabel: Props.noPriority,
                      options: priorityOptions<int>(
                        (b) => priorityOfBucket(b)!,
                      ),
                      onPick: (v) {
                        control.hide();
                        set(() => priority = v);
                      },
                    ),
                  ),
                  pickDate(Props.due, dueDay, (d) => dueDay = d),
                  pickDate(Props.start, startDay, (d) => startDay = d),
                  DraftPropertyRow(
                    def: Props.labels,
                    text: tags.isEmpty ? null : tags.join(', '),
                    picker: (_, control) => TagPropertyPicker(
                      id: 'new-tags',
                      value: tags,
                      suggestions: state.taskTags,
                      onPick: (v) async {
                        set(() => tags = v);
                        return true;
                      },
                    ),
                  ),
                  DraftPropertyRow(
                    def: Props.parent,
                    text: personal && parent == null
                        ? 'Personal'
                        : projectValueFor(state, state.parentOrScope(parent)),
                    picker: (_, control) => ParentPropertyPicker(
                      id: 'new-parent',
                      state: state,
                      uid: '',
                      currentParent: (state.parentOrScope(parent),),
                      onPick: (v) async {
                        control.hide();
                        set(() => parent = v);
                        return true;
                      },
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    ),
    actions: [
      const CancelButton(),
      ActionButton('Add', key: const Key('new-task-add'), onPress: submit),
    ],
  );
}
