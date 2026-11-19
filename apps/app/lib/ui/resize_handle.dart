import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/widgets.dart';

import 'theme.dart';

/// A slim vertical handle on a pane edge: resize cursor, an accent line on
/// hover or drag. Dragging calls [onResize] with the new width, clamped to
/// [min]..[max] (no saving), then [onEnd] on release; a double-click calls
/// [onReset]. [grow] is +1 when dragging right widens the pane (handle on its
/// right edge) and -1 when dragging left does (handle on its left edge); the
/// line sits at that same edge.
class PaneResizeHandle extends StatefulWidget {
  const PaneResizeHandle({
    super.key,
    required this.width,
    required this.min,
    required this.max,
    required this.grow,
    required this.onResize,
    required this.onEnd,
    required this.onReset,
  });
  final double width, min, max, grow;
  final ValueChanged<double> onResize;
  final VoidCallback onEnd, onReset;

  @override
  State<PaneResizeHandle> createState() => _PaneResizeHandleState();
}

class _PaneResizeHandleState extends State<PaneResizeHandle> {
  bool _hover = false;
  bool _drag = false;
  double _startX = 0;
  double _startWidth = 0;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final w = widget;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onDoubleTap: w.onReset,
        onHorizontalDragStart: (d) {
          _startX = d.globalPosition.dx;
          _startWidth = w.width;
          setState(() => _drag = true);
        },
        onHorizontalDragUpdate: (d) => w.onResize(
          (_startWidth + w.grow * (d.globalPosition.dx - _startX)).clamp(
            w.min,
            w.max,
          ),
        ),
        onHorizontalDragEnd: (_) {
          setState(() => _drag = false);
          w.onEnd();
        },
        onHorizontalDragCancel: () => setState(() => _drag = false),
        child: SizedBox(
          width: t.sizes.resizeHit,
          child: Align(
            alignment: w.grow > 0
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: SizedBox(
              width: t.sizes.resizeLine,
              child: Container(color: _hover || _drag ? t.accent : null),
            ),
          ),
        ),
      ),
    );
  }
}
