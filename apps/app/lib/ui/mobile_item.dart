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

  /// Starts editing the item.
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
        if (widget.editing && widget.draft != null)
          AutosaveIndicator(
            state: state,
            uid: widget.uid,
            draft: widget.draft!,
          ),
        if (widget.canEdit)
          IconAction(
            key: const Key('item-mode'),
            tooltip: widget.editing ? 'Show preview' : 'Edit',
            icon: widget.editing ? FLucideIcons.bookOpen : FLucideIcons.pencil,
            onPress: widget.editing
                ? () => state.saveAndLeave(widget.uid)
                : widget.onEdit,
          ),
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

/// A small muted note on the state of an open edit: Saving while a save is
/// pending or running, Saved once everything is stored, Not saved when it
/// could not be (an empty title, a failure).
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
    return ListenableBuilder(
      listenable: Listenable.merge([state, draft]),
      builder: (context, _) {
        final dirty = state.dirtyItem(uid);
        final (key, label, color) = !dirty
            ? ('saved', 'Saved', t.muted)
            : state.autosavePending(uid)
            ? ('saving', 'Saving…', t.muted)
            : ('failed', 'Not saved', t.error);
        return Padding(
          padding: EdgeInsets.only(right: t.space.xs),
          child: Text(
            label,
            key: Key('autosave-$key'),
            maxLines: 1,
            style: t.type.microStyle.copyWith(color: color),
          ),
        );
      },
    );
  }
}
