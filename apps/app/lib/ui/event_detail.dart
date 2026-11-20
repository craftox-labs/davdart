import 'popover_track.dart';

import 'package:davdart/davdart.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/event_draft.dart';
import '../state/event_rules.dart';
import 'chips.dart';
import 'event_menu.dart';
import 'event_when.dart';
import 'markdown_lite.dart';
import 'parts.dart';
import 'note_editor.dart';
import 'theme.dart';
import 'vim_field.dart';

const _statusWords = [
  ('', 'none'),
  ('CONFIRMED', 'confirmed'),
  ('TENTATIVE', 'tentative'),
  ('CANCELLED', 'cancelled'),
];

String _statusName(String? s) => _statusWords
    .firstWhere((e) => e.$1 == (s ?? ''), orElse: () => (s ?? '', s ?? ''))
    .$2;

/// The unsaved-edits bar of an event edit.
class EventEditBar extends StatelessWidget {
  const EventEditBar({super.key, required this.state, required this.draft});
  final AppState state;
  final EventDraft draft;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) {
        final dirty = draft.dirty;
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: t.space.lg,
            vertical: t.space.sm,
          ),
          child: Row(
            children: [
              if (dirty) ...[
                Container(
                  key: const Key('dirty-indicator'),
                  width: t.sizes.statusDot,
                  height: t.sizes.statusDot,
                  decoration: BoxDecoration(
                    color: t.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: t.space.sm),
                Flexible(
                  child: Text(
                    'Unsaved changes',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.type.captionStyle.copyWith(color: t.muted),
                  ),
                ),
              ] else
                Text(
                  'Editing',
                  style: t.type.captionStyle.copyWith(color: t.muted),
                ),
              const Spacer(),
              SizedBox(width: t.space.sm),
              FButton(
                key: const Key('edit-discard'),
                variant: FButtonVariant.outline,
                size: FButtonSizeVariant.sm,
                mainAxisSize: MainAxisSize.min,
                onPress: () => state.discardEventDraft(draft.uid),
                child: Text(dirty ? 'Discard' : 'Done'),
              ),
              SizedBox(width: t.space.sm),
              FButton(
                key: const Key('edit-save'),
                size: FButtonSizeVariant.sm,
                mainAxisSize: MainAxisSize.min,
                onPress: dirty && !draft.titleEmpty && !draft.endBeforeStart
                    ? () => state.saveEventDraft(draft.uid)
                    : null,
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The fields of an open event edit: title, when, location, status, tags and
/// description, with a note when the event repeats.
class EventEditor extends StatelessWidget {
  const EventEditor({
    super.key,
    required this.state,
    required this.draft,
    required this.event,
    required this.full,
  });
  final AppState state;
  final EventDraft draft;
  final Event event;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: t.space.lg,
        children: [
          if (draft.titleEmpty)
            Text(
              'A title is required',
              style: t.type.captionStyle.copyWith(color: t.error),
            ),
          EventWhenFields(
            keys: 'edit',
            allDay: draft.allDay,
            start: draft.start,
            end: draft.end,
            error: draft.endBeforeStart ? 'The end is before the start' : null,
            onAllDay: draft.setAllDay,
            onStart: (date, minutes) =>
                draft.moveStart(date: date, minutes: minutes),
            onEnd: (date, minutes) =>
                draft.setEnd(date: date, minutes: minutes),
          ),
          if (event.isRecurring)
            Text(
              'This event repeats. Editing changes the whole series; '
              'occurrences changed one by one keep their changes.',
              key: const Key('event-series-note'),
              style: t.type.captionStyle.copyWith(color: t.muted),
            ),
          field(
            key: const Key('edit-location'),
            controller: draft.locationController,
            label: 'Location',
          ),
          TrackPopover(
            builder: (_, pc) => FSelect<String>.rich(
              popoverControl: pc,
              key: const Key('edit-status'),
              label: const Text('Status'),
              format: (v) => _statusName(v),
              control: FSelectControl.lifted(
                value: draft.status ?? '',
                onChange: (v) {
                  if (v == null) return;
                  final next = v.isEmpty ? null : v;
                  if (next != draft.status) draft.setStatus(next);
                },
              ),
              children: [
                for (final e in _statusWords)
                  FSelectItem<String>(title: Text(e.$2), value: e.$1),
              ],
            ),
          ),
          field(
            key: const Key('edit-tags'),
            controller: draft.tagsController,
            label: 'Tags (comma separated)',
          ),
          VimField(
            key: ValueKey('vim-${draft.uid}'),
            state: state,
            uid: draft.uid,
            controller: draft.bodyController,
            fieldKey: const Key('edit-body'),
            minLines: full ? t.sizes.editorLinesFull : t.sizes.editorLines,
            label: 'Description',
          ),
        ],
      ),
    );
  }
}

/// An event's page (peek pane or main tab): read view, or the editor while a
/// draft is open. Peek and main tab share one draft per event.
class EventDetail extends StatelessWidget {
  const EventDetail({
    super.key,
    required this.state,
    required this.uid,
    required this.onClose,
    this.full = false,
    this.inHeader = false,
  });
  final AppState state;
  final String uid;
  final VoidCallback onClose;
  final bool full;
  final bool inHeader;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final event = state.eventById(uid);
    if (event == null) return const SizedBox.shrink();
    final draft = state.eventDraftFor(uid);
    final edit = state.eventsEditable;
    Widget meta(String label, Widget value) => Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: t.sizes.metaLabel,
            child: Text(
              label,
              style: t.type.monoStyle.copyWith(color: t.muted),
            ),
          ),
          Expanded(child: value),
        ],
      ),
    );
    Widget page = Column(
      children: [
        ItemHeader(
          title: event.summary.isEmpty ? '(no title)' : event.summary,
          strike: event.isCancelled,
          full: full,
          inHeader: inHeader,
          onClose: onClose,
          editor: draft == null
              ? null
              : field(
                  key: const Key('edit-title'),
                  controller: draft.titleController,
                  hint: 'Title',
                  autofocus: true,
                ),
          actions: [
            if (draft != null) ...editIcons(state, uid),
            if (edit) ...[
              if (state.spaces.length > 1)
                IconAction(
                  key: const Key('move-note'),
                  tooltip: 'Move to another space',
                  icon: FLucideIcons.folderInput,
                  onPress: () => showMoveEventDialog(context, state, event),
                ),
              if (draft == null)
                IconAction(
                  key: const Key('edit-note'),
                  tooltip: 'Edit',
                  icon: FLucideIcons.pencil,
                  onPress: () => state.startEventEdit(uid),
                ),
              IconAction(
                key: const Key('delete-note'),
                tooltip: 'Delete',
                icon: FLucideIcons.trash2,
                onPress: () => confirmDeleteEvent(context, state, event),
              ),
            ],
          ],
        ),
        if (draft != null) EventEditBar(state: state, draft: draft),
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
                  key: const Key('event-detail'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (draft != null)
                      EventEditor(
                        state: state,
                        draft: draft,
                        event: event,
                        full: full,
                      )
                    else ...[
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
                            meta(
                              'when',
                              Text(
                                eventWhen(event),
                                key: const Key('event-when'),
                                style: t.type.bodyStyle,
                              ),
                            ),
                            if (event.location.isNotEmpty)
                              meta(
                                'where',
                                Text(
                                  event.location,
                                  key: const Key('event-location'),
                                  style: t.type.bodyStyle,
                                ),
                              ),
                            meta(
                              'status',
                              Text(
                                _statusName(event.status),
                                key: const Key('event-status-text'),
                                style: t.type.bodyStyle,
                              ),
                            ),
                            if (event.isRecurring)
                              meta(
                                'repeats',
                                Text(
                                  event.rrule == null || event.rrule!.isEmpty
                                      ? 'on chosen dates (edit in another app)'
                                      : '${event.rrule} (edit in another app)',
                                  key: const Key('event-rrule'),
                                  style: t.type.bodyStyle,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (event.recurrenceUnsupported) ...[
                        SizedBox(height: t.space.md),
                        Text(
                          'This repeat rule is not expanded here; only the '
                          'first occurrence is listed.',
                          key: const Key('event-unsupported'),
                          style: t.type.captionStyle.copyWith(color: t.muted),
                        ),
                      ],
                      if (state.eventTagsOf(event).isNotEmpty) ...[
                        SizedBox(height: t.space.lg),
                        Wrap(
                          spacing: t.space.sm,
                          runSpacing: t.space.sm,
                          children: [
                            for (final c in state.eventTagsOf(event))
                              TagChip(c),
                          ],
                        ),
                      ],
                      if (event.description.trim().isNotEmpty) ...[
                        SizedBox(height: t.space.xl),
                        MarkdownLite(event.description),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
    page = CallbackShortcuts(
      bindings: {
        if (draft != null) ...{
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
            if (draft.dirty) state.saveEventDraft(uid);
          },
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
            if (draft.dirty) state.saveEventDraft(uid);
          },
        },
      },
      child: page,
    );
    return draft == null ? page : EditKeys(state: state, uid: uid, child: page);
  }
}
