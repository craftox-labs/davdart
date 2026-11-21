import 'popover_track.dart';

import 'package:davdart/davdart.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import 'chips.dart';
import 'edit_note_dialog.dart' show confirmDeleteNote;
import 'markdown_lite.dart';
import 'parts.dart';
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
        );
      }
      if (state.taskById(uid) == null) return const SizedBox.shrink();
      return TaskDetail(
        state: state,
        uid: uid,
        onClose: onClose,
        full: full,
        inHeader: inHeader,
      );
    }
    final p = PlanItem.fromNote(note);
    final draft = state.draftFor(uid);
    // Narrow: edit/preview toggle and ⋯ in the header; edits autosave.
    final mobile = narrowLayout(context);
    Widget page = Column(
      children: [
        ItemHeader(
          title: note.summary,
          full: full,
          inHeader: inHeader,
          onClose: onClose,
          editor: draft == null
              ? null
              : field(
                  key: const Key('edit-title'),
                  controller: draft.titleController,
                  hint: 'Title',
                  autofocus: !mobile,
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
                    tooltip: 'Move to another space',
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
        if (draft != null && !mobile) EditBar(state: state, draft: draft),
        Expanded(
          child: SingleChildScrollView(
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
                    if (draft != null)
                      NoteEditor(
                        state: state,
                        draft: draft,
                        note: note,
                        full: full,
                      )
                    else ...[
                      if (state.editable && !AppState.isFolder(note)) ...[
                        SizedBox(height: t.space.md),
                        Row(
                          children: [
                            Text('Status', style: TextStyle(color: t.muted)),
                            SizedBox(width: t.space.lg),
                            SizedBox(
                              width: t.sizes.statusField,
                              child: TrackPopover(
                                builder: (_, pc) => FSelect<String>.rich(
                                  popoverControl: pc,
                                  key: const Key('status-menu'),
                                  format: (v) => v,
                                  hint: 'none',
                                  control: FSelectControl.lifted(
                                    value: boardOrder.contains(p.status)
                                        ? p.status
                                        : null,
                                    onChange: (v) {
                                      if (v != null) {
                                        state.setStatus(note.uid, v);
                                      }
                                    },
                                  ),
                                  children: [
                                    for (final s in boardOrder)
                                      FSelectItem<String>(
                                        title: Text(s),
                                        value: s,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      SizedBox(height: t.space.lg),
                      if (p.fields.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(t.space.lg),
                          decoration: BoxDecoration(
                            color: t.card,
                            border: Border.all(color: t.cardBorder),
                            borderRadius: BorderRadius.circular(t.radii.card),
                          ),
                          child: Column(
                            children: [
                              for (final e in p.fields.entries)
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    vertical: t.space.xxs,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: t.sizes.metaLabel,
                                        child: Text(
                                          e.key,
                                          style: t.type.monoStyle.copyWith(
                                            color: t.muted,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          e.value,
                                          style: t.type.bodyStyle,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      if (note.categories.isNotEmpty) ...[
                        SizedBox(height: t.space.lg),
                        Wrap(
                          spacing: t.space.sm,
                          runSpacing: t.space.sm,
                          children: [
                            for (final c in note.categories) TagChip(c),
                          ],
                        ),
                      ],
                      SizedBox(height: t.space.xl),
                      MarkdownLite(p.text),
                    ],
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
                                      Container(
                                        width: double.infinity,
                                        margin: EdgeInsets.only(
                                          bottom: t.space.md,
                                        ),
                                        padding: EdgeInsets.all(t.space.lg),
                                        decoration: BoxDecoration(
                                          color: t.card,
                                          border: Border.all(
                                            color: t.cardBorder,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            t.radii.card,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${r.at.toLocal().toString().substring(0, 16)}  ·  ${r.reason}',
                                              style: t.type.microStyle.copyWith(
                                                color: t.muted,
                                              ),
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
      ],
    );
    // Ctrl/Cmd+S saves an open edit;
    page = CallbackShortcuts(
      bindings: {
        if (draft != null) ...{
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
            if (draft.dirty) state.saveDraft(uid);
          },
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
            if (draft.dirty) state.saveDraft(uid);
          },
        },
      },
      child: page,
    );
    return draft == null ? page : EditKeys(state: state, uid: uid, child: page);
  }
}
