import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import 'parts.dart';
import 'popover_track.dart';
import 'property/date_property_picker.dart';
import 'property/option_picker.dart';
import 'property/property_defs.dart';
import 'property/property_trigger.dart' show PropertyPopoverGroup;
import 'property/tag_property_picker.dart';
import 'section_label.dart';
import 'task_parts.dart' show dueDate, dueOfDay;
import 'theme.dart';

/// A board card's properties, from its ⋯ button: the same pickers the item
/// page uses (status, priority, due, labels), so a card can be triaged
/// without opening it. Nothing is added to the card itself but the button.
///
/// One card and one item of either kind: the note and task boards of a saved
/// view and the unified board all show this same popover.
class CardProperties extends StatefulWidget {
  const CardProperties({super.key, required this.state, required this.uid});
  final AppState state;

  /// The note or task the card shows.
  final String uid;

  @override
  State<CardProperties> createState() => _CardPropertiesState();
}

class _CardPropertiesState extends State<CardProperties>
    with TickerProviderStateMixin {
  /// The tap region of this popover; stable while the card is.
  final _group = Object();

  AppState get _state => widget.state;

  /// A note write (these return nothing): it failed when the state says so.
  Future<bool> _note(Future<void> Function() change) async {
    await change();
    return _state.error == null;
  }

  /// Runs [write] after closing the picker, and says why when it fails.
  Future<void> _apply(
    FPopoverController c,
    Future<bool> Function() write, {
    bool close = true,
  }) async {
    if (close) c.hide();
    final ok = await write();
    if (!ok && mounted) {
      _state.reportNotSaved(_state.error ?? 'could not save');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final uid = widget.uid;
    final task = _state.taskById(uid);
    final note = task == null ? _state.tree.find(uid)?.note : null;
    if (task == null && note == null) return const SizedBox.shrink();
    final tags = task != null
        ? _state.taskTagsOf(task)
        : _state.noteTagsOf(note!);
    final plan = note == null ? null : PlanItem.fromNote(note);
    final status = task != null ? task.boardStatus : plan?.status ?? 'todo';
    final priority = task != null
        ? priorityBucket(task.priority)
        : (plan?.priorityWord ?? 'none');
    return TrackPopover(
      builder: (context, pc) => FPopover(
        control: pc,
        groupId: _group,
        popoverBuilder: (context, c) => PropertyPopoverGroup(
          groupId: _group,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: t.property.popoverMinWidth,
              maxWidth: t.property.popoverMaxWidth,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  vertical: t.property.cardPopoverPadding,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label(context, Props.status.label),
                    OptionPicker<String>(
                      id: 'card-status',
                      value: status,
                      onPick: (v) {
                        if (v == null) return;
                        _apply(
                          c,
                          () => task != null
                              ? _state.setTaskStatus(task.uid, v)
                              : _note(() => _state.setStatus(note!.uid, v)),
                        );
                      },
                      options: [
                        for (final o in noteStatusOptions())
                          PickerOption(
                            o.value,
                            o.label,
                            dot: o.dot,
                            enabled:
                                !(o.value == 'done' &&
                                    task != null &&
                                    _state.taskCompletionBlockerFor(task.uid) !=
                                        null),
                          ),
                      ],
                    ),
                    _label(context, Props.priority.label),
                    OptionPicker<String>(
                      id: 'card-priority',
                      value: priority,
                      clearable: true,
                      clearLabel: Props.noPriority,
                      onPick: (v) {
                        if (v == null) {
                          _apply(
                            c,
                            () => task != null
                                ? _state.setTaskPriority(task.uid, null)
                                : _note(
                                    () =>
                                        _state.setNotePriority(note!.uid, null),
                                  ),
                          );
                          return;
                        }
                        _apply(
                          c,
                          () => task != null
                              ? _state.setTaskPriority(
                                  task.uid,
                                  priorityOfBucket(v),
                                )
                              : _note(
                                  () => _state.setNotePriority(note!.uid, v),
                                ),
                        );
                      },
                      options: priorityOptions<String>((b) => b),
                    ),
                    if (task != null) ...[
                      _label(context, Props.due.label),
                      DatePropertyPicker(
                        id: 'card-due',
                        value: dueDate(task),
                        onPick: (d) => _apply(
                          c,
                          () => _state.setTaskDue(
                            task.uid,
                            d == null ? null : dueOfDay(d, task.due),
                          ),
                        ),
                      ),
                    ],
                    _label(context, Props.labels.label),
                    TagPropertyPicker(
                      id: 'card-labels',
                      value: tags,
                      suggestions: task != null
                          ? _state.taskTags
                          : ({
                              for (final n in _state.notes)
                                ..._state.noteTagsOf(n),
                            }.toList()..sort()),
                      onPick: (next) async {
                        final ok = await (task != null
                            ? _state.setTaskTags(task.uid, next)
                            : _state.updateNoteTags(note!.uid, next));
                        if (!ok && mounted) {
                          _state.reportNotSaved(
                            _state.error ?? 'could not save',
                          );
                        }
                        return ok;
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        builder: (context, c, child) =>
            FTappable(onPress: c.toggle, child: child!),
        child: IconAction(
          key: Key('card-more-$uid'),
          tooltip: 'Edit properties',
          icon: FLucideIcons.ellipsis,
          onPress: null,
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) {
    final p = tokensOf(context).property;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        p.cardLabelSide,
        p.cardLabelTop,
        p.cardLabelSide,
        p.cardLabelBottom,
      ),
      child: SectionLabel(text),
    );
  }
}
