import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../state/app_state.dart';
import '../../state/parent_targets.dart';
import '../parts.dart';
import '../theme.dart';
import 'option_picker.dart';

/// Where an item lives, in a picker: the projects first, so a pick is one row.
///
/// A search field, then "No project (personal)", then the Space's projects
/// (the ones opened most recently first) with their folder in muted text. Once
/// a search term is typed, the matching folders and sub-tasks join the list
/// (indented, marked by kind) so an item can still be put under any note or
/// task. The targets come from [parentTargets], so the rules about what may
/// contain what stay in one place.
class ParentPropertyPicker extends StatefulWidget {
  const ParentPropertyPicker({
    super.key,
    required this.id,
    required this.state,
    required this.uid,
    required this.onPick,
    this.currentParent,
  });

  /// Names the rows' and field's keys (`property-parent-<id>-...`).
  final String id;
  final AppState state;

  /// The item being moved: the picker cannot offer itself or its subtree.
  final String uid;
  final Future<bool> Function(String?) onPick;

  /// The parent the item has now (a note draft's unsaved one, wrapped so that
  /// a null — the top level — is a value too). Null: the item's parent in the
  /// tree.
  final (String?,)? currentParent;

  @override
  State<ParentPropertyPicker> createState() => _ParentPropertyPickerState();
}

class _ParentPropertyPickerState extends State<ParentPropertyPicker> {
  final _search = TextEditingController();
  var _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final state = widget.state;
    final q = _query.trim().toLowerCase();
    // The row the item sits in is the one marked: its own parent, not the
    // project of whatever that parent is under.
    final (parentUid,) =
        widget.currentParent ?? (parentUidOfItem(state, widget.uid),);
    final projects = state.projectsByRecent;
    // Only a search shows the folders and sub-tasks: the projects are the
    // everyday answer, the tree is the exception.
    final others = q.isEmpty
        ? const <ParentTarget>[]
        : [
            for (final p in parentTargets(state, forUid: widget.uid))
              if (p.uid != null &&
                  p.kind != ParentKind.top &&
                  p.label.toLowerCase().contains(q))
                p,
          ];
    final folderOf = {
      for (final p in projects)
        p.uid: p.parentUid == null
            ? null
            : state.tree.find(p.parentUid!)?.note.summary,
    };
    return Padding(
      padding: EdgeInsets.all(t.property.formPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: t.property.searchGap,
        children: [
          field(
            key: Key('property-parent-${widget.id}-search'),
            controller: _search,
            hint: 'Search notes, folders and tasks…',
            prefixIcon: FLucideIcons.search,
            onChange: (v) => setState(() => _query = v),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: t.property.pickerListMaxHeight,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PickerRow(
                    key: Key('property-parent-${widget.id}-top'),
                    label: 'Personal (top level)',
                    icon: FLucideIcons.circleUser,
                    selected: parentUid == null,
                    onPress: () => widget.onPick(null),
                  ),
                  for (final p in projects)
                    PickerRow(
                      key: Key('property-parent-${widget.id}-${p.uid}'),
                      label: p.summary,
                      hint: folderOf[p.uid],
                      icon: FLucideIcons.folderKanban,
                      selected: parentUid == p.uid,
                      onPress: () => widget.onPick(p.uid),
                    ),
                  for (final o in others)
                    PickerRow(
                      key: Key('property-parent-${widget.id}-${o.uid}'),
                      label: o.label,
                      hint: switch (o.kind) {
                        ParentKind.folder => 'folder',
                        ParentKind.task => 'task',
                        ParentKind.note || ParentKind.top => null,
                      },
                      icon: switch (o.kind) {
                        ParentKind.folder => FLucideIcons.folder,
                        ParentKind.task => FLucideIcons.circleCheck,
                        ParentKind.note ||
                        ParentKind.top => FLucideIcons.fileText,
                      },
                      depth: o.depth,
                      selected: o.uid == parentUid,
                      onPress: () => widget.onPick(o.uid),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The project [uid] sits in, or null when it sits outside every project.
Note? projectOfItem(AppState state, String uid) =>
    state.projectIndex.projectOf(uid);

/// The uid of the item [uid] sits in now (a note, a task or an event), or null
/// at the top level.
String? parentUidOfItem(AppState state, String uid) =>
    switch (state.findItem(uid)) {
      Note n => n.parentUid,
      Task t => t.parentUid,
      Event e => e.parentUid,
      _ => null,
    };

/// The value a Project row shows: what the item really sits in (a parent
/// task, a project, a folder or note outside every project), or 'Personal'.
String projectRowValue(AppState state, String uid) => state.belongsToOf(uid);

/// The project value for a parent choice being edited (a note draft, whose
/// parent is not saved yet): the project of [parentUid], its own name when it
/// is not in a project, or 'Personal' when there is none.
String projectValueFor(AppState state, String? parentUid) {
  if (parentUid == null) return 'Personal';
  return state.projectIndex.projectOf(parentUid)?.summary ??
      state.tree.find(parentUid)?.note.summary ??
      switch (state.findItem(parentUid)) {
        Task t => t.summary,
        Event e => e.summary,
        _ => null,
      } ??
      'Personal';
}
