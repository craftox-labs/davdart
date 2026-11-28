import 'dart:async';

import 'package:davdart/davdart.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/key_nav.dart';
import 'chips.dart';
import 'edit_note_dialog.dart' show confirmDeleteNote;
import 'markdown_lite.dart';
import 'parts.dart';
import 'card_box.dart';
import 'property/inline_text.dart';
import 'property/option_picker.dart';
import 'property/parent_property_picker.dart';
import 'property/property_defs.dart';
import 'property/property_picker.dart';
import 'property/property_row.dart';
import 'property/tag_property_picker.dart';
import 'theme.dart';
import 'move_space_dialog.dart';
import 'mobile_item.dart';
import 'note_editor.dart';
import 'note_menu.dart';
import 'event_detail.dart';
import 'task_detail.dart';

class DetailView extends StatelessWidget {
  const DetailView({
    super.key,
    required this.state,
    required this.uid,
    required this.onClose,
    this.full = false,
    this.inHeader = false,
    this.area = NavArea.main,
  });
  final AppState state;

  /// The note shown (the peek note, or the main tab's note).
  final String uid;
  final VoidCallback onClose;

  /// This is the main area's full page (no Back or breadcrumb), not the peek
  /// pane.
  final bool full;

  /// The shell's header row carries this pane's tab with its controls, so the
  /// pane leaves Back out.
  final bool inHeader;

  /// The pane showing this page: its keyboard scrolling goes to it.
  final NavArea area;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final note = state.tree.find(uid)?.note;
    if (note == null) {
      if (state.eventById(uid) != null) {
        return EventDetail(
          state: state,
          uid: uid,
          onClose: onClose,
          full: full,
          inHeader: inHeader,
          area: area,
        );
      }
      if (state.taskById(uid) == null) return const SizedBox.shrink();
      return TaskDetail(
        state: state,
        uid: uid,
        onClose: onClose,
        full: full,
        inHeader: inHeader,
        area: area,
      );
    }
    final p = PlanItem.fromNote(note);
    final draft = state.draftFor(uid);
    final edit = state.editable;
    final folder = AppState.isFolder(note);
    // Narrow: edit/preview toggle and ⋯ in the header; edits autosave.
    final mobile = narrowLayout(context);
    final status = boardOrder.contains(p.status) ? p.status : null;
    final priority = p.priorityWord;
    final tags = state.noteTagsOf(note);
    final tagSuggestions = ({
      for (final n in state.notes)
        for (final g in state.noteTagsOf(n))
          if (g.isNotEmpty) g,
    }.toList()..sort());

    final statusValue = status == null
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatusDot(status),
              SizedBox(width: t.space.sm),
              Flexible(
                child: Text(
                  statusWordOf(status),
                  key: const Key('note-status-text'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.type.bodyStyle,
                ),
              ),
            ],
          );

    /// The properties, flat rows like a task's: a pick saves at once (with
    /// Undo) through the same writes the board and the menus use. A read-only
    /// Space reads them as plain text.
    final rows = <Widget>[
      if (!folder)
        if (edit)
          PropertyPicker<String>(
            id: Props.status.id,
            uid: uid,
            state: state,
            icon: Props.status.icon,
            label: Props.status.label,
            value: statusValue,
            picker: (context, control, apply) => OptionPicker<String>(
              id: Props.status.id,
              value: status,
              clearable: true,
              clearLabel: 'none',
              onPick: (v) {
                control.hide();
                apply(v);
              },
              options: noteStatusOptions(),
            ),
            onPick: (v) async {
              await state.setStatus(uid, v);
              return state.error == null;
            },
          )
        else
          PropertyRow(
            key: const Key('property-status'),
            icon: Props.status.icon,
            label: Props.status.label,
            value: statusValue,
            readOnly: true,
          ),
      if (!folder)
        if (edit)
          PropertyPicker<String>(
            id: Props.priority.id,
            uid: uid,
            state: state,
            icon: Props.priority.icon,
            label: Props.priority.label,
            text: priority,
            picker: (context, control, apply) => OptionPicker<String>(
              id: Props.priority.id,
              value: priority,
              clearable: true,
              clearLabel: Props.noPriority,
              onPick: (v) {
                control.hide();
                apply(v);
              },
              options: priorityOptions<String>((b) => b),
            ),
            onPick: (v) async {
              await state.setNotePriority(uid, v);
              return state.error == null;
            },
          )
        else
          PropertyRow(
            key: const Key('property-priority'),
            icon: Props.priority.icon,
            label: Props.priority.label,
            text: priority,
            readOnly: true,
          ),
      if (edit)
        PropertyPicker<List<String>>(
          id: Props.labels.id,
          uid: uid,
          state: state,
          icon: Props.labels.icon,
          label: Props.labels.label,
          text: tags.isEmpty ? null : tags.join(', '),
          picker: (context, control, apply) => TagPropertyPicker(
            id: Props.labels.id,
            value: tags,
            suggestions: tagSuggestions,
            onPick: (next) => apply(next),
          ),
          onPick: (v) => state.updateNoteTags(uid, v ?? const []),
        )
      else
        PropertyRow(
          key: const Key('property-tags'),
          icon: Props.labels.icon,
          label: Props.labels.label,
          text: tags.isEmpty ? null : tags.join(', '),
          readOnly: true,
        ),
      if (edit && state.projectsByRecent.isNotEmpty)
        PropertyPicker<String>(
          id: Props.parent.id,
          uid: uid,
          state: state,
          icon: Props.parent.icon,
          label: Props.parent.label,
          text: state.belongsToOf(uid),
          picker: (context, control, apply) => ParentPropertyPicker(
            id: Props.parent.id,
            state: state,
            uid: uid,
            onPick: (v) {
              control.hide();
              return apply(v);
            },
          ),
          onPick: (v) => state.setNoteParent(uid, v),
        )
      else
        PropertyRow(
          key: const Key('property-parent'),
          icon: Props.parent.icon,
          label: Props.parent.label,
          text: state.belongsToOf(uid),
          readOnly: true,
        ),
      // The rest of the header (item_id, owner, decided_by, ...) has no picker
      // of its own: it reads as plain text, as the meta card did. A non-folder
      // shows status and priority in the rows above.
      for (final e in p.fields.entries)
        if (folder || (e.key != 'status' && e.key != 'priority'))
          PropertyRow(
            key: Key('property-field-${e.key}'),
            icon: FLucideIcons.alignLeft,
            label: e.key,
            text: e.value,
            readOnly: true,
          ),
    ];

    Widget page = Column(
      children: [
        parentCrumb(state, uid),
        ItemHeader(
          title: note.summary,
          full: full,
          inHeader: inHeader,
          onClose: onClose,
          onTitleTap: edit && draft == null
              ? () => state.startEdit(uid, true)
              : null,
          editor: draft == null
              ? null
              : InlineText(
                  key: const Key('edit-title'),
                  controller: draft.titleController,
                  focusNode: draft.titleFocus,
                  commitSignal: draft.commitSignal,
                  style: paneTitleStyle(t),
                  autoBegin: state.noteTextTargets(uid),
                  onBegan: state.clearNoteTextIntent,
                  onCommit: (_) => state.commitNoteText(uid),
                  preview: (text) =>
                      PaneTitle(text, textKey: const Key('pane-title')),
                ),
          actions: [
            if (mobile)
              MobileItemActions(
                state: state,
                uid: uid,
                editing: draft != null,
                canEdit: state.editable,
                onEdit: () => state.startEdit(uid),
                draft: draft,
                groups: NoteContextMenu(
                  state: state,
                  uid: uid,
                  child: const SizedBox.shrink(),
                ).pageGroups,
              )
            else ...[
              if (draft != null) ...editIcons(state, uid),
              if (state.editable) ...[
                if (state.spaces.length > 1)
                  IconAction(
                    key: const Key('move-note'),
                    tooltip: 'Move to Space…',
                    icon: FLucideIcons.folderInput,
                    onPress: () => showMoveSpaceDialog(context, state, note),
                  ),
                if (draft == null)
                  IconAction(
                    key: const Key('edit-note'),
                    tooltip: 'Edit',
                    icon: FLucideIcons.pencil,
                    onPress: () => state.startEdit(uid),
                  ),
                IconAction(
                  key: const Key('delete-note'),
                  tooltip: 'Delete',
                  icon: FLucideIcons.trash2,
                  onPress: () => confirmDeleteNote(context, state, note),
                ),
              ],
            ],
          ],
        ),
        Expanded(
          child: SelectableBody(
            enabled: draft == null,
            child: SingleChildScrollView(
              controller: state.nav.pageScroll(area),
              padding: EdgeInsets.fromLTRB(
                t.space.xxl,
                t.space.md,
                t.space.xxl,
                t.space.huge,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: t.sizes.pageMax),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (rows.isNotEmpty) ...[
                        SizedBox(height: t.space.md),
                        PropertySection(rows: rows),
                        SizedBox(height: t.space.xl),
                      ],
                      if (draft != null)
                        NoteEditor(state: state, draft: draft, full: full)
                      else
                        MarkdownLite(p.text),
                      if (draft == null &&
                          state.tasksByParent(note.uid).isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: t.space.xxl),
                          child: ChildTasks(state: state, parentUid: note.uid),
                        ),
                      FutureBuilder<List<Revision>>(
                        key: ValueKey('rev-${note.uid}-${note.lastModified}'),
                        future: state.revisionsFor(note.uid),
                        builder: (context, snap) {
                          final revs = snap.data ?? const <Revision>[];
                          if (revs.isEmpty) return const SizedBox.shrink();
                          return Padding(
                            padding: EdgeInsets.only(top: t.space.xxl),
                            child: FAccordion(
                              key: const Key('revisions'),
                              children: [
                                FAccordionItem(
                                  title: Text(
                                    'Earlier versions (${revs.length})',
                                    style: t.type.bodyStyle.copyWith(
                                      color: t.muted,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      for (final r in revs.reversed)
                                        CardBox(
                                          width: double.infinity,
                                          margin: EdgeInsets.only(
                                            bottom: t.space.md,
                                          ),
                                          padding: EdgeInsets.all(t.space.lg),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${r.at.toLocal().toString().substring(0, 16)}  ·  ${r.reason}',
                                                style: t.type.microStyle
                                                    .copyWith(color: t.muted),
                                              ),
                                              SizedBox(height: t.space.xs),
                                              Text(
                                                r.summary,
                                                style: t.type.semiboldStyle,
                                              ),
                                              SelectableBody(
                                                child: Text(
                                                  r.body,
                                                  style: t.type.bodyStyle,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    // Ctrl/Cmd+S saves an open edit: the title field writes what it shows and
    // the body's own field follows.
    void saveNow() {
      if (draft == null) return;
      draft.commitSignal.ping();
      unawaited(state.flushEdit(uid));
    }

    page = CallbackShortcuts(
      bindings: {
        if (draft != null) ...{
          const SingleActivator(LogicalKeyboardKey.keyS, control: true):
              saveNow,
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): saveNow,
        },
      },
      child: page,
    );
    return draft == null ? page : EditKeys(state: state, uid: uid, child: page);
  }
}
