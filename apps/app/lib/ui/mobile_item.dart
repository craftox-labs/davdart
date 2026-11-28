import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import 'note_menu.dart';
import 'parts.dart';
import 'theme.dart';

/// The open item's header actions on the narrow layout, Obsidian style: a
/// small saved/saving note while editing, the edit/preview toggle and a ⋯
/// button opening a sheet from the top with the item's other actions.
///
/// The toggle's icon shows the action a press does: a pencil while previewing
/// (edit), an open book while editing (back to the preview). Leaving edit mode
/// saves first (edits autosave, there is no cancel).
///
/// An item with no edit mode ([canEdit] false, a task whose text is edited in
/// place) keeps only the ⋯ button and the dot of its text buffer.
class MobileItemActions extends StatefulWidget {
  const MobileItemActions({
    super.key,
    required this.state,
    required this.uid,
    required this.editing,
    required this.canEdit,
    required this.onEdit,
    required this.groups,
    this.draft,
  });
  final AppState state;
  final String uid;
  final bool editing, canEdit;

  /// Starts editing the item (unused when [canEdit] is false).
  final VoidCallback onEdit;

  /// The edit session, for the saved indicator.
  final Listenable? draft;

  /// The item's actions for the ⋯ sheet: [context] outlives the sheet (use it
  /// for dialogs), [menuContext] themes the rows.
  final List<FItemGroup> Function(
    BuildContext context,
    BuildContext menuContext,
    FPopoverController controller,
  )
  groups;

  @override
  State<MobileItemActions> createState() => _MobileItemActionsState();
}

class _MobileItemActionsState extends State<MobileItemActions>
    with TickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.canEdit)
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconAction(
                key: const Key('item-mode'),
                tooltip: widget.editing ? 'Show preview' : 'Edit',
                icon: widget.editing
                    ? FLucideIcons.bookOpen
                    : FLucideIcons.pencil,
                onPress: widget.editing
                    ? () => state.saveAndLeave(widget.uid)
                    : widget.onEdit,
              ),
              // The save state, a dot on the button's corner.
              if (widget.editing && widget.draft != null)
                AutosaveIndicator(
                  state: state,
                  uid: widget.uid,
                  draft: widget.draft!,
                ),
            ],
          ),
        if (!widget.canEdit && widget.draft != null)
          AutosaveDot(state: state, uid: widget.uid, draft: widget.draft!),
        IconAction(
          key: const Key('item-more'),
          tooltip: 'More',
          icon: FLucideIcons.ellipsis,
          onPress: () => showMenuSheet(
            context,
            this,
            (ctx, c) => widget.groups(context, ctx, c),
            side: FLayout.ttb,
          ),
        ),
      ],
    );
  }
}

/// The state of an open edit as a tiny dot on the corner of the mode
/// button: nothing once saved, a muted dot while a save is pending or
/// running, an error-coloured dot when it could not be saved (an empty title,
/// a failure; leaving also toasts it). Every state has a semantic label.
class AutosaveIndicator extends StatelessWidget {
  const AutosaveIndicator({
    super.key,
    required this.state,
    required this.uid,
    required this.draft,
  });
  final AppState state;
  final String uid;
  final Listenable draft;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Positioned(
      top: t.space.sm,
      right: t.space.sm,
      child: IgnorePointer(
        child: AutosaveDot(state: state, uid: uid, draft: draft),
      ),
    );
  }
}

/// The dot itself, for the places that have no mode button to sit on (a
/// task's inline text beside the ⋯ button).
class AutosaveDot extends StatelessWidget {
  const AutosaveDot({
    super.key,
    required this.state,
    required this.uid,
    required this.draft,
  });
  final AppState state;
  final String uid;
  final Listenable draft;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([state, draft]),
      builder: (context, _) {
        final dirty = state.dirtyItem(uid);
        final (key, label, color) = !dirty
            ? ('saved', 'Saved', null)
            : state.autosavePending(uid)
            ? ('saving', 'Saving', t.muted)
            : ('failed', 'Not saved', t.error);
        return Semantics(
          key: Key('autosave-$key'),
          label: label,
          child: color == null
              ? const SizedBox.shrink()
              : Container(
                  width: t.sizes.statusDot,
                  height: t.sizes.statusDot,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
        );
      },
    );
  }
}
