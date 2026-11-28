import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'overflow_tip.dart';
import 'theme.dart';

/// A small icon-only button with a hover tooltip.
class IconAction extends StatelessWidget {
  const IconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPress,
    this.compact = false,
    this.spinning = false,
  });

  /// Rotates the icon continuously while true (a refresh in progress).
  final bool spinning;

  /// Extra-small button, for dense bars such as the top bar.
  final bool compact;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) => FTooltip(
    tipBuilder: (_, _) => Text(tooltip),
    child: touchBox(
      context,
      square: true,
      FButton.icon(
        variant: FButtonVariant.ghost,
        size: compact ? FButtonSizeVariant.xs : FButtonSizeVariant.sm,
        semanticsLabel: tooltip,
        onPress: onPress,
        child: spinning ? SpinIcon(icon) : Icon(icon),
      ),
    ),
  );
}

/// An icon that turns continuously while it is mounted; callers mount it only
/// while busy, so no ticker runs when idle. Still under reduced motion.
class SpinIcon extends StatefulWidget {
  const SpinIcon(this.icon, {super.key});
  final IconData icon;

  @override
  State<SpinIcon> createState() => _SpinIconState();
}

class _SpinIconState extends State<SpinIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RotationTransition(turns: _c, child: Icon(widget.icon));
}

/// The one header row every pane starts with (side panel section title, top
/// bar, peek toolbar): [SizeTokens.paneHeader] tall with a hairline under it and
/// children centred, so rows side by side share top, centreline and bottom.
class PaneHeaderRow extends StatelessWidget {
  const PaneHeaderRow({
    super.key,
    required this.children,
    this.startPad,
    this.endPad,
    this.maxContentWidth,
  });
  final List<Widget> children;

  /// Horizontal insets; both default to the standard medium space.
  final double? startPad, endPad;

  /// The row's content is centred in a column this wide (the item page's
  /// content column), so its edges line up with the page below.
  final double? maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: children,
    );
    return SizedBox(
      height: t.sizes.paneHeader,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: t.divider, width: t.borders.hairline),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            left: startPad ?? t.space.md,
            right: endPad ?? t.space.md,
          ),
          child: maxContentWidth == null
              ? row
              : Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxContentWidth!),
                    child: row,
                  ),
                ),
        ),
      ),
    );
  }
}

/// The title of a pane header row: one line, paneTitleStyle, with an
/// ellipsis and a full-text tooltip when it is cut off. Used for the side
/// panel section name, the item title in the main and peek panes and (as a
/// style) the Home breadcrumb, so they all read the same.
class PaneTitle extends StatelessWidget {
  const PaneTitle(
    this.text, {
    super.key,
    this.textKey,
    this.muted = false,
    this.strike = false,
  });
  final String text;
  final Key? textKey;
  final bool muted;
  final bool strike;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return OverflowTip(
      text,
      textKey: textKey,
      style: paneTitleStyle(
        t,
        muted: muted,
      ).copyWith(decoration: strike ? TextDecoration.lineThrough : null),
    );
  }
}

/// The title field of an item header while editing. Wide: the form field.
/// Narrow: plain text in the exact style of [PaneTitle], no box or border, so
/// the title looks the same in edit and preview and the row does not shift.
Widget itemTitleField(
  BuildContext context, {
  required TextEditingController controller,
}) => narrowLayout(context)
    ? _PlainTitleField(key: const Key('edit-title'), controller: controller)
    : field(
        key: const Key('edit-title'),
        controller: controller,
        hint: 'Title',
        autofocus: true,
      );

class _PlainTitleField extends StatefulWidget {
  const _PlainTitleField({super.key, required this.controller});
  final TextEditingController controller;

  @override
  State<_PlainTitleField> createState() => _PlainTitleFieldState();
}

class _PlainTitleFieldState extends State<_PlainTitleField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    // What PaneTitle's Text shows: its style merged over the inherited
    // DefaultTextStyle (an EditableText does not inherit it by itself).
    final style = DefaultTextStyle.of(context).style.merge(paneTitleStyle(t));
    return Align(
      alignment: Alignment.centerLeft,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          // The hint, only while empty.
          ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) => widget.controller.text.isEmpty
                ? Text('Title', style: style.copyWith(color: t.muted))
                : const SizedBox.shrink(),
          ),
          EditableText(
            controller: widget.controller,
            focusNode: _focus,
            style: style,
            cursorColor: t.accent,
            backgroundCursorColor: t.muted,
            selectionColor: t.selectionFill,
            maxLines: 1,
            textInputAction: TextInputAction.done,
          ),
        ],
      ),
    );
  }
}

/// The header row of an item pane (note, task or event, in the main area or
/// the peek): optional Back arrow, the item [title] on one line (or the
/// [editor] field in its place while editing, so nothing jumps), then the
/// [actions] at the end. Body content starts directly under it.
class ItemHeader extends StatelessWidget {
  const ItemHeader({
    super.key,
    required this.title,
    required this.full,
    required this.inHeader,
    required this.onClose,
    required this.actions,
    this.editor,
    this.leading,
    this.strike = false,
    this.onTitleTap,
  });
  final String title;
  final bool full, inHeader, strike;
  final VoidCallback onClose;
  final List<Widget> actions;

  /// The title field while the item is being edited.
  final Widget? editor;

  /// Makes the title itself the way into its inline field (an item whose text
  /// is edited in place).
  final VoidCallback? onTitleTap;

  /// Shown before the title when not editing (a task's checkbox).
  final Widget? leading;

  /// The title as text, or as the tap target that opens its inline field.
  Widget _title() {
    final text = Align(
      alignment: Alignment.centerLeft,
      child: PaneTitle(
        title,
        textKey: const Key('pane-title'),
        muted: strike,
        strike: strike,
      ),
    );
    final tap = onTitleTap;
    return tap == null ? text : FTappable(onPress: tap, child: text);
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    // The narrow layout has the bottom bar's Back, so no arrow here.
    final back = !full && !inHeader && !narrowLayout(context);
    return PaneHeaderRow(
      key: const Key('peek-toolbar'),
      // Without a Back arrow the title lines up with the body's own padding.
      startPad: back ? t.space.xs : t.space.xxl,
      // Wide: the title starts where the content column starts and the
      // actions end where it ends (the page below is centred and capped).
      endPad: back || narrowLayout(context) ? null : t.space.xxl,
      maxContentWidth: back || narrowLayout(context) ? null : t.sizes.pageMax,
      children: [
        if (back)
          IconAction(
            tooltip: 'Close',
            icon: FLucideIcons.arrowLeft,
            onPress: onClose,
          ),
        if (back) SizedBox(width: t.space.sm),
        if (leading != null && editor == null) ...[
          leading!,
          SizedBox(width: t.space.md),
        ],
        Expanded(child: editor ?? _title()),
        SizedBox(width: t.space.md),
        ...actions,
      ],
    );
  }
}

/// The way back up from an item that sits inside another: one muted line
/// above the item's title row, `↑ parent name`, which opens the parent where
/// this item is shown. Muted, one line, ellipsized; the label's own row, so
/// the title row and its alignment do not change.
class ParentCrumb extends StatelessWidget {
  const ParentCrumb({super.key, required this.label, required this.onOpen});
  final String label;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return PaneHeaderRow(
      key: const Key('parent-crumb'),
      startPad: t.space.xxl,
      endPad: t.space.xxl,
      maxContentWidth: narrowLayout(context) ? null : t.sizes.pageMax,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FTappable(
              onPress: onOpen,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    FLucideIcons.arrowUpToLine,
                    size: t.icons.sm,
                    color: t.muted,
                  ),
                  SizedBox(width: t.space.xs),
                  Flexible(
                    child: OverflowTip(
                      label,
                      textKey: const Key('parent-crumb-label'),
                      style: t.type.captionStyle.copyWith(color: t.muted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The crumb for [uid], or nothing when it sits at the top level.
Widget parentCrumb(AppState state, String uid) {
  final parent = state.parentItemOf(uid);
  if (parent == null) return const SizedBox.shrink();
  return ParentCrumb(
    label: parent.label,
    onOpen: () => state.openParentOf(uid),
  );
}

/// The shared pane title text style (size and weight from the type tokens,
/// colour [Tokens.paneTitleColor], or muted).
TextStyle paneTitleStyle(Tokens t, {bool muted = false}) =>
    t.type.paneTitleStyle.copyWith(color: muted ? t.muted : t.paneTitleColor);

/// Opens a forui dialog with a title, content and a row of actions.
Future<T?> showAppDialog<T>(
  BuildContext context, {
  required String title,
  required Widget content,
  required List<Widget> actions,
  double? width,
}) => showFDialog<T>(
  context: context,
  builder: (ctx, style, animation) => FDialog(
    animation: animation,
    constraints: BoxConstraints(maxWidth: width ?? tokensOf(ctx).sizes.dialog),
    builder: (ctx, style) {
      final t = tokensOf(ctx);
      return Padding(
        padding: EdgeInsets.all(t.space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: style.titleTextStyle),
            SizedBox(height: t.space.lg),
            Flexible(
              child: SingleChildScrollView(
                child: DefaultTextStyle.merge(
                  style: style.bodyTextStyle,
                  child: content,
                ),
              ),
            ),
            SizedBox(height: t.space.xl),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: t.space.md,
              runSpacing: t.space.md,
              children: actions,
            ),
          ],
        ),
      );
    },
  ),
);

/// The Cancel button every dialog carries.
class CancelButton extends StatelessWidget {
  const CancelButton({super.key, this.label = 'Cancel'});
  final String label;

  @override
  Widget build(BuildContext context) => FButton(
    variant: FButtonVariant.outline,
    mainAxisSize: MainAxisSize.min,
    onPress: () => Navigator.of(context).pop(),
    child: Text(label),
  );
}

/// The main action of a dialog.
class ActionButton extends StatelessWidget {
  const ActionButton(this.label, {super.key, required this.onPress});
  final String label;
  final void Function(BuildContext context) onPress;

  @override
  Widget build(BuildContext context) => FButton(
    mainAxisSize: MainAxisSize.min,
    onPress: () => onPress(context),
    child: Text(label),
  );
}

/// A form field: text with the forui look.
FTextField field({
  Key? key,
  required TextEditingController controller,
  String? label,
  String? hint,
  String? error,
  bool autofocus = false,
  FocusNode? focusNode,
  bool obscure = false,
  IconData? prefixIcon,
  int? minLines,
  int? maxLines = 1,
  ValueChanged<String>? onChange,
  ValueChanged<String>? onSubmit,
  bool readOnly = false,
  bool? showCursor,
}) {
  var last = controller.text;
  return FTextField(
    key: key,
    control: FTextFieldControl.managed(
      controller: controller,
      onChange: onChange == null
          ? null
          : (v) {
              if (v.text == last) return;
              last = v.text;
              onChange(v.text);
            },
    ),
    label: label == null ? null : Text(label),
    hint: hint,
    error: error == null ? null : Text(error),
    autofocus: autofocus,
    focusNode: focusNode,
    obscureText: obscure,
    prefixBuilder: prefixIcon == null
        ? null
        : (c, s, v) => FTextField.prefixIconBuilder(c, s, v, Icon(prefixIcon)),
    minLines: minLines,
    maxLines: maxLines,
    onSubmit: onSubmit,
    readOnly: readOnly,
    showCursor: showCursor,
  );
}

/// Text the user can select and copy (the revision list, the read views of
/// notes, tasks and events). Forui has no selectable text, so this wraps the
/// framework's region. [enabled] is off while a draft is open: the fields keep
/// their own selection and focus behaviour.
class SelectableBody extends StatefulWidget {
  const SelectableBody({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;

  @override
  State<SelectableBody> createState() => _SelectableBodyState();
}

class _SelectableBodyState extends State<SelectableBody> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.enabled
      ? SelectableRegion(
          focusNode: _focus,
          selectionControls: emptyTextSelectionControls,
          child: widget.child,
        )
      : widget.child;
}
