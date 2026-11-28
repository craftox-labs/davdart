import 'package:davdart/davdart.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/event_draft.dart';
import '../state/event_rules.dart';
import '../state/key_nav.dart';
import 'event_menu.dart';
import 'event_when.dart';
import 'markdown_lite.dart';
import 'mobile_item.dart';
import 'note_editor.dart';
import 'parts.dart';
import 'property/inline_text.dart';
import 'property/option_picker.dart';
import 'property/parent_property_picker.dart'
    show ParentPropertyPicker, projectRowValue;
import 'property/property_picker.dart';
import 'property/property_row.dart';
import 'property/property_trigger.dart' show PropertyPopoverGroup;
import 'property/tag_property_picker.dart';
import 'repeat_fields.dart';
import 'section_label.dart';
import 'theme.dart';

/// An event's page (peek pane or main tab): its title, location and
/// description edited in place, and when, repeat, status and labels as rows
/// that open a picker. Each pick saves at once (with Undo), so there is no
/// edit mode, no Save or Cancel and no pencil.
class EventDetail extends StatelessWidget {
  const EventDetail({
    super.key,
    required this.state,
    required this.uid,
    required this.onClose,
    this.full = false,
    this.inHeader = false,
    this.area = NavArea.main,
  });
  final AppState state;
  final String uid;
  final VoidCallback onClose;
  final bool full;
  final bool inHeader;

  /// The pane showing this page: its keyboard scrolling goes to it.
  final NavArea area;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final event = state.eventById(uid);
    if (event == null) return const SizedBox.shrink();
    final draft = state.eventDraftFor(uid);
    final edit = state.eventsEditable;
    // Narrow: no edit toggle, just the ⋯ and the buffer's dot.
    final mobile = narrowLayout(context);
    final when = eventWhenOf(event);
    final tags = state.eventTagsOf(event);
    final status = event.status;

    void titleTap() => state.startEventEdit(uid);
    void whereTap() => state.startEventEdit(uid, focusLocation: true);
    void bodyTap() => state.startEventEdit(uid, focusBody: true);

    /// A plain value of a row that is not a picker.
    Widget value(String text, {Key? key}) => Text(
      text,
      key: key,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: t.type.bodyStyle,
    );

    final whenValue = value(eventWhen(event), key: const Key('event-when'));
    final statusValue = value(
      eventStatusName(status),
      key: const Key('event-status-text'),
    );

    Widget whereValue() {
      if (draft != null) {
        return InlineText(
          key: const Key('edit-location'),
          controller: draft.locationController,
          focusNode: draft.locationFocus,
          placeholder: 'Where…',
          style: t.type.bodyStyle,
          autoBegin: state.eventTextTargets(uid, location: true),
          onBegan: state.clearEventTextIntent,
          onCommit: (_) => state.commitEventText(uid),
          preview: (text) => value(text, key: const Key('event-location')),
        );
      }
      if (!edit) return value(event.location, key: const Key('event-location'));
      return FTappable(
        key: const Key('event-where-tap'),
        onPress: whereTap,
        child: Align(
          alignment: Alignment.centerLeft,
          child: event.location.isEmpty
              ? Text(
                  '—',
                  maxLines: 1,
                  style: t.type.bodyStyle.copyWith(color: t.muted),
                )
              : value(event.location, key: const Key('event-location')),
        ),
      );
    }

    final rows = <Widget>[
      if (edit)
        PropertyPicker<EventWhen>(
          id: 'when',
          uid: uid,
          state: state,
          icon: FLucideIcons.calendar,
          label: 'when',
          value: whenValue,
          picker: (context, control, apply) =>
              _WhenPicker(when: when, onPick: apply),
          onPick: (v) =>
              v == null ? Future.value(false) : state.setEventWhen(uid, v),
        )
      else
        PropertyRow(
          key: const Key('property-when'),
          icon: FLucideIcons.calendar,
          label: 'when',
          value: whenValue,
          readOnly: true,
        ),
      if (edit)
        PropertyPicker<String?>(
          id: 'repeat',
          uid: uid,
          state: state,
          icon: FLucideIcons.repeat,
          label: 'repeats',
          text: repeatLabel(event.rrule),
          picker: (context, control, apply) =>
              _RepeatPicker(rrule: event.rrule, when: when, onPick: apply),
          onPick: (v) => state.setEventRrule(uid, v),
        )
      else
        PropertyRow(
          key: const Key('property-repeat'),
          icon: FLucideIcons.repeat,
          label: 'repeats',
          text: repeatLabel(event.rrule),
          readOnly: true,
        ),
      PropertyRow(
        key: const Key('property-where'),
        icon: FLucideIcons.mapPin,
        label: 'where',
        value: whereValue(),
        readOnly: true,
      ),
      if (edit)
        PropertyPicker<String>(
          id: 'status',
          uid: uid,
          state: state,
          icon: FLucideIcons.circleDot,
          label: 'status',
          value: statusValue,
          picker: (context, control, apply) => OptionPicker<String>(
            id: 'status',
            value: status ?? '',
            onPick: (v) {
              control.hide();
              apply(v);
            },
            options: [
              for (final (word, label) in eventStatusWords)
                PickerOption(
                  word,
                  label,
                  icon: switch (word) {
                    'CONFIRMED' => FLucideIcons.circleCheck,
                    'TENTATIVE' => FLucideIcons.circleDot,
                    'CANCELLED' => FLucideIcons.x,
                    _ => FLucideIcons.circle,
                  },
                ),
            ],
          ),
          onPick: (v) =>
              state.setEventStatus(uid, v == null || v.isEmpty ? null : v),
        )
      else
        PropertyRow(
          key: const Key('property-status'),
          icon: FLucideIcons.circleDot,
          label: 'status',
          value: statusValue,
          readOnly: true,
        ),
      if (edit)
        PropertyPicker<List<String>>(
          id: 'tags',
          uid: uid,
          state: state,
          icon: FLucideIcons.tag,
          label: 'labels',
          text: tags.isEmpty ? null : tags.join(', '),
          picker: (context, control, apply) => TagPropertyPicker(
            id: 'tags',
            value: tags,
            suggestions: state.eventTags,
            onPick: apply,
          ),
          onPick: (v) => state.setEventTags(uid, v ?? const []),
        )
      else
        PropertyRow(
          key: const Key('property-tags'),
          icon: FLucideIcons.tag,
          label: 'labels',
          text: tags.isEmpty ? null : tags.join(', '),
          readOnly: true,
        ),
      if (edit && state.projectsByRecent.isNotEmpty)
        PropertyPicker<String>(
          id: 'parent',
          uid: uid,
          state: state,
          icon: FLucideIcons.folderKanban,
          label: 'project',
          text: projectRowValue(state, uid),
          picker: (context, control, apply) => ParentPropertyPicker(
            id: 'parent',
            state: state,
            uid: uid,
            onPick: (v) {
              control.hide();
              return apply(v);
            },
          ),
          onPick: (v) => state.setEventParent(uid, v),
        )
      else
        PropertyRow(
          key: const Key('property-parent'),
          icon: FLucideIcons.folderKanban,
          label: 'project',
          text: projectRowValue(state, uid),
          readOnly: true,
        ),
    ];

    final page = Column(
      children: [
        parentCrumb(state, uid),
        ItemHeader(
          title: event.summary,
          strike: event.isCancelled,
          full: full,
          inHeader: inHeader,
          onClose: onClose,
          onTitleTap: edit && draft == null ? titleTap : null,
          editor: draft == null
              ? null
              : InlineText(
                  key: const Key('edit-title'),
                  controller: draft.titleController,
                  focusNode: draft.titleFocus,
                  style: paneTitleStyle(t, muted: event.isCancelled).copyWith(
                    decoration: event.isCancelled
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                  autoBegin: state.eventTextTargets(uid),
                  onBegan: state.clearEventTextIntent,
                  onCommit: (_) => state.commitEventText(uid),
                  preview: (text) => PaneTitle(
                    text,
                    textKey: const Key('pane-title'),
                    muted: event.isCancelled,
                    strike: event.isCancelled,
                  ),
                ),
          actions: [
            if (mobile)
              MobileItemActions(
                state: state,
                uid: uid,
                editing: false,
                canEdit: false,
                onEdit: titleTap,
                draft: draft,
                groups: EventContextMenu(
                  state: state,
                  uid: uid,
                  child: const SizedBox.shrink(),
                ).pageGroups,
              )
            else if (edit) ...[
              if (state.spaces.length > 1)
                IconAction(
                  key: const Key('move-note'),
                  tooltip: 'Move to Space…',
                  icon: FLucideIcons.folderInput,
                  onPress: () => showMoveEventDialog(context, state, event),
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
                    key: const Key('event-detail'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PropertySection(rows: rows),
                      if (event.isRecurring) ...[
                        SizedBox(height: t.space.md),
                        Text(
                          'This event repeats. Editing changes the whole '
                          'series; occurrences changed one by one keep their '
                          'changes.',
                          key: const Key('event-series-note'),
                          style: t.type.captionStyle.copyWith(color: t.muted),
                        ),
                      ],
                      if (event.recurrenceUnsupported) ...[
                        SizedBox(height: t.space.md),
                        Text(
                          'This repeat rule is not expanded here; only the '
                          'first occurrence is listed.',
                          key: const Key('event-unsupported'),
                          style: t.type.captionStyle.copyWith(color: t.muted),
                        ),
                      ],
                      SizedBox(height: t.space.xl),
                      if (edit || event.description.trim().isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(bottom: t.space.sm),
                          child: SectionLabel('Description'),
                        ),
                      _description(context, event, draft, edit, bodyTap),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    Widget withKeys = CallbackShortcuts(
      bindings: {
        if (draft != null) ...{
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
            if (draft.dirty) state.commitEventText(uid);
          },
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
            if (draft.dirty) state.commitEventText(uid);
          },
        },
      },
      child: page,
    );
    return draft == null
        ? withKeys
        : EditKeys(state: state, uid: uid, child: withKeys);
  }

  /// The description: markdown until it is picked, then the inline field.
  Widget _description(
    BuildContext context,
    Event event,
    EventDraft? draft,
    bool edit,
    VoidCallback onTap,
  ) {
    final t = tokensOf(context);
    if (draft != null) {
      return InlineText(
        key: const Key('edit-body'),
        controller: draft.bodyController,
        focusNode: draft.bodyFocus,
        multiline: true,
        placeholder: 'Description',
        autoBegin: state.eventTextTargets(uid, body: true),
        onBegan: state.clearEventTextIntent,
        onCommit: (_) => state.commitEventText(uid),
        preview: MarkdownLite.new,
      );
    }
    if (event.description.trim().isEmpty) {
      if (!edit) return const SizedBox.shrink();
      return FTappable(
        key: const Key('event-description-tap'),
        onPress: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: t.space.xs),
          child: Text(
            'Description',
            style: t.type.bodyStyle.copyWith(color: t.muted),
          ),
        ),
      );
    }
    return FTappable(
      key: const Key('event-description-tap'),
      onPress: edit ? onTap : null,
      child: MarkdownLite(event.description),
    );
  }
}

/// The when fields in a picker: all day, start date and time, end date and
/// time. Each change writes the whole when at once.
class _WhenPicker extends StatelessWidget {
  const _WhenPicker({required this.when, required this.onPick});
  final EventWhen when;
  final ValueChanged<EventWhen> onPick;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.all(tokensOf(context).space.lg),
    child: EventWhenFields(
      keys: 'property-when',
      allDay: when.allDay,
      start: when.start,
      end: when.end,
      groupId: PropertyPopoverGroup.of(context),
      onAllDay: (v) => onPick(eventAllDaySwitched(when, v)),
      onStart: (date, minutes) =>
          onPick(eventStartMoved(when, date: date, minutes: minutes)),
      onEnd: (date, minutes) =>
          onPick(eventEndSet(when, date: date, minutes: minutes)),
    ),
  );
}

/// The repeat rule in a picker: frequency, interval, weekdays and end. Each
/// change writes the rule at once and the picker stays open.
class _RepeatPicker extends StatelessWidget {
  const _RepeatPicker({
    required this.rrule,
    required this.when,
    required this.onPick,
  });
  final String? rrule;
  final EventWhen when;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.all(tokensOf(context).space.lg),
    child: RepeatFields(
      keys: 'property-repeat',
      rrule: rrule,
      start: when.start,
      allDay: when.allDay,
      groupId: PropertyPopoverGroup.of(context),
      onChange: onPick,
    ),
  );
}
