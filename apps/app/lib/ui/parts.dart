import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

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
  });

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
        child: Icon(icon),
      ),
    ),
  );
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
  });
  final List<Widget> children;

  /// Horizontal insets; both default to the standard medium space.
  final double? startPad, endPad;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: children,
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
  });
  final String title;
  final bool full, inHeader, strike;
  final VoidCallback onClose;
  final List<Widget> actions;

  /// The title field while the item is being edited.
  final Widget? editor;

  /// Shown before the title when not editing (a task's checkbox).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    // The narrow layout has the bottom bar's Back, so no arrow here.
    final back = !full && !inHeader && !narrowLayout(context);
    return PaneHeaderRow(
      key: const Key('peek-toolbar'),
      // Without a Back arrow the title lines up with the body's own padding.
      startPad: back ? t.space.xs : t.space.xxl,
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
        Expanded(
          child:
              editor ??
              Align(
                alignment: Alignment.centerLeft,
                child: PaneTitle(
                  title,
                  textKey: const Key('pane-title'),
                  muted: strike,
                  strike: strike,
                ),
              ),
        ),
        SizedBox(width: t.space.md),
        ...actions,
      ],
    );
  }
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

/// Text the user can select and copy (the revision list). Forui has no
/// selectable text, so this wraps the framework's region.
class SelectableBody extends StatefulWidget {
  const SelectableBody({super.key, required this.child});
  final Widget child;

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
  Widget build(BuildContext context) => SelectableRegion(
    focusNode: _focus,
    selectionControls: emptyTextSelectionControls,
    child: widget.child,
  );
}
