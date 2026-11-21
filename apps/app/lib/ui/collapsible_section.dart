import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../data/key_value_storage.dart';
import 'theme.dart';
import 'overflow_tip.dart';

/// A section with a small heading row (chevron, muted label, optional count)
/// that toggles its body. The collapsed state is kept in [prefs] under
/// [prefKey] when given. The toggle is keyed `'$id-toggle'`.
///
/// With [fill] the expanded body takes the height the section is given: put
/// the section in a `Flexible`, so a collapsed one shrinks to its heading.
class CollapsibleSection extends StatefulWidget {
  const CollapsibleSection({
    super.key,
    required this.id,
    required this.title,
    required this.child,
    this.count,
    this.prefs,
    this.prefKey,
    this.fill = false,
    this.headerPadding = EdgeInsets.zero,
    this.upper = true,
    this.initiallyCollapsed = false,
    this.leading,
    this.onChanged,
    this.collapsed,
    this.trailing,
  });
  final String id;
  final String title;
  final int? count;
  final KeyValueStorage? prefs;
  final String? prefKey;
  final bool fill;
  final EdgeInsetsGeometry headerPadding;

  /// Upper-case the label.
  final bool upper;

  /// Starts collapsed when [prefKey] holds no saved state.
  final bool initiallyCollapsed;

  /// Shown between the chevron and the label.
  final Widget? leading;

  /// Called with the new collapsed state after a toggle.
  final ValueChanged<bool>? onChanged;

  /// When set, the caller owns the collapsed state (and its persistence):
  /// the section shows it and only reports a toggle through [onChanged].
  final bool? collapsed;

  /// Shown at the right end of the header row (links, add buttons).
  final Widget? trailing;
  final Widget child;

  @override
  State<CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<CollapsibleSection> {
  late bool _collapsed = widget.prefKey != null
      ? widget.prefs?.read(widget.prefKey!) == 'true'
      : widget.initiallyCollapsed;

  bool get _isCollapsed => widget.collapsed ?? _collapsed;

  void _toggle() {
    if (widget.collapsed != null) {
      widget.onChanged?.call(!widget.collapsed!);
      return;
    }
    setState(() => _collapsed = !_collapsed);
    widget.onChanged?.call(_collapsed);
    final k = widget.prefKey;
    if (k == null) return;
    if (_collapsed) {
      widget.prefs?.write(k, 'true');
    } else {
      widget.prefs?.remove(k);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final title = widget.upper ? widget.title.toUpperCase() : widget.title;
    final fill = widget.fill && !_isCollapsed;
    return Column(
      mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: widget.headerPadding,
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FTappable(
                    key: Key('${widget.id}-toggle'),
                    semanticsLabel:
                        '${_isCollapsed ? 'Expand' : 'Collapse'} ${widget.title}',
                    onPress: _toggle,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: narrowLayout(context)
                            ? t.sizes.touchTarget
                            : 0,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isCollapsed
                                ? FLucideIcons.chevronRight
                                : FLucideIcons.chevronDown,
                            size: t.icons.lg,
                            color: t.muted,
                          ),
                          SizedBox(width: t.space.sm),
                          if (widget.leading != null) ...[
                            widget.leading!,
                            SizedBox(width: t.space.sm),
                          ],
                          Flexible(
                            child: OverflowTip(
                              title,
                              style: t.type.labelStyle.copyWith(
                                fontSize: t.type.caption,
                                color: t.muted,
                              ),
                            ),
                          ),
                          if (widget.count != null) ...[
                            SizedBox(width: t.space.sm),
                            Text(
                              '${widget.count}',
                              style: t.type.captionStyle.copyWith(
                                color: t.muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.trailing != null) widget.trailing!,
            ],
          ),
        ),
        if (!_isCollapsed) fill ? Expanded(child: widget.child) : widget.child,
      ],
    );
  }
}
