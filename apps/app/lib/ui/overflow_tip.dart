import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import 'theme.dart';

/// A [Text] that shows a tooltip with its full text only while it is cut off
/// (ellipsis or clipped lines). Hover on desktop, long press on touch (forui's
/// tooltip handles both). When the text fits there is no tooltip at all, so
/// hover and long-press fall through to whatever surrounds it.
///
/// Give it the same arguments as a [Text]; [tip] replaces the tooltip text
/// where the full text differs from what is shown.
class OverflowTip extends StatefulWidget {
  const OverflowTip(
    this.text, {
    super.key,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign,
    this.tip,
    this.textKey,
  });

  final String text;
  final TextStyle? style;
  final int maxLines;
  final TextOverflow overflow;
  final TextAlign? textAlign;

  /// Tooltip text when it should differ from [text].
  final String? tip;

  /// Key of the inner [Text] (so tests and callers can find the label).
  final Key? textKey;

  /// True when [text] laid out in [maxWidth] does not fit [maxLines].
  static bool cutOff(
    String text,
    TextStyle style,
    int maxLines,
    double maxWidth,
    TextDirection dir,
    TextScaler scaler,
  ) {
    if (!maxWidth.isFinite || text.isEmpty) return false;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: maxLines,
      textDirection: dir,
      textScaler: scaler,
    )..layout(maxWidth: maxWidth);
    final cut = painter.didExceedMaxLines;
    painter.dispose();
    return cut;
  }

  @override
  State<OverflowTip> createState() => _OverflowTipState();
}

class _OverflowTipState extends State<OverflowTip> {
  bool _cut = false;

  void _set(bool cut) {
    if (mounted && cut != _cut) setState(() => _cut = cut);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final base = DefaultTextStyle.of(context).style.merge(w.style);
    final dir = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final label = _Probe(
      check: (maxWidth) =>
          OverflowTip.cutOff(w.text, base, w.maxLines, maxWidth, dir, scaler),
      onResult: _set,
      child: Text(
        w.text,
        key: w.textKey,
        style: w.style,
        maxLines: w.maxLines,
        overflow: w.overflow,
        textAlign: w.textAlign,
      ),
    );
    if (!_cut) return label;
    return FTooltip(
      tipBuilder: (_, _) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: tokensOf(context).sizes.tipMax),
        child: Text(w.tip ?? w.text),
      ),
      child: label,
    );
  }
}

/// Measures after layout (so it works under intrinsic-size parents such as
/// menus, where a LayoutBuilder cannot) and reports whether the text is cut.
class _Probe extends SingleChildRenderObjectWidget {
  const _Probe({required this.check, required this.onResult, super.child});
  final bool Function(double maxWidth) check;
  final ValueChanged<bool> onResult;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderProbe(check, onResult);

  @override
  void updateRenderObject(BuildContext context, _RenderProbe renderObject) {
    renderObject
      ..check = check
      ..onResult = onResult
      ..markNeedsLayout();
  }
}

class _RenderProbe extends RenderProxyBox {
  _RenderProbe(this.check, this.onResult);
  bool Function(double maxWidth) check;
  ValueChanged<bool> onResult;
  bool _last = false;

  @override
  void performLayout() {
    super.performLayout();
    final cut = check(constraints.maxWidth);
    if (cut != _last) {
      _last = cut;
      SchedulerBinding.instance.addPostFrameCallback((_) => onResult(cut));
    }
  }
}
